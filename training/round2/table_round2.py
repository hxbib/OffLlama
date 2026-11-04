"""Table every eval/experiments/round2_*_cal*_summary.json against the shipping repro and apply THE GATE.
Gate (LEDGER 0 + orchestrator noise rule): replace shipping only if on cal180 v2+cc (graded vs gold)
 (a) LTT tightest bound < 10.4% (box repro) at a tau with handled share >= 35%, or certifies alpha 0.05; and the bound must
     also be < 10.0% to count as outside the single-order noise band (10.4-10.9% over 6 runs of the same GGUF, PERM_AVG.md),
     on EVERY repeat run;
 (b) acc-on-handled @ tau 0.8 >= 0.95; (c) ECE <= 0.06.  Prints markdown and writes training/round2/out/table.json."""
import glob, json, re, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "training"))
from pg_train import conformal  # noqa: E402


def best35(name, rep):
    """tightest LTT bound restricted to tau with handled share >= 35% (same grid / delta/K level as conformal.tightest_bound)"""
    suf = "" if rep == 1 else f"_rep{rep}"
    rows = json.load(open(ROOT / f"eval/experiments/round2_{name}_cal{suf}.json"))["cal/v2+cc"]["rows"]
    conf = [r["conf"] for r in rows]; ok = [r["ok"] for r in rows]; lvl = 0.1 / len(conformal.GRID); best = None
    for t in conformal.GRID:
        idx = [i for i in range(len(conf)) if conf[i] >= t]
        if len(idx) < 0.35 * len(conf): continue
        e = sum(not ok[i] for i in idx); u = conformal.cp_upper(e, len(idx), lvl)
        if best is None or u < best["error_upper_bound"]: best = {"tau": t, "handled": len(idx), "errors": e, "error_upper_bound": u}
    return best
rows = {}
for f in sorted(glob.glob(str(ROOT / "eval/experiments/round2_*_cal*_summary.json"))):
    m = re.match(r"round2_(.+)_cal(?:_rep(\d+))?_summary\.json", Path(f).name)
    d = json.load(open(f)); d["best35"] = best35(m.group(1), d["rep"]); rows.setdefault(m.group(1), []).append(d)


SHIP_BOUND = min(m["ltt_tightest"]["error_upper_bound"] for m in rows["SHIP"])  # box repro value (10.4% printed)


def gate(m):
    b35 = m["best35"]; a05 = m["ltt_alpha05"]["tau"] is not None
    a = (b35 is not None and b35["error_upper_bound"] < SHIP_BOUND - 1e-9) or a05
    a_strict = (b35 is not None and b35["error_upper_bound"] < 0.100) or a05
    b = (m["acc_on_handled_at_0.8"] or 0) >= 0.95; c = m["ece_10bin"] <= 0.06
    return a, a_strict, b, c


out = []; md = ["| model | rep | acc | handled@0.8 | acc-on-handled@0.8 | ECE | LTT tightest (τ, handled, err) | best bound with share ≥35% | α0.05 | a (<10.4) | a-strict (<10.0) | b (≥0.95) | c (≤0.06) |",
                "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
for name, ms in sorted(rows.items(), key=lambda kv: (kv[0] != "SHIP", kv[0])):
    for m in sorted(ms, key=lambda x: x["rep"]):
        lt = m["ltt_tightest"]; a, s, b, c = gate(m)
        out.append({"name": name, "rep": m["rep"], **{k: m[k] for k in ("acc", "handled_at_0.8", "acc_on_handled_at_0.8", "ece_10bin")}, "ltt": lt, "best35": m["best35"],
                    "alpha05": m["ltt_alpha05"], "gate": {"a": a, "a_strict": s, "b": b, "c": c}})
        yn = lambda x: "✓" if x else "✗"
        b35 = m["best35"]; b35s = f"{b35['error_upper_bound']*100:.1f}% (τ {b35['tau']:.2f}, {b35['handled']}, {b35['errors']})" if b35 else "—"
        aoh = m['acc_on_handled_at_0.8']
        md.append(f"| {name} | {m['rep']} | {m['acc']:.3f} | {m['handled_at_0.8']:.3f} ({m['handled_n_at_0.8']}) | {('%.3f' % aoh) if aoh is not None else '—'} | {m['ece_10bin']:.3f} | "
                  f"{lt['error_upper_bound']*100:.1f}% ({lt['tau']:.2f}, {lt['handled']} = {lt['handled_share']:.0%}, {lt['errors']}) | {b35s} | "
                  f"{m['ltt_alpha05']['tau'] or '—'} | {yn(a)} | {yn(s)} | {yn(b)} | {yn(c)} |")
verdict = {}
for name, ms in rows.items():
    if name == "SHIP": continue
    gs = [gate(m) for m in ms]
    verdict[name] = {"reps": len(ms), "pass_all_reps": all(s and b and c for _, s, b, c in gs), "pass_loose_any": any(a and b and c for a, _, b, c in gs)}
(ROOT / "training/round2/out/table.json").write_text(json.dumps({"rows": out, "verdict": verdict}, indent=1))
print("\n".join(md)); print(); print(json.dumps(verdict, indent=1))
