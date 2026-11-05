"""Rebuild publication figures from saved predictions; performs no inference."""
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/img"
OUT.mkdir(exist_ok=True)
BG, FG, MUTED, OLD, NEW = "#101820", "#f1f5f7", "#b4c0ca", "#8396a6", "#66d6c5"
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 17})


def chart(title, subtitle, labels, values, total, annotations, caption, filename, colors):
    fig, ax = plt.subplots(figsize=(13.333, 7.5), dpi=144)
    fig.patch.set_facecolor(BG)
    ax.set_facecolor(BG)
    fig.subplots_adjust(left=.26, right=.91, top=.70, bottom=.26)
    fig.text(.05, .91, title, color=FG, fontsize=25, weight="bold")
    fig.text(.05, .84, subtitle, color=MUTED, fontsize=15)
    y = list(range(len(values)))
    ax.barh(y, [total] * len(y), color="#24313d", height=.48)
    ax.barh(y, values, color=colors, height=.48)
    for row, value, annotation in zip(y, values, annotations):
        ax.text(value + total * .025, row, annotation, color=FG, va="center", fontsize=18)
    ax.set_yticks(y, labels=labels, color=FG)
    ax.invert_yaxis()
    ax.set_xlim(0, total * 1.12)
    ax.set_xticks([0, total / 4, total / 2, 3 * total / 4, total])
    ax.tick_params(axis="both", length=0, labelcolor=MUTED, pad=12)
    for spine in ax.spines.values():
        spine.set_visible(False)
    ax.set_xlabel(f"Number of decisions, out of {total}", color=MUTED, labelpad=14)
    fig.text(.05, .10, caption, color=MUTED, fontsize=12, linespacing=1.6)
    fig.savefig(OUT / filename, facecolor=BG)
    plt.close(fig)


baseline = json.loads((ROOT / "eval/experiments/test120_results.json").read_text())["test/v2+cc"]
shipping = json.loads((ROOT / "eval/results/after_floor.test.json").read_text())["rows"]
before = round(baseline["acc"] * baseline["n"])
after = sum(row["pred"] == row["gold"] for row in shipping)
assert baseline["n"] == len(shipping) == 120
assert (before, after) == (89, 98)
chart(
    "Nine more correct decisions after distillation",
    "Same 120 authored decision examples · Linux CPU · individual choices, not phone task success",
    ["Before training", "Shipping model"], [before, after], 120,
    ["89 / 120", "98 / 120"],
    "Source: eval/experiments/test120_results.json and eval/results/after_floor.test.json\n"
    "At the separate shipping threshold of 0.90: 44 choices accepted, 41 correct. No error guarantee.",
    "distillation_decisions.png", [OLD, NEW],
)

bench = json.loads((ROOT / "docs/verification/local_model_reliability_2026-11-04/memory_context_bench.json").read_text())
action = [r for r in bench["results"] if r["kind"] == "route" and r["gold"] == "tool"]
values = []
for condition in ["mem4", "mem2", "bare"]:
    seeds = [0] if condition == "bare" else [1, 2, 3]
    counts = []
    for seed in seeds:
        rows = [r for r in action if r["cond"] == condition and r["seed"] == seed]
        assert len(rows) == 24
        counts.append(sum(r["conf"] >= bench["tau"] for r in rows))
    values.append(sum(counts) / len(counts))
assert values == [1, 2, 9]
chart(
    "Cleaner route input accepts more action requests",
    "24 action-routing examples · threshold 0.90 · no actions were executed in this benchmark",
    ["4 unrelated facts", "2 unrelated facts", "Clean route input"], values, 24,
    ["1 / 24*", "2 / 24*", "9 / 24"],
    "* Mean across three synthetic memory draws. Four-fact counts were 0, 1 and 2.\n"
    "20 authored examples + 4 reused calibration examples; Linux CPU, not iPhone Metal.\n"
    "15 of 24 still fall back with clean input. This is a diagnostic, not a held-out safety result.",
    "route_context_diagnostic.png", [OLD, OLD, NEW],
)
print("Wrote docs/img/distillation_decisions.png and docs/img/route_context_diagnostic.png")
