"""Temperature scaling + per-decision tau on held-out, using the STUDENT's real letter logits
(GGUF served by llama-server). Writes a CalibrationProfile JSON the app loads (core: CalibrationProfile).

  python -m pg_train.calibrate --heldout out/heldout.jsonl --url http://127.0.0.1:8088 --target-acc 0.95 --out out/calibration.json"""
import argparse, json, math
from collections import defaultdict
from pathlib import Path
from . import prompts, teachers as T


def softmax(v, t=1.0):
    m = max(v); e = [math.exp((x - m) / max(t, 1e-6)) for x in v]; s = sum(e); return [x / s for x in e]


def nll(samples, t):
    return sum(-math.log(max(softmax(l, t)[y], 1e-12)) for l, y in samples) / max(len(samples), 1)


def fit_temperature(samples, lo=0.05, hi=10.0):
    g = (math.sqrt(5) - 1) / 2; a, b = lo, hi
    c, d = b - g * (b - a), a + g * (b - a)
    for _ in range(80):
        if nll(samples, c) < nll(samples, d): b = d
        else: a = c
        c, d = b - g * (b - a), a + g * (b - a)
    return (a + b) / 2


def ece(conf, ok, bins=10):
    n = len(conf); err = 0.0
    for b in range(bins):
        lo, hi = b / bins, (b + 1) / bins
        idx = [i for i in range(n) if lo < conf[i] <= hi or (b == 0 and conf[i] == 0)]
        if idx: err += len(idx) / n * abs(sum(ok[i] for i in idx) / len(idx) - sum(conf[i] for i in idx) / len(idx))
    return err


def select_tau(conf, ok, target, min_cov=0.0):
    for tau in sorted(set(conf)):
        acc = [i for i in range(len(conf)) if conf[i] >= tau]
        if acc and len(acc) / len(conf) >= min_cov and sum(ok[i] for i in acc) / len(acc) >= target: return tau
    return None


def student_logits(url, rows, style="zeroShot"):
    st = T.LocalLlamaServerTeacher(url=url, name="student", style=style)
    out = []
    for r in rows:
        s = prompts.get_set(r["type"], r.get("candidates"))
        lab = st.label(s, r["context"])
        L = prompts.letters(s)
        out.append(([math.log(max(lab["probs"].get(l, 1e-9), 1e-9)) for l in L], L.index(r["target"]), r["type"]))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--heldout", default="out/heldout.jsonl"); ap.add_argument("--url", default="http://127.0.0.1:8088")
    ap.add_argument("--target-acc", type=float, default=0.95); ap.add_argument("--default-tau", type=float, default=0.8)
    ap.add_argument("--min-per-type", type=int, default=15, help="below this many held-out rows a type keeps the global T / default tau")
    ap.add_argument("--out", default="out/calibration.json")
    ap.add_argument("--style", default="zeroShot", help="zeroShot for a distilled student, fewShot for the base model")
    a = ap.parse_args()
    rows = [json.loads(l) for l in Path(a.heldout).read_text().splitlines() if l.strip()]
    data = student_logits(a.url, rows, a.style)
    allS = [(l, y) for l, y, _ in data]
    T_global = fit_temperature(allS)
    by = defaultdict(list)
    for l, y, t in data: by[t].append((l, y))
    prof = {"temperature": {}, "tau": {}, "defaultTau": a.default_tau, "prior": {}, "promptStyle": a.style}
    report = []
    for t, S in sorted(by.items()):
        Tt = fit_temperature(S) if len(S) >= a.min_per_type else T_global
        conf = [max(softmax(l, Tt)) for l, _ in S]
        ok = [softmax(l, Tt).index(max(softmax(l, Tt))) == y for l, y in S]
        tau = select_tau(conf, ok, a.target_acc) if len(S) >= a.min_per_type else None
        prof["temperature"][t] = round(Tt, 4)
        if tau is not None: prof["tau"][t] = round(tau, 4)
        cov = sum(c >= (tau if tau is not None else a.default_tau) for c in conf) / len(conf)
        report.append(f"{t:20s} n={len(S):4d} T={Tt:5.2f} acc={sum(ok)/len(ok):.2f} ECE={ece(conf, ok):.3f} tau={tau if tau is not None else '(default)'} coverage={cov:.2f}")
    conf0 = [max(softmax(l)) for l, _ in allS]; ok0 = [softmax(l).index(max(softmax(l))) == y for l, y in allS]
    confT = [max(softmax(l, T_global)) for l, _ in allS]
    print(f"global: n={len(allS)} T={T_global:.3f} ECE before={ece(conf0, ok0):.3f} after={ece(confT, ok0):.3f} acc={sum(ok0)/len(ok0):.3f}")
    print("\n".join(report))
    if any(r.get("dry_run") for r in rows): prof["_note"] = "DRY RUN: targets from local Llama-3.2-1B stand-in teacher; do not ship"
    Path(a.out).write_text(json.dumps(prof, indent=2))
    print(f"-> {a.out}")


if __name__ == "__main__":
    main()
