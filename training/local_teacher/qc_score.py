"""Agreement of Glimmer (teacher_option) with gold on eval QC items, overall + per type."""
import json, sys, collections
rows = [json.loads(l) for l in open(sys.argv[1])]
by = collections.defaultdict(lambda: [0, 0]); conf = collections.defaultdict(list)
for r in rows:
    ok = r["teacher_option"] == r["gold"]; by[r["type"]][0] += ok; by[r["type"]][1] += 1
    conf["right" if ok else "wrong"].append(r["label"]["confidence"] or 0)
tot = sum(v[0] for v in by.values()), sum(v[1] for v in by.values())
out = {"N": tot[1], "agree": tot[0], "overall": tot[0] / tot[1],
       "per_type": {k: {"agree": v[0], "n": v[1], "rate": round(v[0] / v[1], 3)} for k, v in sorted(by.items())},
       "mean_conf_right": sum(conf["right"]) / max(1, len(conf["right"])), "mean_conf_wrong": sum(conf["wrong"]) / max(1, len(conf["wrong"])),
       "mean_letter_mass": sum(r["label"]["letter_mass"] for r in rows) / len(rows)}
print(json.dumps(out, indent=1))
if len(sys.argv) > 2: open(sys.argv[2], "w").write(json.dumps(out, indent=1))
