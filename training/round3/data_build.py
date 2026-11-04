"""Build the round-3 phone train/dev/cal-fit/report manifests.

Inputs are contexts plus provenance. This script writes no teacher labels:
rows that need a Meta-teacher letter keep label_status=needs_label and
gold=null. Deterministic gold appears only where source semantics or an
explicit contract justify it (SQuAD answer-span presence for the
answerability proxy, BFCL irrelevance -> no_tool_call, Pocket skill
registry examples -> their skill id).

Grouping: a group is the wrapper-stripped normalized core of a context.
Envelope lines (Now:, User location:, Network:) never change the group.
The same group lands in exactly one split, across every Pocket task type.
Prior training contexts (round-2 train files, Glimmer distill, Spark
labels, round-3 matched inputs) and every eval/stress context are
decontamination references: a group matching one can never enter
dev/cal-fit/report, and prior-train groups are not recounted as new train.

Usage:
  python3 training/round3/data_build.py --offline
  python3 training/round3/data_build.py --fetch --clinc-train-new 800 \
      --banking-train 600 --dev-clinc 350 --calfit-clinc 250 \
      --report-banking 350 --report-clinc-test 250 --squad-dev 150 --squad-calfit 150
Fetches use the HF datasets-server rows API (parquet conversion). No
datasets loader, no trust_remote_code, no paid calls.
"""
import argparse, collections, hashlib, json, re, sys, time, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "training" / "local_teacher"))
import dedupe as D  # norm/utter/grams/jac + eval_items (stdlib only)

ENVELOPE = re.compile(r"^(Now:|User location:|Network:)\s")
LETTERS = "ABCDEFGH"


def core_text(context):
    lines = [l for l in context.splitlines() if not ENVELOPE.match(l.strip())]
    return "\n".join(lines).strip()


def group_key(context):
    return "g" + hashlib.sha256(D.norm(core_text(context)).encode()).hexdigest()[:15]


def utter_key(context):
    return D.norm(D.utter(context))


def sha_file(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load_jsonl(path):
    p = Path(path)
    if not p.exists():
        return []
    return [json.loads(l) for l in p.read_text().splitlines() if l.strip()]


def fetch_rows(dataset, config, split, limit, cache_dir):
    """Paginated HF datasets-server fetch. Caches raw pages with hashes."""
    cache_dir = Path(cache_dir); cache_dir.mkdir(parents=True, exist_ok=True)
    tag = re.sub(r"[^A-Za-z0-9]+", "_", f"{dataset}_{config}_{split}")[:80]
    rows, offset = [], 0
    while len(rows) < limit:
        n = min(100, limit - len(rows))
        url = (f"https://datasets-server.huggingface.co/rows?dataset={urllib.request.quote(dataset, safe='')}"
               f"&config={config}&split={split}&offset={offset}&length={n}")
        cache = cache_dir / f"{tag}_{offset}.json"
        if cache.exists():
            payload = json.loads(cache.read_text())
        else:
            payload = None
            for attempt in range(4):
                try:
                    with urllib.request.urlopen(url, timeout=30) as r:
                        payload = json.loads(r.read())
                    break
                except Exception:
                    if attempt == 3:
                        raise
                    time.sleep(2 * (attempt + 1))
            cache.write_text(json.dumps(payload))
        names = None
        for f in payload.get("features", []):
            if f["name"] in ("intent", "label") and f["type"].get("names"):
                names = f["type"]["names"]
        for item in payload.get("rows", []):
            row = dict(item["row"])
            if names:
                for k in ("intent", "label"):
                    if isinstance(row.get(k), int):
                        row[k + "_name"] = names[row[k]]
            rows.append(row)
        if len(payload.get("rows", [])) < n:
            break
        offset += n
    return rows


def pocket_context(utterance, with_network=False):
    u = utterance.strip()
    u = u[0].upper() + u[1:] if u else u
    return (("Network: online\n" if with_network else "") + f"User: {u}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--offline", action="store_true", help="use only repository files and local snapshots")
    ap.add_argument("--fetch", action="store_true")
    ap.add_argument("--cache-dir", default="/tmp/pocket-glimmer-training-scale/phone-bench-r3/hf-cache")
    ap.add_argument("--samples-dir", default="/tmp/pocket-glimmer-training-scale/samples")
    ap.add_argument("--out-dir", default=str(HERE))
    ap.add_argument("--clinc-train-new", type=int, default=800)
    ap.add_argument("--banking-train", type=int, default=600)
    ap.add_argument("--dev-clinc", type=int, default=350)
    ap.add_argument("--calfit-clinc", type=int, default=250)
    ap.add_argument("--report-banking", type=int, default=350)
    ap.add_argument("--report-clinc-test", type=int, default=250)
    ap.add_argument("--squad-dev", type=int, default=150)
    ap.add_argument("--squad-calfit", type=int, default=150)
    ap.add_argument("--synthetic-cap-per-core", type=int, default=4)
    a = ap.parse_args()
    out_dir = Path(a.out_dir); stats = collections.Counter(); notes = []

    # --- decontamination references -------------------------------------
    prior_files = [
        "training/round2/out/r2c_train.jsonl", "training/round2/out/r2a_train.jsonl",
        "training/local_teacher/out/distill_train.jsonl",
        "training/round3/target_comparison_inputs.jsonl", "training/round3/anchor_inputs.jsonl",
    ]
    prior_rows = [r for f in prior_files for r in load_jsonl(ROOT / f) if r.get("context")]
    label_ctx_files = ["training/round2/out/labels_round2.jsonl",
                       "training/spark_teacher/out/extra_labels_spark.jsonl"]
    seen_union_rows = prior_rows + [r for f in label_ctx_files for r in load_jsonl(ROOT / f) if r.get("context")]
    eval_rows = D.eval_items()
    stress_rows = load_jsonl(ROOT / "training/data_scale/out/clinc_oos_test_stress.jsonl")
    prior_groups = {group_key(r["context"]) for r in prior_rows}
    seen_ctx = {r["context"] for r in seen_union_rows}
    eval_groups = {group_key(r["context"]) for r in eval_rows + stress_rows if r.get("context")}
    eval_utters = {utter_key(r["context"]) for r in eval_rows + stress_rows if r.get("context")}

    pool = load_jsonl(ROOT / "training/data_scale/out/pool.jsonl")
    labeled_ids = {r["id"] for r in load_jsonl(ROOT / "training/round2/out/labels_round2.jsonl")}
    unlabeled = [r for r in pool if r["id"] not in labeled_ids]
    stats["pool_rows"] = len(pool); stats["unlabeled_remainder"] = len(unlabeled)

    # Recheck the grounding pass's 83 duplicate contexts independently.
    dup83 = [r for r in unlabeled if r["context"] in seen_ctx]
    stats["recheck_seen_context_duplicates"] = len(dup83)

    train, dev, calfit, report = [], [], [], []
    used_groups = {}  # group -> split that owns it

    def admit(row, split_list, split_name):
        g = row["group_id"]
        if g in prior_groups:
            stats[f"drop_prior_train_group_{split_name}"] += 1; return False
        if g in eval_groups or utter_key(row["context"]) in eval_utters:
            stats[f"drop_eval_group_{split_name}"] += 1; return False
        if g in used_groups and used_groups[g] != split_name:
            stats[f"drop_cross_split_group_{split_name}"] += 1; return False
        used_groups[g] = split_name
        split_list.append(row); return True

    def base_row(rid, dtype, context, source, family, origin, publisher_split,
                 original_label, label_status, gold, gold_basis, transform, candidates=None):
        return {"id": rid, "decision_type": dtype, "context": context,
                "candidates": candidates, "source_id": source, "source_family": family,
                "publisher_split": publisher_split, "original_label": original_label,
                "original_utterance": core_text(context), "group_id": group_key(context),
                "generation_origin": origin, "label_status": label_status,
                "gold": gold, "gold_basis": gold_basis, "transform": transform}

    # --- cleaned old pool -> train (needs_label only) --------------------
    core_counts = collections.Counter()
    for r in unlabeled:
        if r["context"] in seen_ctx:
            stats["drop_seen_context"] += 1; continue
        fam = r.get("source", "synthetic")
        if fam == "synthetic":
            core = group_key(r["context"])
            if core_counts[core] >= a.synthetic_cap_per_core:
                stats["drop_synthetic_template_excess"] += 1; continue
            core_counts[core] += 1
        row = base_row("r3tr-" + r["id"], r["type"], r["context"],
                       {"synthetic": "old_synthetic", "massive": "massive_en_us",
                        "clinc": "clinc_plus", "snips": "snips_2017"}.get(fam, fam),
                       fam, "human" if fam != "synthetic" else "synthetic_generator",
                       "train" if fam != "synthetic" else "generator",
                       None, "needs_label", None, None,
                       "pool_remainder_cleaned_v1", r.get("candidates"))
        row["rejoin_status"] = "not_applicable" if fam == "synthetic" else "unresolved_no_gold_no_eval"
        admit(row, train, "train")
    stats["train_from_pool"] = len(train)
    stats["synthetic_distinct_cores_in_train"] = len(core_counts)

    def safe_fetch(dataset, config, split, limit, notes):
        try:
            return fetch_rows(dataset, config, split, limit, a.cache_dir)
        except Exception as e:
            notes.append(f"fetch_failed:{dataset}:{split}:{type(e).__name__}")
            return []

    # --- optional publisher fetches --------------------------------------
    fetched_hashes = {}
    if a.fetch:
        clinc_val = safe_fetch("clinc/clinc_oos", "plus", "validation", a.dev_clinc + a.calfit_clinc, notes)
        for i, r in enumerate(clinc_val):
            intent = r.get("intent_name") or str(r.get("intent"))
            dtype = "answerability" if i % 3 == 2 else "route"
            row = base_row(f"r3dv-clinc-{i:04d}" if i < a.dev_clinc else f"r3cf-clinc-{i:04d}",
                           dtype, pocket_context(r["text"], with_network=(dtype == "route")),
                           "clinc_plus", "clinc", "human", "validation", intent,
                           "needs_label", None, None, "clinc_val_envelope_v1")
            row["rejoin_status"] = "publisher_intent_retained"
            admit(row, dev if i < a.dev_clinc else calfit, "dev" if i < a.dev_clinc else "calfit")
        clinc_test = [r for r in safe_fetch("clinc/clinc_oos", "plus", "test", a.report_clinc_test * 3, notes)
                      if (r.get("intent_name") or "") != "oos"][:a.report_clinc_test]
        for i, r in enumerate(clinc_test):
            row = base_row(f"r3rp-clinc-{i:04d}", "route", pocket_context(r["text"], with_network=True),
                           "clinc_plus", "clinc", "human", "test_in_scope",
                           r.get("intent_name"), "needs_label", None, None, "clinc_test_envelope_v1")
            row["rejoin_status"] = "publisher_intent_retained"
            admit(row, report, "report")
        bank_tr = safe_fetch("PolyAI/banking77", "default", "train", a.banking_train, notes)
        for i, r in enumerate(bank_tr):
            row = base_row(f"r3tr-banking-{i:04d}", "route", pocket_context(r["text"]),
                           "banking77", "banking77", "human", "train",
                           r.get("label_name"), "needs_label", None, None, "banking_envelope_v1")
            row["rejoin_status"] = "publisher_intent_retained"
            admit(row, train, "train")
        bank_te = safe_fetch("PolyAI/banking77", "default", "test", a.report_banking, notes)
        for i, r in enumerate(bank_te):
            row = base_row(f"r3rp-banking-{i:04d}", "route", pocket_context(r["text"]),
                           "banking77", "banking77", "human", "test",
                           r.get("label_name"), "needs_label", None, None, "banking_envelope_v1")
            row["rejoin_status"] = "publisher_intent_retained"
            admit(row, report, "report")
        # Bounded sample of plus-train for new utterances. A full 15,250-row
        # pull hit HTTP 429 in this run; the failure and this cap are recorded
        # in data_manifest.json notes. Larger pulls reuse the same code path.
        try:
            clinc_tr = safe_fetch("clinc/clinc_oos", "plus", "train", 3000, notes)
        except Exception as e:
            clinc_tr = []
            notes.append(f"clinc_train_fetch_failed:{type(e).__name__}")
        pool_utters = {utter_key(r["context"]) for r in pool}
        added = 0
        for r in clinc_tr:
            if added >= a.clinc_train_new:
                break
            if D.norm(r["text"]) in pool_utters:
                continue
            row = base_row(f"r3tr-clincnew-{added:04d}", "route",
                           pocket_context(r["text"], with_network=True),
                           "clinc_plus", "clinc", "human", "train",
                           r.get("intent_name"), "needs_label", None, None, "clinc_train_envelope_v1")
            row["rejoin_status"] = "publisher_intent_retained"
            if admit(row, train, "train"):
                added += 1
        stats["train_clinc_new"] = added
        _sq_all = safe_fetch("rajpurkar/squad_v2", "squad_v2", "validation",
                             a.squad_dev + a.squad_calfit, notes)
        for name, n in (("dev", a.squad_dev), ("calfit", a.squad_calfit)):
            sq = _sq_all[:n] if name == "dev" else _sq_all[a.squad_dev:a.squad_dev + n]
            if not sq:
                _sp = Path(a.samples_dir) / "squad_v2-rows-sample.json"
                if _sp.exists():
                    _d = json.loads(_sp.read_text())
                    sq = [dict(x["row"]) for x in _d.get("rows", [])][:n]
                    notes.append("squad_fallback_local_sample")
            for i, r in enumerate(sq):
                has = bool(r.get("answers", {}).get("text"))
                passage = " ".join(r["context"].split())[:600]
                row = base_row(f"r3{'dv' if name=='dev' else 'cf'}-squad-{i:04d}", "answerability",
                               f"Passage: {passage}\nUser: {r['question']}",
                               "squad_v2", "squad", "human", "validation", r["id"],
                               "deterministic_gold", "yes" if has else "no",
                               "squad_v2_answer_span_v1", "squad_passage_question_v1")
                row["rejoin_status"] = "publisher_label_retained"
                admit(row, dev if name == "dev" else calfit, name)
    else:
        notes.append("offline_build_no_publisher_fetch")

    # --- BFCL irrelevance snapshot -> report (deterministic abstention) --
    bfcl_path = Path(a.samples_dir) / "BFCL_v3_irrelevance.json"
    if bfcl_path.exists():
        fetched_hashes["bfcl_snapshot"] = sha_file(bfcl_path)
        for i, r in enumerate(load_jsonl(bfcl_path)):
            q = r.get("question") or r.get("query") or ""
            if not q:
                continue
            row = base_row(f"r3rp-bfcl-{i:04d}", "route", pocket_context(str(q)),
                           "bfcl_v3_irrelevance", "bfcl", "expert_contributed", "irrelevance",
                           r.get("id"), "deterministic_gold", "no_tool_call",
                           "bfcl_irrelevance_v1", "bfcl_question_envelope_v1")
            row["rejoin_status"] = "publisher_case_retained"
            admit(row, report, "report")
    else:
        notes.append("bfcl_snapshot_missing_report_rows_absent")

    # --- Pocket skill registry examples -> report (deterministic) --------
    swift = (ROOT / "core/Sources/PocketCore/Skills.swift").read_text()
    blocks = re.split(r'\n\s*s\("', swift)[1:]
    n_skills = 0
    for block in blocks:
        sid = block.split('"', 1)[0]
        m = re.search(r'offline:\s*(?:true|false),\s*\[([^\]]*)\]', block)
        if not m:
            continue
        examples = re.findall(r'"([^"]{3,80})"', m.group(1))
        if not examples:
            continue
        n_skills += 1
        for j, ex in enumerate(examples[:2]):
            row = base_row(f"r3rp-skill-{sid}-{j}", "skillPick", f"User: {ex}",
                           "pocket_skill_registry", "pocket_skills", "developer_example",
                           "registry", sid, "deterministic_gold", sid,
                           "pocket_registry_example_v1", "registry_example_direct_v1")
            row["rejoin_status"] = "registry_definition"
            admit(row, report, "report")
    stats["skill_registry_skills_parsed"] = n_skills

    splits = {"train": train, "dev": dev, "calfit": calfit, "report": report}
    manifest = {"builder": "training/round3/data_build.py", "notes": notes,
                "fetched_snapshot_sha256": fetched_hashes, "stats": dict(stats), "splits": {}}
    for name, rows in splits.items():
        p = out_dir / f"data_{name}.jsonl"
        p.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
        by_type = dict(collections.Counter(r["decision_type"] for r in rows))
        by_status = dict(collections.Counter(r["label_status"] for r in rows))
        manifest["splits"][name] = {"file": p.name, "rows": len(rows),
                                    "groups": len({r["group_id"] for r in rows}),
                                    "sha256": sha_file(p), "by_type": by_type, "by_label_status": by_status}
    (out_dir / "data_manifest.json").write_text(json.dumps(manifest, indent=1))
    print(json.dumps(manifest, indent=1))


if __name__ == "__main__":
    main()
