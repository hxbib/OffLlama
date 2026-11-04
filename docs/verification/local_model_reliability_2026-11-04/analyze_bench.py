"""Summarize memory_context_bench.json into Markdown. Usage: python3 -I analyze_bench.py <bench.json>

Unit of analysis is the ROW (one utterance). bare has one run per row. mem2/mem4 have three seeded memory samples per
row; per-seed metrics are computed over rows and reported as mean [min, max] across seeds, never pooled as if the three
seeds were independent examples. Paired deltas average each row's seeds first, then bootstrap over rows (cluster
bootstrap) and run an exact two-sided sign test over rows."""
import json, math, random, sys
from collections import defaultdict
d = json.load(open(sys.argv[1])); TAU = d["tau"]; R = d["results"]
SRC = {"cal180": "cal180 (calibration split, diagnostic reuse: it fitted priors/tau, so not held out)",
       "authored": "authored (48 offline utterances written for this bench; labels are mine, not frozen or teacher-checked)"}

def ece(rows, bins=10):
    err = 0.0
    for b in range(bins):
        lo, hi = b / bins, (b + 1) / bins
        s = [r for r in rows if lo < r["conf"] <= hi]
        if s: err += len(s) / len(rows) * abs(sum(r["argmax"] == r["gold"] for r in s) / len(s) - sum(r["conf"] for r in s) / len(s))
    return err

def metrics(rows):
    h = [r for r in rows if r["conf"] >= TAU]; hok = sum(r["argmax"] == r["gold"] for r in h)
    return {"acc": sum(r["argmax"] == r["gold"] for r in rows), "handled": len(h), "handled_ok": hok,
            "conf_err": len(h) - hok, "ece": ece(rows), "mean_conf": sum(r["conf"] for r in rows) / len(rows)}

def select(kind, src, cond, seed=None, gold=None):
    return [r for r in R if r["kind"] == kind and r["cond"] == cond and (src == "all" or r["src"] == src)
            and (seed is None or r["seed"] == seed) and (gold is None or r["gold"] == gold)]

def seeds(cond): return sorted({r["seed"] for r in R if r["cond"] == cond})

def cell(vals, fmt):
    if len(vals) == 1: return fmt(vals[0])
    m = sum(vals) / len(vals)
    return f"{fmt(m)} [{fmt(min(vals))}, {fmt(max(vals))}]"

def table(kind, src):
    n = len(select(kind, src, "bare"))
    out = [f"\n#### {kind}, {SRC.get(src, 'all rows')} (n = {n} rows)\n",
           "| condition | argmax correct | handled at tau | correct of handled | confident errors | ECE | mean conf |",
           "|---|---|---|---|---|---|---|"]
    for cond in ("bare", "mem2", "mem4"):
        per = [metrics(select(kind, src, cond, s)) for s in seeds(cond)]
        i = lambda x: f"{x:.1f}" if isinstance(x, float) and x != int(x) else f"{int(x)}"
        out.append(f"| {cond} | {cell([p['acc'] for p in per], i)}/{n} | {cell([p['handled'] for p in per], i)}/{n} | "
                   f"{cell([p['handled_ok'] for p in per], i)} | {cell([p['conf_err'] for p in per], i)} | "
                   f"{cell([p['ece'] for p in per], lambda x: f'{x:.3f}')} | {cell([p['mean_conf'] for p in per], lambda x: f'{x:.3f}')} |")
    return out

def sign_p(lower, higher):
    n = lower + higher
    if n == 0: return 1.0
    k = min(lower, higher)
    return min(1.0, 2 * sum(math.comb(n, i) for i in range(k + 1)) / 2 ** n)

def paired(kind, cond, metric, gold=None, B=4000):
    by = defaultdict(lambda: defaultdict(list))
    for r in R:
        if r["kind"] == kind and r["cond"] in ("bare", cond) and (gold is None or r["gold"] == gold):
            by[r["row"]][r["cond"]].append(r)
    val = {"handled": lambda rs: sum(x["conf"] >= TAU for x in rs) / len(rs),
           "correct": lambda rs: sum(x["argmax"] == x["gold"] for x in rs) / len(rs),
           "conf": lambda rs: sum(x["conf"] for x in rs) / len(rs)}[metric]
    ids = sorted(by); delta = {i: val(by[i][cond]) - val(by[i]["bare"]) for i in ids}
    rng = random.Random(7); bs = sorted(sum(delta[rng.choice(ids)] for _ in ids) / len(ids) for _ in range(B))
    lo, hi = sum(v < 0 for v in delta.values()), sum(v > 0 for v in delta.values())
    return sum(delta.values()) / len(ids), bs[int(0.025 * B)], bs[int(0.975 * B) - 1], lo, hi, len(ids) - lo - hi, len(ids)

out = [f"tau = {TAU}. Unit = row (utterance). bare: 1 run per row. mem2/mem4: 3 seeded fact samples per row, shown as mean [min, max] over seeds."]
for kind in ("route", "toolChoice"):
    for src in ("cal180", "authored", "all"):
        out += table(kind, src)
out.append("\n#### Paired change vs bare (all rows; per-row seed mean; cluster bootstrap over rows, 4000 resamples, 95% CI; exact sign test over rows)\n")
out.append("| decision | gold class | condition | metric | mean change per row | 95% CI | rows down / up / same | sign-test p |")
out.append("|---|---|---|---|---|---|---|---|")
for kind in ("route", "toolChoice"):
    golds = [None] + (["tool", "answer_local", "escalate_cloud", "clarify"] if kind == "route" else [])
    for g in golds:
        for cond in ("mem2", "mem4"):
            for m, name in (("conf", "confidence"), ("handled", "handled at tau"), ("correct", "argmax correct")):
                if g is not None and m != "conf" and m != "handled": continue
                p, lo, hi, dn, up, same, n = paired(kind, cond, m, g)
                out.append(f"| {kind} | {g or 'all'} (n={n}) | {cond} | {name} | {p:+.3f} | [{lo:+.3f}, {hi:+.3f}] | {dn} / {up} / {same} | {sign_p(dn, up):.2g} |")

out.append("\n#### What the route decision does with each request (offline, all rows)\n")
out.append("Model acts: conf >= tau and argmax is the gold option. Falls back: conf < tau. The app then takes the escalate_cloud "
           "fallback (offline: the answerability decision, then chat or an offline notice) unless a deterministic rule intercepts "
           "first. Wrong and confident: conf >= tau with the wrong option. mem2/mem4 counts are rows, mean [min, max] over 3 seeds.\n")
out.append("| gold route | rows | condition | model acts | falls back | wrong and confident |\n|---|---|---|---|---|---|")
for g in ("tool", "answer_local", "escalate_cloud", "clarify"):
    n = len(select("route", "all", "bare", gold=g))
    for cond in ("bare", "mem2", "mem4"):
        per = [select("route", "all", cond, s, g) for s in seeds(cond)]
        f = lambda x: f"{x:.1f}" if x != int(x) else f"{int(x)}"
        acts = [sum(r["conf"] >= TAU and r["argmax"] == g for r in rs) for rs in per]
        fb = [sum(r["conf"] < TAU for r in rs) for rs in per]
        wr = [sum(r["conf"] >= TAU and r["argmax"] != g for r in rs) for rs in per]
        out.append(f"| {g} | {n} | {cond} | {cell(acts, f)} | {cell(fb, f)} | {cell(wr, f)} |")
print("\n".join(out))
