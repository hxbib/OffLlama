#!/usr/bin/env python3
"""Merge teacher-graded escalations into the next round's distillation train file.
Rows take the exact schema lora_gpu.py / lora_r2.py consume: id, type, context, candidates, target, soft, teacher_conf, weight, teacher.
Filters: teacher letter mass >= 0.5 (logprob teachers) and teacher confidence >= --min-conf (default 0.6); exact + near
dedupe against EVERY eval item (training/local_teacher/dedupe.py) and against the previous train rows.
Weights: 1.0 for Glimmer logprob labels; --spark-weight (default 0.8) for vote-frequency labels; both multiplied by
teacher confidence when --conf-weight is set."""
import argparse, json, sys, collections
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "training"), str(ROOT / "training/local_teacher")]
import dedupe as D
ap = argparse.ArgumentParser()
ap.add_argument("--prev", required=True); ap.add_argument("--labels", required=True, nargs="+"); ap.add_argument("--out", required=True)
ap.add_argument("--min-conf", type=float, default=0.6); ap.add_argument("--spark-weight", type=float, default=0.8)
ap.add_argument("--conf-weight", action="store_true"); a = ap.parse_args()
prev = [json.loads(l) for l in open(a.prev) if l.strip()]
seen = {(r["type"], r["context"].strip()) for r in prev}
stat = collections.Counter(kept_prev=len(prev)); new = []
for path in a.labels:
    for l in open(path):
        if not l.strip(): continue
        r = json.loads(l); lab = r.get("label") or {}
        if not lab.get("probs"): stat["drop_no_probs"] += 1; continue
        if lab.get("letter_mass") is not None and lab["letter_mass"] < 0.5: stat["drop_low_letter_mass"] += 1; continue
        if lab.get("confidence", 0) < a.min_conf: stat[f"drop_lowconf_{r['type']}"] += 1; continue
        key = (r["type"], r["context"].strip())
        if key in seen: stat["drop_dup_prev"] += 1; continue
        seen.add(key)
        is_vote = "votes" in lab or "sample-k" in str(lab.get("mode", ""))
        w = (a.spark_weight if is_vote else 1.0) * (lab["confidence"] if a.conf_weight else 1.0)
        cand = r.get("candidates")
        if cand is None and r["type"] in ("contactPick", "eventPick"): cand = [i for i in r["option_ids"] if i != "ask"]
        new.append({"id": f"loop-{r['id']}", "type": r["type"], "context": r["context"], "candidates": cand, "target": lab["letter"],
                    "soft": lab["probs"], "teacher_conf": lab["confidence"], "weight": round(w, 3), "teacher": lab["teacher"],
                    "source": "phone_escalation", "student_conf": r.get("confidence")})
kept, dropped = D.check(new, D.eval_items())
stat["drop_eval_overlap"] = len(dropped); stat["kept_new"] = len(kept)
rows = prev + kept
open(a.out, "w").write("".join(json.dumps(x) + "\n" for x in rows))
stat["total"] = len(rows); stat["new_per_type"] = dict(collections.Counter(r["type"] for r in kept))
print(json.dumps(stat, indent=1))
