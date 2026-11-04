"""Round-2 train set R2-A = 892 Glimmer rows (training/local_teacher/out/distill_train.jsonl, real soft probs kept)
+ Nov-1 Spark extra weak-type rows (training/spark_teacher/out/extra_labels_spark.jsonl) passing the same filter
+ new round-2 Spark rows (training/round2/out/labels_round2.jsonl).
Spark soft target = vote counts + ALPHA Laplace smoothing over the options (never one-hot), renormalised.
Filter: drop Spark rows whose top-vote share < 0.6 (teacher unsure) or with < 2 valid votes. Spark weight = 1.0
(Spark QC agreement vs gold: 49/50, cal180 0.989). Asserts zero overlap with eval (dedupe.check vs ALL eval/**/*.jsonl,
which includes eval/gold/gold_all.jsonl) and zero context overlap with cal180. Never reads gold_test.
  python3 training/round2/build_round2.py [--labels ...] [--out training/round2/out/r2a_train.jsonl]"""
import argparse, collections, json, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent; ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "training")); sys.path.insert(0, str(ROOT / "training/local_teacher"))
from pg_train import prompts
import dedupe as D
ap = argparse.ArgumentParser()
ap.add_argument("--labels", default=str(HERE / "out/labels_round2.jsonl"))
ap.add_argument("--out", default=str(HERE / "out/r2a_train.jsonl")); ap.add_argument("--alpha", type=float, default=0.5)
ap.add_argument("--min-top", type=float, default=0.6)
ap.add_argument("--impute-k", type=int, default=0, help="R2-B: early-stopped unanimous rows (k<k_max, all votes equal) are imputed to k_max "
                "unanimous votes (Nov-1 k=8 data: P(votes 3-5 agree | votes 1-2 agree) = 850/866 = 0.982)")
ap.add_argument("--stats", default=str(HERE / "out/build_stats_round2.json")); a = ap.parse_args()
stat = collections.Counter(); per = collections.defaultdict(collections.Counter)
glim = [json.loads(l) for l in open(ROOT / "training/local_teacher/out/distill_train.jsonl")]
for r in glim: per[r["type"]]["glimmer_kept"] += 1


def spark_row(r, src):
    lab = r["label"]; t = r["type"]; s = prompts.get_set(t, r.get("candidates")); L = prompts.letters(s)
    votes = [v for v in lab["votes"] if v]
    per[t][f"{src}_in"] += 1
    if a.impute_k and lab.get("k_max") and len(lab["votes"]) < a.impute_k and len(votes) == len(lab["votes"]) and len(set(votes)) == 1:
        votes = [votes[0]] * a.impute_k; lab = {**lab, "votes": votes}; per[t][f"{src}_imputed_to_k{a.impute_k}"] += 1
    if len(votes) < 2: per[t][f"{src}_drop_fewvotes"] += 1; return None
    cnt = collections.Counter(votes); top, c = cnt.most_common(1)[0]
    share = c / len(lab["votes"])  # share of ALL draws (unparsed draws count against the teacher)
    if share < a.min_top: per[t][f"{src}_drop_top<{a.min_top}"] += 1; return None
    tot = len(votes) + a.alpha * len(L)
    soft = {l: (cnt.get(l, 0) + a.alpha) / tot for l in L}
    per[t][f"{src}_kept"] += 1
    return {"id": r["id"], "type": t, "context": r["context"], "candidates": r.get("candidates"), "target": top, "soft": soft,
            "teacher_conf": share, "weight": 1.0, "teacher": lab["teacher"], "votes": len(lab["votes"]), "src": src}


extra = [x for x in (spark_row(json.loads(l), "spark_nov1_extra") for l in open(ROOT / "training/spark_teacher/out/extra_labels_spark.jsonl")) if x]
new, seen_ids = [], set()
for l in open(a.labels):
    r = json.loads(l)
    if r["id"] in seen_ids: continue
    seen_ids.add(r["id"]); x = spark_row(r, "spark_r2")
    if x: new.append(x)
for r in glim: r.setdefault("src", "glimmer"); r["teacher_conf"] = r.get("teacher_conf", max(r["soft"].values()))
rows = glim + extra + new
# frozen-eval guard + cal180 guard
kept, dropped = D.check(rows, D.eval_items())
cal_ctx = {json.loads(l)["context"] for l in open(ROOT / "eval/gold/gold_calibration.jsonl")}
gold_ctx = {json.loads(l)["context"] for l in open(ROOT / "eval/gold/gold_all.jsonl")}
assert not any(r["context"] in cal_ctx or r["context"] in gold_ctx for r in kept), "eval overlap"
stat["dropped_dedupe_vs_eval"] = len(dropped)
ctx_seen, final = set(), []
for r in kept:
    if r["context"] in ctx_seen and r.get("src") != "glimmer": stat["dropped_dup_context"] += 1; continue
    ctx_seen.add(r["context"]); final.append(r)
Path(a.out).write_text("".join(json.dumps(r) + "\n" for r in final))
stat["rows"] = len(final); stat.update({f"src_{k}": v for k, v in collections.Counter(r["src"] for r in final).items()})
out = {"out": str(a.out), "alpha": a.alpha, "min_top_share": a.min_top, "stats": dict(stat),
       "per_type_final": dict(collections.Counter(r["type"] for r in final)), "per_type": {t: dict(c) for t, c in sorted(per.items())},
       "dedupe_dropped": [{"id": d["id"], "why": d["_dedupe"]} for d in dropped][:50]}
out["impute_k"] = a.impute_k
Path(a.stats).write_text(json.dumps(out, indent=1)); print(json.dumps(out["stats"]), json.dumps(out["per_type_final"]))
