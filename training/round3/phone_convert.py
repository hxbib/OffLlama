"""Convert Glimmer label files to trainer rows. No spend.

Controlled set: joins /tmp glimmer-v2 labels to target_comparison_inputs
by id, verifying prompt identities via distribution completeness.
Phone/broader sets: joins phone_label outputs to their input files.
Invalid, censored, low-mass, or incomplete targets are dropped and
counted, never imputed. Spark conversion refuses anything but a final
verified fixed-k=5 file; partial votes are never imputed to full votes.
"""
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import phone_contracts as PC

TEACHER_BF16 = "muse-glimmer-30b-bf16-r3"


def load_jsonl(p):
    return [json.loads(l) for l in Path(p).read_text().splitlines() if l.strip()]


def sha_file(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def convert_glimmer(inputs, labels, src, require_ids=None):
    """Return (trainer_rows, stats). Inputs carry id/type/context/candidates."""
    by_id = {}
    stats = Counter()
    for lab in labels:
        if lab["id"] in by_id:
            stats["duplicate_label_id"] += 1
        by_id[lab["id"]] = lab
    rows = []
    seen = set()
    for inp in inputs:
        iid = inp["id"]
        seen.add(iid)
        typ = inp.get("type") or inp.get("reflex_type") or inp.get("decision_type")
        lab = by_id.get(iid)
        if lab is None:
            stats["missing_label"] += 1
            continue
        if lab["type"] != typ:
            stats["type_mismatch"] += 1
            continue
        if (lab.get("candidates") or None) != (inp.get("candidates") or None):
            stats["candidates_mismatch"] += 1
            continue
        if lab.get("status") not in ("valid_complete", "valid_bounded") or not lab.get("usable"):
            stats[f"drop_{lab.get('status')}"] += 1
            continue
        dist = lab.get("distribution")
        if not dist or lab.get("top_letter") is None:
            stats["drop_no_distribution"] += 1
            continue
        oset = PC.extended_get_set(typ, inp.get("candidates"))
        want_ids = PC.option_ids_for(oset)
        if lab.get("option_ids") != want_ids:
            stats["option_map_mismatch"] += 1
            continue
        letters = PC.letters_for(oset)
        if sorted(dist.keys()) != sorted(letters):
            stats["letter_set_mismatch"] += 1
            continue
        total = sum(dist.values())
        if not (0.99 <= total <= 1.01):
            stats["distribution_not_normalized"] += 1
            continue
        top = max(dist, key=dist.get)
        if top != lab["top_letter"]:
            stats["top_mismatch"] += 1
            continue
        rows.append({
            "id": iid, "type": typ, "context": inp["context"],
            "candidates": inp.get("candidates"), "target": top,
            "soft": {k: float(dist[k]) for k in letters},
            "teacher_conf": float(dist[top]), "weight": 1.0,
            "teacher": TEACHER_BF16, "src": src,
        })
        stats["kept"] += 1
    for lid in by_id:
        if lid not in seen:
            stats["label_without_input"] += 1
    if require_ids is not None and seen != set(require_ids):
        stats["input_id_set_mismatch"] += 1
    return rows, dict(stats)


def convert_spark_final(inputs, draws, contexts_by_id):
    """Fixed-k=5 vote frequencies, alpha=0.5, no imputation.

    Refuses unless every input has exactly 5 SETTLED draws. Returns
    (rows, stats) or raises ValueError with the refusal reason.
    """
    settled = Counter()
    votes = {}
    for d in draws:
        if d.get("state") == "SETTLED" and d.get("parsed_letter"):
            cid = d["context_id"]
            settled[cid] += 1
            votes.setdefault(cid, []).append(d["parsed_letter"])
    missing = [i["id"] for i in inputs if i["id"] not in settled and i["id"] not in votes]
    attempted = {d["context_id"] for d in draws}
    if len(attempted) != len(inputs) or missing:
        raise ValueError(
            f"spark not final: attempted={len(attempted)} inputs={len(inputs)} "
            f"missing={len(missing)}; refusing partial file")
    # Final file: contexts with <5 valid (malformed) draws are dropped
    # and counted. Unseen votes are never imputed.
    import sys as _s
    _s.path.insert(0, str(ROOT / "training"))
    from pg_train import prompts as _p
    rows, stats = [], Counter()
    for inp in inputs:
        typ = inp.get("type") or inp.get("reflex_type") or inp.get("decision_type")
        oset = PC.extended_get_set(typ, inp.get("candidates"))
        letters = PC.letters_for(oset)
        if len(votes.get(inp["id"], [])) != 5:
            stats["drop_incomplete_valid_votes"] += 1
            continue
        cnt = Counter(votes[inp["id"]])
        top, c = cnt.most_common(1)[0]
        share = c / 5.0
        if share < 0.6:
            stats["drop_low_share"] += 1
            continue
        tot = 5 + 0.5 * len(letters)
        soft = {l: (cnt.get(l, 0) + 0.5) / tot for l in letters}
        rows.append({"id": inp["id"], "type": typ, "context": inp["context"],
                     "candidates": inp.get("candidates"), "target": top,
                     "soft": soft, "teacher_conf": share, "weight": 1.0,
                     "teacher": "muse-spark-open-1026", "src": "spark_r3_fixedk5",
                     "votes": 5})
        stats["kept"] += 1
    return rows, dict(stats)
