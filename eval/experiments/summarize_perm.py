"""Summarize run_perm_avg.py output on cal180 vs the single-order T1 baseline; apply the pre-registered selection rule.
Rule (from the Nov 4 brief, fixed before results): perm-avg wins iff [LTT tightest bound improves OR (equal bound AND higher
handled share)] AND ECE <= baseline ECE + 0.01. Baseline = T1 single-order run (repro_nov4_cal180_v2cc.json).
Also derives cyc4 (first min(n,4) cyclic rotations) offline from the cycall per-permutation distributions (they are a prefix),
and reports AURC (area under the risk-coverage curve, lower = better confidence ranking) and single-order run-to-run spread.
Usage: python3 eval/experiments/summarize_perm.py --perm eval/experiments/perm_avg_cal180.json --out eval/experiments/perm_avg_cal180_summary.json"""
import argparse, glob, json, math, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent; ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "training"))
from pg_train import conformal  # noqa: E402
import reliability  # noqa: E402


def aurc(conf, ok):
    o = sorted(range(len(conf)), key=lambda i: -conf[i]); err = 0; s = 0.0
    for j, i in enumerate(o, 1): err += (not ok[i]); s += err / j
    return s / len(conf)


def metrics(rows):
    n = len(rows); conf = [r["conf"] for r in rows]; ok = [bool(r["ok"]) for r in rows]; cov = [r for r in rows if r["conf"] >= 0.8]
    t = conformal.tightest_bound(conf, ok, 0.1); ms = sorted(r["ms"] for r in rows)
    return {"n": n, "acc": sum(ok) / n, "handled_n_at_0.8": len(cov), "handled_at_0.8": len(cov) / n,
            "acc_on_handled_at_0.8": sum(r["ok"] for r in cov) / len(cov) if cov else None, "ece_10bin": reliability.ece(list(zip(conf, ok)), 10),
            "aurc": aurc(conf, ok), "ltt_tightest": t, "ltt_alpha05_tau": conformal.calibrate(conf, ok, 0.05, 0.1)["tau"],
            "mean_conf": sum(conf) / n, "median_ms": ms[n // 2], "p90_ms": ms[int(math.ceil(0.9 * n)) - 1]}


def rows_from(items, comb, k=None):
    out = []
    for it in items:
        per = it["per_perm"][:k] if k else it["per_perm"]
        if comb == "order0": p = per[0]; ms = it["timings"][0]["ms"]
        else:
            n = len(it["ids"])
            if comb == "mean": p = [sum(q[j] for q in per) / len(per) for j in range(n)]
            else:
                g = [sum(math.log(max(q[j], 1e-12)) for q in per) / len(per) for j in range(n)]; m = max(g); e = [math.exp(x - m) for x in g]; p = [x / sum(e) for x in e]
            ms = sum(t["ms"] for t in it["timings"][:len(per)])
        kk = max(range(len(p)), key=lambda i: p[i])
        out.append({"type": it["type"], "gold": it["gold"], "pred": it["ids"][kk], "conf": p[kk], "ok": it["ids"][kk] == it["gold"], "ms": ms, "k": len(per)})
    return out


def verdict(m, base):
    b, bb = m["ltt_tightest"]["error_upper_bound"], base["ltt_tightest"]["error_upper_bound"]
    better = b < bb - 1e-9 or (abs(b - bb) <= 1e-9 and m["ltt_tightest"]["handled_share"] > base["ltt_tightest"]["handled_share"])
    ece_ok = m["ece_10bin"] <= base["ece_10bin"] + 0.01
    return {"bound_or_handled_better": better, "ece_within_0.01": ece_ok, "ece_delta_vs_base": m["ece_10bin"] - base["ece_10bin"], "wins": better and ece_ok}


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--perm", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--base", default=str(HERE / "repro_nov4_cal180_v2cc.json"))
    ap.add_argument("--no-repeats", action="store_true", help="skip the cal180 single-order repeat files (use for test120)")
    a = ap.parse_args()
    _b = json.loads(Path(a.base).read_text())
    base = metrics(_b["cal/v2+cc"]["rows"] if "cal/v2+cc" in _b else _b["rows"])
    reps = {}
    for f in ([] if a.no_repeats else sorted(glob.glob(str(HERE / "repro_nov4_cal180_v2cc*.json")))):
        reps[Path(f).name] = metrics(json.loads(Path(f).read_text())["cal/v2+cc"]["rows"])
    P = json.loads(Path(a.perm).read_text()); res = {"baseline_T1": base, "baseline_source": a.base, "single_order_repeats": reps, "variants": {}}
    for mode, o in P["modes"].items():
        items = o["items"]
        combos = [("order0", None), ("mean", None), ("geo", None)] + ([("mean", 4), ("geo", 4)] if mode == "cycall" else [])
        for comb, k in combos:
            name = f"{mode if not k else 'cyc4'}/{comb}"
            if name in res["variants"]: continue
            r = rows_from(items, comb, k); m = metrics(r); m["mean_k"] = sum(x["k"] for x in r) / len(r)
            m["verdict_vs_T1"] = verdict(m, base) if comb != "order0" else None
            # sensitivity (post hoc, NOT the pre-registered rule): paired vs the identity permutation of the SAME run/server state
            m["verdict_paired_vs_same_run_order0"] = verdict(m, metrics(rows_from(items, "order0"))) if comb != "order0" else None
            m["source"] = f"{a.perm} modes.{mode}" + (f" (first {k} rotations)" if k else "")
            res["variants"][name] = m
    sp = list(reps.values()) + [v for k, v in res["variants"].items() if k.endswith("order0")]
    res["single_order_spread"] = {"n_runs": len(sp), "ece_min": min(x["ece_10bin"] for x in sp), "ece_max": max(x["ece_10bin"] for x in sp),
                                  "bound_min": min(x["ltt_tightest"]["error_upper_bound"] for x in sp), "bound_max": max(x["ltt_tightest"]["error_upper_bound"] for x in sp),
                                  "aurc_min": min(x["aurc"] for x in sp), "aurc_max": max(x["aurc"] for x in sp)}
    Path(a.out).write_text(json.dumps(res, indent=1))
    f = lambda m: (f"acc {m['acc']:.3f} h@.8 {m['handled_n_at_0.8']} aoh {m['acc_on_handled_at_0.8']:.3f} ece {m['ece_10bin']:.3f} aurc {m['aurc']:.4f} "
                   f"bound {m['ltt_tightest']['error_upper_bound']:.3f}@{m['ltt_tightest']['tau']} ({m['ltt_tightest']['handled']},{m['ltt_tightest']['errors']}) med {m['median_ms']:.0f} p90 {m['p90_ms']:.0f}")
    print("T1      ", f(base))
    for k, m in reps.items(): print(k[:28].ljust(28), f(m))
    for k, m in res["variants"].items(): print(k.ljust(12), f(m), "K=%.2f" % m["mean_k"], (m["verdict_vs_T1"] or {}).get("wins"))
    print(json.dumps(res["single_order_spread"]))
