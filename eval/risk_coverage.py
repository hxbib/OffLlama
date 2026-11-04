#!/usr/bin/env python3
"""Selective-prediction risk-coverage curve (Geifman & El-Yaniv 2017) for the Reflex, baseline vs shipping.

Inputs are the saved per-item predictions of the headline pipeline (v2+cc, frozen test N=120):
  baseline  eval/experiments/test120_results.json  key "test/v2+cc"   (untrained Llama 3.2 1B Q4_K_M + prompt debiasing)
  shipping  eval/results/after_floor.test.json                          (Llama-Reflex-1B ep1 Q4_K_M)
For every threshold tau we keep items with conf >= tau ("handled on device"); coverage = kept/N, risk = errors among kept/kept.
Writes a JSON with the curve points + AURC and, if matplotlib is importable, a PNG. stdlib-only otherwise.
Usage: python3 eval/risk_coverage.py [--out docs/img/risk_coverage_test120.png]
"""
import argparse, json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def curve(rows):
    rows = sorted(rows, key=lambda r: -r["conf"])
    n = len(rows); pts = []; err = 0
    for i, r in enumerate(rows, 1):
        err += 0 if r["ok"] else 1
        pts.append({"coverage": i / n, "risk": err / i, "tau": r["conf"]})
    aurc = sum(p["risk"] for p in pts) / n   # area under the risk-coverage curve (lower is better)
    return pts, aurc


def at_tau(rows, tau):
    kept = [r for r in rows if r["conf"] >= tau]
    return {"tau": tau, "coverage": len(kept) / len(rows), "n_kept": len(kept),
            "risk": (sum(not r["ok"] for r in kept) / len(kept)) if kept else None}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "docs/img/risk_coverage_test120.png"))
    ap.add_argument("--json", default=str(ROOT / "eval/results/risk_coverage_test120.json"))
    a = ap.parse_args()
    base = json.load(open(ROOT / "eval/experiments/test120_results.json"))["test/v2+cc"]["rows"]
    ship = json.load(open(ROOT / "eval/results/after_floor.test.json"))["rows"]
    assert len(base) == len(ship) == 120, (len(base), len(ship))
    out = {"n": 120, "split": "frozen test120, v2+cc", "series": {}}
    for name, rows in [("baseline_untrained_1B", base), ("shipping_llama_reflex_1B", ship)]:
        pts, aurc = curve(rows)
        out["series"][name] = {"accuracy": sum(r["ok"] for r in rows) / len(rows), "aurc": aurc,
                               "at_tau": [at_tau(rows, t) for t in (0.5, 0.6, 0.7, 0.8, 0.9, 0.95)], "curve": pts}
        print(f"{name}: acc {out['series'][name]['accuracy']:.3f}  AURC {aurc:.4f}  " +
              "  ".join(f"τ{p['tau']}: cov {p['coverage']:.2f} risk {p['risk'] if p['risk'] is None else round(p['risk'],3)}" for p in out["series"][name]["at_tau"]))
    Path(a.json).write_text(json.dumps(out, indent=1))
    print("wrote", a.json)
    try:
        import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
    except Exception as e:  # noqa
        print("matplotlib not available, PNG skipped:", e); return
    fig, ax = plt.subplots(figsize=(6.4, 4.2), dpi=160)
    for name, lab, c in [("baseline_untrained_1B", "Untrained Llama 3.2 1B (prompt-debiased)", "#999999"),
                         ("shipping_llama_reflex_1B", "Llama-Reflex-1B (distilled from Muse Glimmer)", "#1f6feb")]:
        s = out["series"][name]
        ax.plot([p["coverage"] for p in s["curve"]], [p["risk"] for p in s["curve"]], label=f"{lab}  AURC {s['aurc']:.3f}", color=c, lw=2)
        for p in s["at_tau"]:
            if p["tau"] in (0.8, 0.9) and p["risk"] is not None:
                ax.scatter([p["coverage"]], [p["risk"]], color=c, s=28, zorder=3)
                ax.annotate(f"τ={p['tau']}", (p["coverage"], p["risk"]), textcoords="offset points", xytext=(4, 6), fontsize=7, color=c)
    ax.set_xlabel("Coverage (share of decisions kept on device)"); ax.set_ylabel("Selective risk (error rate among kept decisions)")
    ax.set_title("Risk-coverage, frozen test split N=120 (12 decision types)", fontsize=10)
    ax.set_xlim(0, 1); ax.set_ylim(0, 0.6); ax.grid(alpha=0.3); ax.legend(fontsize=7, loc="upper left")
    fig.text(0.01, 0.005, "Confidence = raw letter-softmax probability (no temperature scaling). Measured via llama-server on a Linux x86 CPU; same model file ships on the phone.", fontsize=6, color="#555")
    fig.tight_layout(rect=(0, 0.03, 1, 1)); fig.savefig(a.out); print("wrote", a.out)


if __name__ == "__main__":
    main()
