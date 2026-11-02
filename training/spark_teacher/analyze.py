"""Teacher QC + old/new teacher agreement. Writes out/qc_report_spark.json and out/agreement.json."""
import json, collections, math
ld = lambda f: [json.loads(l) for l in open(f)]
cal = {r["id"]: r for r in ld("out/cal_labels_spark.jsonl")}
qc_ids = [r["id"] for r in ld("../local_teacher/out/qc_items.jsonl")]
glq = {r["id"]: r for r in ld("../local_teacher/out/qc_labels.jsonl")}
def score(rows):
    by = collections.defaultdict(lambda: [0, 0])
    for r in rows: ok = r["teacher_option"] == r["gold"]; by[r["type"]][0] += ok; by[r["type"]][1] += 1
    a = sum(v[0] for v in by.values()); n = sum(v[1] for v in by.values())
    return {"N": n, "agree": a, "overall": round(a / n, 3), "per_type": {k: {"agree": v[0], "n": v[1], "rate": round(v[0] / v[1], 3)} for k, v in sorted(by.items())}}
qc = score([cal[i] for i in qc_ids]); qc["teacher"] = "muse-spark-open@baseten"
json.dump(qc, open("out/qc_report_spark.json", "w"), indent=1)
calq = score(list(cal.values()))
# old vs new on train (distill_train rows carry Glimmer target/soft)
tr = ld("out/train_labels_spark.jsonl"); ag = collections.defaultdict(lambda: [0, 0]); tv = []
for r in tr:
    if not r["label"]["letter"]: continue
    ok = r["label"]["letter"] == r["target"]; ag[r["type"]][0] += ok; ag[r["type"]][1] += 1
    L = sorted(set(r["soft"]) | set(r["label"]["probs"])); tv.append(0.5 * sum(abs(r["soft"].get(l, 0) - r["label"]["probs"].get(l, 0)) for l in L))
# extra rows that Glimmer also labeled in the (unshipped) nv2 experiment
try: g2 = {r["id"]: r for r in ld("../local_teacher/out/nv2/nv2_labels.jsonl")}
except FileNotFoundError: g2 = {}
ex = ld("out/extra_labels_spark.jsonl"); ov = [(r, g2[r["id"]]) for r in ex if r["id"] in g2 and r["label"]["letter"] and g2[r["id"]]["label"]["letter"]]
a = sum(v[0] for v in ag.values()); n = sum(v[1] for v in ag.values())
out = {"train_892_top1_agreement": {"agree": a, "n": n, "rate": round(a / n, 3), "per_type": {k: round(v[0] / v[1], 3) for k, v in sorted(ag.items())},
        "mean_total_variation": round(sum(tv) / len(tv), 3)},
       "extra_nudge_overlap_with_glimmer_nv2": {"n": len(ov), "agree": sum(x["label"]["letter"] == y["label"]["letter"] for x, y in ov)},
       "spark_vs_gold_qc50": {k: qc[k] for k in ("N", "agree", "overall")}, "glimmer_vs_gold_qc50": json.load(open("../local_teacher/out/qc_report.json"))["overall"],
       "glimmer_qc50_per_type": {k: v["rate"] for k, v in json.load(open("../local_teacher/out/qc_report.json"))["per_type"].items()},
       "spark_vs_gold_cal180": calq,
       "parse_fail_rows": sum(1 for r in tr + ex if not r["label"]["letter"]),
       "mean_spark_conf_train": round(sum(r["label"]["confidence"] or 0 for r in tr) / len(tr), 3)}
json.dump(out, open("out/agreement.json", "w"), indent=1); print(json.dumps(out, indent=1))
