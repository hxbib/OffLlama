"""Spark labels -> distillation rows, same rules as local_teacher/build_train.py but with Spark's own QC report
(per-type weight = Spark QC50 agreement; drop types < 0.4; on types < 1.0 drop rows with confidence < 0.7;
letter_mass here = fraction of the K samples that parsed to a valid letter)."""
import json, sys, collections
import os; Q = json.load(open(os.environ.get("QC_REPORT", "out/qc_report_spark.json")))["per_type"]; rows, stat = [], collections.Counter()
for f in sys.argv[1:-1]:
    for l in open(f):
        r = json.loads(l); lab = r["label"]; t = r["type"]
        if not lab.get("probs") or lab["letter_mass"] < 0.5: stat["drop_low_letter_mass"] += 1; continue
        w = Q.get(t, {}).get("rate", 1.0)
        if w < 0.4: stat[f"drop_type_{t}"] += 1; continue
        if w < 1.0 and lab["confidence"] < 0.7: stat[f"drop_lowconf_{t}"] += 1; continue
        rows.append({"id": r["id"], "type": t, "context": r["context"], "candidates": r.get("candidates"), "target": lab["letter"],
                     "soft": lab["probs"], "teacher_conf": lab["confidence"], "weight": round(w, 3), "teacher": lab["teacher"]})
        stat["kept"] += 1; stat[f"kept_{t}"] += 1
open(sys.argv[-1], "w").write("".join(json.dumps(x) + "\n" for x in rows)); print(json.dumps(stat))
