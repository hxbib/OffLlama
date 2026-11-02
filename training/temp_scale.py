"""Single-temperature scaling fit on the CALIBRATION split only (NLL grid search over T on the post-cc letter logits 'lp'),
then applied unchanged to cal and test. argmax (pred/ok) is invariant; only conf changes. Writes <stem>_ts.<split>.json.
  python training/temp_scale.py eval/results/after_floor_nv2   # needs .calibration_split.json and .test.json with 'lp' rows"""
import json, math, sys
def sm(v, T):
    m = max(x / T for x in v); e = [math.exp(x / T - m) for x in v]; s = sum(e); return [x / s for x in e]
stem = sys.argv[1]
cal = json.load(open(stem + ".calibration_split.json"))["rows"]; test = json.load(open(stem + ".test.json"))["rows"]
def nll(rows, T): return -sum(math.log(max(sm(r["lp"], T)[r["lp"].index(max(r["lp"]))] if r["ok"] else 1 - sm(r["lp"], T)[r["lp"].index(max(r["lp"]))], 1e-12)) for r in rows) / len(rows)
# full multiclass NLL needs gold index; rows lack it, so use the binary correct/incorrect NLL of top confidence (top-label calibration)
grid = [round(0.05 * i, 2) for i in range(4, 101)]
T = min(grid, key=lambda t: nll(cal, t))
out = {"T": T, "nll_cal_T1": nll(cal, 1.0), "nll_cal_T": nll(cal, T)}
for rows, n in ((cal, "calibration_split"), (test, "test")):
    new = [{**r, "conf": max(sm(r["lp"], T))} for r in rows]
    json.dump({"rows": new, "temperature": T}, open(f"{stem}_ts.{n}.json", "w"))
print(json.dumps(out))
