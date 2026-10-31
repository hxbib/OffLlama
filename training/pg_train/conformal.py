"""Conformal risk control for the Reflex escalation threshold tau (mirrors core/Sources/PocketCore/Conformal.swift).

Guarantee: P( P(wrong | conf >= tau) <= alpha ) >= 1 - delta, exchangeable calibration/test data.
Bound: Learn-Then-Test (Angelopoulos et al. 2021, arXiv 2110.01052): exact binomial p-value
p = P(Bin(n_tau, alpha) <= k_tau) per tau on a FIXED grid 0.01..0.99, Bonferroni at delta/K; smallest certified tau wins.
Motivation: Conformal Cascade (arXiv 2607.25018), CR2 (arXiv 2605.12001).

Recalibrate after each distillation round from any scored eval JSON (eval/score_decisions.py output, rows with conf/ok):
  python -m pg_train.conformal --results ../eval/results/llama32-1b-base.json --alpha 0.05 --delta 0.1 \
      [--profile out/calibration.json]   # writes defaultTau (or 1.01 = escalate all if nothing certifies)
"""
import argparse, json, math
from pathlib import Path

GRID = [i / 100 for i in range(1, 100)]


def binom_cdf(k, n, p):
    if k < 0: return 0.0
    if k >= n or p <= 0: return 1.0
    if p >= 1: return 0.0
    return min(1.0, sum(math.exp(math.lgamma(n + 1) - math.lgamma(i + 1) - math.lgamma(n - i + 1) + i * math.log(p) + (n - i) * math.log1p(-p)) for i in range(k + 1)))


def cp_upper(k, n, delta):
    if n == 0 or k >= n: return 1.0
    lo, hi = k / n, 1.0
    for _ in range(100):
        m = (lo + hi) / 2
        if binom_cdf(k, n, m) > delta: lo = m
        else: hi = m
    return hi


def calibrate(conf, ok, alpha=0.05, delta=0.1, grid=GRID):
    n = len(conf); level = delta / len(grid)
    for tau in sorted(grid):
        idx = [i for i in range(n) if conf[i] >= tau]
        if not idx: continue
        e = sum(not ok[i] for i in idx); p = binom_cdf(e, len(idx), alpha)
        if p <= level:
            return {"tau": tau, "alpha": alpha, "delta": delta, "n": n, "handled": len(idx), "errors": e,
                    "handled_share": len(idx) / n, "empirical_error": e / len(idx), "error_upper_bound": cp_upper(e, len(idx), level), "p_value": p}
    return {"tau": None, "alpha": alpha, "delta": delta, "n": n, "handled": 0, "errors": 0, "handled_share": 0.0,
            "empirical_error": None, "error_upper_bound": None, "p_value": None,
            "min_rows_needed_zero_errors": math.ceil(math.log(level) / math.log1p(-alpha))}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", required=True); ap.add_argument("--alpha", type=float, default=0.05)
    ap.add_argument("--delta", type=float, default=0.1); ap.add_argument("--profile"); ap.add_argument("--out")
    a = ap.parse_args()
    d = json.loads(Path(a.results).read_text()); rows = d["rows"]
    r = calibrate([x["conf"] for x in rows], [bool(x["ok"]) for x in rows], a.alpha, a.delta)
    r["model"] = d.get("model"); r["source"] = a.results
    print(json.dumps(r, indent=1))
    if a.out: Path(a.out).write_text(json.dumps(r, indent=1))
    if a.profile:
        p = Path(a.profile); prof = json.loads(p.read_text()) if p.exists() else {"temperature": {}, "tau": {}}
        prof["defaultTau"] = r["tau"] if r["tau"] is not None else 1.01; prof["tau"] = {}  # per-type taus aren't certified
        prof["conformal"] = {k: r[k] for k in ("alpha", "delta", "n", "handled_share", "error_upper_bound")}
        p.write_text(json.dumps(prof, indent=1))


if __name__ == "__main__":
    main()
