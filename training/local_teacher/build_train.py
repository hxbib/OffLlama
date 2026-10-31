"""Glimmer labels -> distillation rows. Drops rows where the teacher put <50% mass on letter tokens; per-type weight
= QC agreement rate (types with QC agreement < 0.4 are dropped, documented in the output stats)."""
import json, sys, collections
labels, qc, out = sys.argv[1], sys.argv[2], sys.argv[3]
Q = json.load(open(qc))["per_type"]
rows, stat = [], collections.Counter()
for l in open(labels):
    r = json.loads(l); lab = r["label"]; t = r["type"]
    if not lab.get("probs") or lab["letter_mass"] < 0.5: stat["drop_low_letter_mass"] += 1; continue
    w = Q.get(t, {}).get("rate", 1.0)
    if w < 0.4: stat[f"drop_type_{t}"] += 1; continue
    rows.append({"id": r["id"], "type": t, "context": r["context"], "candidates": r.get("candidates"), "target": lab["letter"],
                 "soft": lab["probs"], "teacher_conf": lab["confidence"], "weight": round(w, 3), "teacher": lab["teacher"]})
    stat["kept"] += 1
open(out, "w").write("".join(json.dumps(x) + "\n" for x in rows))
print(json.dumps(stat))
