#!/usr/bin/env python3
"""Reliability diagram + Expected Calibration Error (ECE).

Input: any JSON/JSONL eval file whose rows have a confidence and a correctness flag.
Accepted keys: confidence in {conf, confidence, p}; correct in {ok, correct}.
A JSON object with a "rows" list (eval/results/*.json) also works.

    python3 training/reliability.py eval/results/llama32-1b-base.json \
        --out docs/img/reliability_baseline.png --title "Llama 3.2 1B Q4_K_M, untrained"

ECE = sum_b (n_b / N) * |acc_b - conf_b| over equal-width bins (default 10).
"""
import argparse, json, sys


def load_rows(path):
    with open(path) as f:
        text = f.read()
    try:
        data = json.loads(text)
        rows = data["rows"] if isinstance(data, dict) else data
    except json.JSONDecodeError:
        rows = [json.loads(l) for l in text.splitlines() if l.strip()]
    out = []
    for r in rows:
        c = next((r[k] for k in ("conf", "confidence", "p") if k in r), None)
        y = next((r[k] for k in ("ok", "correct") if k in r), None)
        if c is None or y is None:
            continue
        out.append((float(c), bool(y)))
    if not out:
        sys.exit(f"{path}: no rows with (confidence, correct) found")
    return out


def bins_of(pairs, n_bins=10):
    bins = [[] for _ in range(n_bins)]
    for c, y in pairs:
        bins[min(int(c * n_bins), n_bins - 1)].append((c, y))
    return bins


def ece(pairs, n_bins=10):
    n = len(pairs)
    total = 0.0
    for b in bins_of(pairs, n_bins):
        if b:
            acc = sum(y for _, y in b) / len(b)
            conf = sum(c for c, _ in b) / len(b)
            total += len(b) / n * abs(acc - conf)
    return total


def plot(pairs, out, title, n_bins=10):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    e = ece(pairs, n_bins)
    acc = sum(y for _, y in pairs) / len(pairs)
    fig, ax = plt.subplots(figsize=(5, 5), dpi=160)
    ax.plot([0, 1], [0, 1], ls="--", color="#999", lw=1, label="perfect calibration")
    w = 1 / n_bins
    for i, b in enumerate(bins_of(pairs, n_bins)):
        if not b:
            continue
        a = sum(y for _, y in b) / len(b)
        ax.bar(i * w, a, width=w, align="edge", color="#1877F2", alpha=0.85, edgecolor="white")
        ax.text(i * w + w / 2, a + 0.02, f"n={len(b)}", ha="center", fontsize=7, color="#444")
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    ax.set_xlim(0, 1); ax.set_ylim(0, 1.08)
    ax.set_xlabel("model confidence"); ax.set_ylabel("accuracy in bin")
    ax.set_title(f"{title}\nN={len(pairs)}  accuracy={acc:.2f}  ECE={e:.3f} ({n_bins} bins)", fontsize=9)
    ax.legend(frameon=False, fontsize=8, loc="upper left")
    fig.tight_layout()
    fig.savefig(out)
    return e


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("results")
    ap.add_argument("--out", default="reliability.png")
    ap.add_argument("--title", default="Reliability")
    ap.add_argument("--bins", type=int, default=10)
    a = ap.parse_args()
    pairs = load_rows(a.results)
    e = plot(pairs, a.out, a.title, a.bins)
    print(json.dumps({"n": len(pairs), "ece": round(e, 4), "bins": a.bins, "png": a.out}))


if __name__ == "__main__":
    main()
