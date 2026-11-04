"""Convert Spark phone labels to comparison-ready trainer exports. No spend.

Joins spark_phone_label output to its input file by ID, verifying type,
candidates, option mapping, and vote completeness. Spark trainer rows carry
the majority letter plus smoothed sample frequencies (alpha=0.5) labelled as
such; rows without at least 2 valid draws or with a top vote share below 0.6
are dropped and counted, never imputed. Also emits a paired-comparison table
against a Glimmer label file when supplied (agreement on identical contexts).
"""
import argparse
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import spark_phone_common as C


def sha_file(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def convert(inputs, labels, src, min_share=0.6):
    by_id = {}
    stats = Counter()
    for lab in labels:
        if lab["id"] in by_id:
            stats["duplicate_label_id"] += 1
        by_id[lab["id"]] = lab
    rows = []
    for inp in inputs:
        iid = inp["id"]
        lab = by_id.get(iid)
        if lab is None:
            stats["missing_label"] += 1
            continue
        typ = inp.get("reflex_type") or inp.get("type") or inp.get("decision_type")
        if lab.get("reflex_type") != typ:
            stats["type_mismatch"] += 1
            continue
        if (lab.get("candidates") or None) != (inp.get("candidates") or None):
            stats["candidates_mismatch"] += 1
            continue
        oset = C.extended_get_set(typ, inp.get("candidates"))
        if lab.get("option_ids") != C.option_ids_for(oset):
            stats["option_map_mismatch"] += 1
            continue
        if lab.get("hard_letter") is None or lab.get("n_valid", 0) < 2:
            stats["drop_insufficient_valid_draws"] += 1
            continue
        soft = lab.get("soft_smoothed_alpha0.5")
        if not soft:
            stats["drop_no_soft"] += 1
            continue
        top_share = max(lab["sample_frequencies"].values())
        if top_share < min_share:
            stats["drop_low_top_share"] += 1
            continue
        rows.append({
            "id": iid, "type": typ, "context": inp["context"],
            "candidates": inp.get("candidates"), "target": lab["hard_letter"],
            "soft": soft, "target_kind": "spark_vote_frequency_alpha0.5",
            "teacher_conf": float(soft[lab["hard_letter"]]),
            "vote_counts": lab["vote_counts"], "n_valid": lab["n_valid"],
            "weight": 1.0, "teacher": C.TEACHER, "src": src,
            "contract_id": inp.get("contract_id"), "group_id": inp.get("group_id"),
        })
        stats["kept"] += 1
    for lid in by_id:
        if lid not in {i["id"] for i in inputs}:
            stats["label_without_input"] += 1
    return rows, dict(stats)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--inputs", required=True)
    ap.add_argument("--labels", required=True)
    ap.add_argument("--src", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--glimmer-labels", default="",
                    help="optional Glimmer labels JSONL with id/top_letter for pairing")
    ap.add_argument("--report", default="")
    a = ap.parse_args(argv)
    inputs = [json.loads(l) for l in Path(a.inputs).read_text().splitlines() if l.strip()]
    labels = [json.loads(l) for l in Path(a.labels).read_text().splitlines() if l.strip()]
    rows, stats = convert(inputs, labels, a.src)
    out = Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(".jsonl.tmp")
    with open(tmp, "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
    tmp.replace(out)
    report = {"inputs": a.inputs, "inputs_sha256": sha_file(a.inputs),
              "labels": a.labels, "labels_sha256": sha_file(a.labels),
              "out": str(out), "out_sha256": sha_file(out), "out_rows": len(rows),
              "stats": stats,
              "note": "soft = Laplace-smoothed (alpha=0.5) empirical vote frequencies; not teacher probabilities"}
    if a.glimmer_labels and Path(a.glimmer_labels).exists():
        glim = {json.loads(l)["id"]: json.loads(l)
                for l in Path(a.glimmer_labels).read_text().splitlines() if l.strip()}
        spark = {r["id"]: r for r in labels}
        both = [i for i in spark if i in glim and spark[i].get("hard_letter")]
        agree = sum(1 for i in both if spark[i]["hard_letter"] == glim[i].get("top_letter"))
        report["paired_glimmer"] = {"n_paired": len(both), "n_agree": agree,
                                    "agreement": (agree / len(both)) if both else None,
                                    "glimmer_labels_sha256": sha_file(a.glimmer_labels)}
    if a.report:
        Path(a.report).write_text(json.dumps(report, indent=1))
    print(json.dumps(report, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
