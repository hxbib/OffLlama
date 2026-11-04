"""Batched Spark Open utterance generation for phone-action expansion.

The teacher invents utterances + expressed arguments; deterministic contract
validators then decide each row's disposition and accept/reject it. Teacher
prose is an input (the utterance), never a label: decision letters still come
only from spark_phone_label votes, and dispositions come from the compiled
contracts. Rows are train-only, grouped by scenario core, and screened
against frozen held-out groups so no held-out sibling leaks into training.

Usage (paid; requires BASETEN_API_KEY):
  python3 spark_phone_generate.py --state-dir DIR --status status.json \
      --out generated_inputs.jsonl --cap-usd 54.99 --per-cell 4 --gen-per-request 10
"""
import argparse
import hashlib
import json
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import spark_phone_common as C
import spark_phone_store as S

# (family, reflex target style). skillPick rows carry the contract as the
# intended action; disposition is recomputed deterministically at ingest.
CELLS_FAMILIES = ["valid_complete", "missing_required", "invalid_field",
                  "time_difficult", "contact_ambiguous", "unsupported_extra",
                  "cancellation", "privacy_difficult", "hard_negative",
                  "permission", "recovery_failed", "confirmation_risky"]

NOWS = ["Fri 09:00", "Sat 14:30", "Mon 08:15", "Wed 19:40", "Thu 07:05", "Sun 11:20"]


def skill_candidates(contract_id, contracts, rng):
    sys.path.insert(0, str(C.ROOT / "training"))
    titles = {cid: e["capability"]["title"] for cid, e in contracts.items()}
    pool = [c for c in contracts if c != contract_id
            and C.availability(contracts[c]) != "notWired"]
    distract = rng.sample(pool, 6)
    labels = [titles[contract_id]] + [titles[d] for d in distract]
    rng.shuffle(labels)
    return labels


REFLEX_TYPES = ["contactPick", "timing", "eventPick", "confirmBeforeAct",
                "sensitivity", "answerability", "rememberOrNot",
                "notificationTriage", "route", "toolChoice"]
REFLEX_FAMILIES = ["valid_complete", "contact_ambiguous", "time_difficult",
                   "permission", "privacy_difficult", "hard_negative"]


def build_cells(contracts, per_cell, seed=20261105):
    cells = []
    for cid in sorted(contracts):
        if C.availability(contracts[cid]) == "notWired":
            fams = ["valid_complete"]  # unsupported-by-availability examples
        else:
            fams = CELLS_FAMILIES
        for fam in fams:
            for rep in range(per_cell):
                cells.append((cid, fam, rep))
    return cells


def reflex_cells(per_type_batches=2):
    return [(t, f, r) for t in REFLEX_TYPES for f in REFLEX_FAMILIES
            for r in range(per_type_batches)]


def ingest(records, contracts, heldout_cores, seen_cores, start_idx):
    """records: settled generation batch records. Returns (rows, stats)."""
    import random
    rows, stats = [], {"accepted": 0, "rejected": 0}
    idx = start_idx
    for rec in records:
        if rec.get("state") != "SETTLED_OK":
            stats["batch_not_ok"] = stats.get("batch_not_ok", 0) + 1
            continue
        cid, fam = rec["contract_id"], rec["family"]
        entry = contracts[cid]
        for j, item in enumerate(rec["items"]):
            utt = item["utterance"]
            args = item["arguments"]
            rng = random.Random(hashlib.sha256(f"{rec['batch_id']}|{j}".encode()).hexdigest()[:12])
            now = NOWS[rng.randrange(len(NOWS))]
            net = "offline" if rng.random() < 0.33 else "online"
            context = f"Now: {now}\nUser location: home\nNetwork: {net}\nUser: {utt}"
            core = C.core_key(context)
            reason = None
            if core in heldout_cores:
                reason = "heldout_core_overlap"
            elif core in seen_cores:
                reason = "duplicate_core"
            else:
                disp, basis = C.disposition_for(entry, args, utt,
                                                C.FAMILY_FLAGS.get(fam, {}))
                expected = {
                    "valid_complete": {"await_confirmation", "execute_once", "unsupported"},
                    "missing_required": {"clarify_missing"},
                    "invalid_field": {"clarify_invalid"},
                    "time_difficult": {"clarify_invalid", "await_confirmation", "execute_once"},
                    "unsupported_extra": {"clarify_invalid"},
                }.get(fam)
                if expected is not None and disp not in expected:
                    reason = f"disposition_mismatch:{disp}"
            if reason:
                stats["rejected"] += 1
                stats[f"reject_{reason.split(':')[0]}"] = stats.get(f"reject_{reason.split(':')[0]}", 0) + 1
                continue
            seen_cores.add(core)
            cands = skill_candidates(cid, contracts, rng)
            oset = C.extended_get_set("skillPick", cands)
            idx += 1
            rows.append({
                "id": f"sparkphone-{idx:05d}",
                "group_id": "sp-" + hashlib.sha256(
                    f"{cid}|{fam}|{C.norm(utt)}".encode()).hexdigest()[:14],
                "contract_id": cid, "contract_version": entry["capability"]["version"],
                "contract_availability": C.availability(entry),
                "family": fam, "reflex_type": "skillPick",
                "utterance": utt, "context": context, "candidates": cands,
                "option_ids": C.option_ids_for(oset), "fallback_id": "ask",
                "typed_arguments": args,
                "expected_disposition": disp, "deterministic_basis": basis,
                "provenance": {"source": "spark_phone_generation_v1",
                               "template_family": fam,
                               "generation_origin": "teacher_generated_spark_open",
                               "generation_batch": rec["batch_id"],
                               "note": "Spark-generated utterance; disposition is deterministic contract semantics, letters come from Spark votes. Not human gold, not iPhone traces."},
                "label_status": "needs_teacher", "split": "train",
            })
            stats["accepted"] += 1
    return rows, stats


REFLEX_QUESTIONS = {
    "contactPick": "Which contact does the user mean? (candidates: 3-5 contact names with roles)",
    "timing": "When should the requested action happen? (context needs a User request, with or without a stated time/place trigger)",
    "eventPick": "Which calendar event does the user mean? (candidates: 3-5 event titles)",
    "confirmBeforeAct": "Does this action need explicit confirmation first? (context is a User phone-action request)",
    "sensitivity": "Is it acceptable to send this request to a cloud service? (context is a User request, varied privacy)",
    "answerability": "Can a small on-device model answer this without the internet? (context is a User question)",
    "rememberOrNot": "Should the assistant save this to long-term memory? (context is a User statement)",
    "notificationTriage": "How urgent is this incoming notification right now? (context describes a notification plus Now/location)",
    "route": "How should the assistant handle this request? (context includes Network online/offline and a User request)",
    "toolChoice": "Which tool should be used? (context is a User request needing reminder/event/message/contact/memory or none)",
}


def reflex_batch_messages(rtype, family, count, seed_hint):
    user = (
        f"Decision: {REFLEX_QUESTIONS[rtype]}\nStyle: {C.FAMILY_GUIDANCE.get(family, C.FAMILY_GUIDANCE['valid_complete'])}\n"
        f"Write {count} distinct short contexts (seed {seed_hint}). Each context is 2-5 short lines "
        "ending with a 'User: ...' line, except notificationTriage which describes the notification. "
        "For contactPick/eventPick also give \"candidates\": 3-5 short names/titles. "
        'Reply with ONLY a JSON array of {"context": "...", "candidates": [...]} objects (candidates [] when not applicable).'
    )
    return [{"role": "system", "content": C.GEN_SYSTEM},
            {"role": "user", "content": user}]


def parse_reflex_batch(content):
    text = (content or "").strip()
    if text.startswith("```"):
        import re as _re
        text = _re.sub(r"^```(?:json)?\s*", "", text)
        text = _re.sub(r"\s*```$", "", text)
    try:
        data = json.loads(text)
    except Exception:
        import re as _re
        m = _re.search(r"\[.*\]", text, _re.S)
        if not m:
            raise ValueError("no_json_array")
        data = json.loads(m.group(0))
    if not isinstance(data, list) or not data:
        raise ValueError("not_a_nonempty_list")
    out = []
    for obj in data:
        if not isinstance(obj, dict) or not str(obj.get("context") or "").strip():
            raise ValueError(f"bad_object:{obj!r:.80}")
        cands = obj.get("candidates") or []
        if not isinstance(cands, list):
            raise ValueError("bad_candidates")
        out.append({"context": str(obj["context"]).strip(),
                    "candidates": [str(x) for x in cands][:7]})
    return out


def ingest_reflex(records, heldout_cores, seen_cores, start_idx):
    rows, stats = [], {"accepted": 0, "rejected": 0}
    idx = start_idx
    for rec in records:
        if rec.get("state") != "SETTLED_OK":
            continue
        rtype, fam = rec["reflex_type"], rec["family"]
        for item in rec["items"]:
            context = item["context"]
            core = C.core_key(context)
            if core in heldout_cores:
                stats["rejected"] += 1
                stats["reject_heldout_core_overlap"] = stats.get("reject_heldout_core_overlap", 0) + 1
                continue
            if core in seen_cores:
                stats["rejected"] += 1
                stats["reject_duplicate_core"] = stats.get("reject_duplicate_core", 0) + 1
                continue
            if len(context) > 1200:
                stats["rejected"] += 1
                continue
            cands = item["candidates"] or None
            if rtype in ("contactPick", "eventPick") and not (cands and len(cands) >= 2):
                stats["rejected"] += 1
                stats["reject_missing_candidates"] = stats.get("reject_missing_candidates", 0) + 1
                continue
            seen_cores.add(core)
            oset = C.extended_get_set(rtype, cands)
            idx += 1
            rows.append({
                "id": f"sparkphone-{idx:05d}",
                "group_id": "sp-" + hashlib.sha256(
                    f"{rtype}|{fam}|{C.norm(context)}".encode()).hexdigest()[:14],
                "contract_id": None, "contract_version": None,
                "contract_availability": None,
                "family": fam, "reflex_type": rtype,
                "utterance": context.split("User:")[-1].strip(),
                "context": context, "candidates": cands,
                "option_ids": C.option_ids_for(oset), "fallback_id": oset["fallback"],
                "typed_arguments": {}, "expected_disposition": None,
                "deterministic_basis": None,
                "provenance": {"source": "spark_phone_generation_v1",
                               "template_family": fam,
                               "generation_origin": "teacher_generated_spark_open",
                               "generation_batch": rec["batch_id"],
                               "note": "Spark-generated context; letters come from Spark votes. Not human gold, not iPhone traces."},
                "label_status": "needs_teacher", "split": "train",
            })
            stats["accepted"] += 1
    return rows, stats


def heldout_cores_from(paths):
    cores = set()
    for p in paths:
        if p and Path(p).exists():
            for r in C.load_jsonl(p):
                ctx = r.get("context") or ""
                if ctx:
                    cores.add(C.core_key(ctx))
                if r.get("utterance"):
                    cores.add(C.core_key("User: " + r["utterance"]))
    return cores


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--state-dir", required=True)
    ap.add_argument("--status", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--cap-usd", type=float, default=54.99)
    ap.add_argument("--per-cell", type=int, default=4)
    ap.add_argument("--gen-per-request", type=int, default=10)
    ap.add_argument("--workers", type=int, default=S.MAX_INFLIGHT)
    ap.add_argument("--max-tokens", type=int, default=2048)
    ap.add_argument("--max-attempts", type=int, default=3)
    ap.add_argument("--rpm", type=float, default=S.MAX_RPM)
    ap.add_argument("--heldout", nargs="*", default=[],
                    help="frozen dev/calfit/report/gold files screened for overlap")
    ap.add_argument("--limit-batches", type=int, default=0)
    a = ap.parse_args(argv)

    contracts = C.load_contracts()
    cells = build_cells(contracts, a.per_cell)
    state_dir = Path(a.state_dir)
    with S.single_writer(state_dir):
        store = S.Store(state_dir, a.cap_usd)
        done = S.load_done_batches(state_dir, "gen_batches.jsonl")
        todo = []
        for cid, fam, rep in cells:
            bid = f"gen-{cid}-{fam}-{rep:02d}"
            rec = done.get(bid)
            if rec and rec.get("state") == "SETTLED_OK":
                continue
            if rec is not None:
                k = 1
                while f"{bid}-r{k}" in done:
                    k += 1
                bid = f"{bid}-r{k}"
            todo.append((bid, cid, fam, rep))
        for rtype, fam, rep in reflex_cells():
            bid = f"genr-{rtype}-{fam}-{rep:02d}"
            rec = done.get(bid)
            if rec and rec.get("state") == "SETTLED_OK":
                continue
            if rec is not None:
                k = 1
                while f"{bid}-r{k}" in done:
                    k += 1
                bid = f"{bid}-r{k}"
            todo.append((bid, rtype, fam, rep))
        if a.limit_batches:
            todo = todo[: a.limit_batches]
        S.write_status(store, a.status, "generating",
                       {"cells_total": len(cells), "batches_pending": len(todo),
                        "per_cell": a.per_cell, "gen_per_request": a.gen_per_request})
        key = os.environ.get("BASETEN_API_KEY")
        if todo and not key:
            raise SystemExit("BASETEN_API_KEY missing (source the env file; never pass keys as flags)")
        denied = [0]
        if todo:
            throttle = S.Throttle(a.rpm)
            transport = S.real_transport(key, throttle)

            def work(unit):
                bid, cid, fam, rep = unit
                is_reflex = bid.startswith("genr-")
                messages = (reflex_batch_messages(cid, fam, a.gen_per_request, f"{cid}-{fam}-{rep}")
                            if is_reflex else
                            C.generation_batch_messages(
                                cid, contracts[cid], fam, a.gen_per_request, f"{cid}-{fam}-{rep}"))
                outcome, body = S.run_batch_call(
                    store, transport, "generate", bid, messages, a.max_tokens,
                    max_attempts=a.max_attempts)
                if outcome == "budget_denied":
                    denied[0] += 1
                    return bid
                rec = {"batch_id": bid, "kind": "generate",
                       ("reflex_type" if is_reflex else "contract_id"): cid,
                       "family": fam, "outcome": outcome, "at": time.time()}
                if outcome == "settled" and body is not None:
                    content = None
                    try:
                        content = (body.get("choices") or [{}])[0].get("message", {}).get("content")
                    except Exception:
                        content = None
                    rec["raw_completion"] = content
                    rec["raw_completion_sha256"] = C.sha256_text(content or "")
                    rec["usage"] = body.get("usage")
                    rec["model_returned"] = body.get("model")
                    try:
                        rec["items"] = (parse_reflex_batch(content) if is_reflex else
                                        C.parse_generation_batch(content, a.gen_per_request))
                        rec["state"] = "SETTLED_OK"
                    except ValueError as e:
                        rec["state"] = "SETTLED_PARSE_FAIL"
                        rec["parse_error"] = str(e)
                else:
                    rec["state"] = "FAILED_" + outcome.upper()
                with store.lock:
                    S.append_jsonl(state_dir, "gen_batches.jsonl", rec)
                return bid

            with ThreadPoolExecutor(max_workers=max(1, a.workers)) as ex:
                futs = [ex.submit(work, u) for u in todo]
                for f in as_completed(futs):
                    f.result()
        done = S.load_done_batches(state_dir, "gen_batches.jsonl")
        held = heldout_cores_from(a.heldout)
        seen = set()
        contract_recs = [r for r in done.values() if "contract_id" in r]
        reflex_recs = [r for r in done.values() if "reflex_type" in r]
        rows, stats = ingest(contract_recs, contracts, held, seen, 0)
        rows2, stats2 = ingest_reflex(reflex_recs, held, seen, len(rows))
        rows = rows + rows2
        for k, v in stats2.items():
            stats[k] = stats.get(k, 0) + v if isinstance(v, int) else v
        out_path = Path(a.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = out_path.with_suffix(".jsonl.tmp")
        with open(tmp, "w") as f:
            for r in rows:
                f.write(json.dumps(r) + "\n")
            f.flush()
            os.fsync(f.fileno())
        tmp.replace(out_path)
        S.write_status(store, a.status, "generated_written",
                       {"generated_out": str(out_path),
                        "generated_sha256": C.sha256_file(out_path),
                        "generated_rows": len(rows), "ingest_stats": stats,
                        "heldout_cores_screened": len(held),
                        "budget_denied_batches": denied[0]})
        print(f"generated: {len(rows)} accepted, stats={stats}, "
              f"committed ${store.committed():.4f} / ${a.cap_usd}", flush=True)
        store.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
