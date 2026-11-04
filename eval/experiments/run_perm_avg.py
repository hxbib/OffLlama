"""Option-order permutation averaging for the v2+cc Reflex readout (LEDGER idea 13.4). Inference-time only, no training.

For each item the v2+cc readout (prompt v2 + contextual calibration) is run under K option orders of the QUERY item
(few-shot exemplars keep their original order). Each letter distribution is mapped back to option ids and the K
distributions are combined: arithmetic mean ("mean") and normalized geometric mean ("geo"). The contextual-calibration
prior is computed per (type, n_options, permutation), because the positional prior moves with the order.
Order 0 is the identity permutation, so its prompt is byte-identical to run_prompt_variants.py v2+cc (single order).

Modes:  rev   K=2: original + reversed order
        cyc   K=min(n_options, --kmax) cyclic rotations (rotation r puts option r first)
Usage:  python3 eval/experiments/run_perm_avg.py --set cal --modes rev,cyc4,cycall --url http://127.0.0.1:8088 --out ...
Box CPU via llama-server; nothing here touches the original single-order script."""
import argparse, json, math, sys, time, urllib.request
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent; ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE)); sys.path.insert(0, str(ROOT / "training"))
import run_prompt_variants as rpv  # noqa: E402  (reuses render/relabel/softmax/load/CF_CONTEXTS unchanged)
from pg_train import prompts, conformal  # noqa: E402
import reliability  # noqa: E402

URL = "http://127.0.0.1:8088"


def call(prompt, L):
    """Same request body as rpv.letter_logprobs; also returns server timings / token counts."""
    req = urllib.request.Request(URL + "/completion", json.dumps({"prompt": prompt, "n_predict": 1, "n_probs": 40, "temperature": 0, "cache_prompt": True}).encode(),
                                 {"Content-Type": "application/json"})
    t0 = time.time(); r = json.loads(urllib.request.urlopen(req, timeout=120).read()); ms = (time.time() - t0) * 1000
    out = {}
    for t in r["completion_probabilities"][0]["top_logprobs"]:
        k = t["token"].strip()
        if k in L: out[k] = max(out.get(k, -1e9), t["logprob"]) if k not in out else math.log(math.exp(out[k]) + math.exp(t["logprob"]))
    floor = (min(out.values()) if out else -20) - 2
    tm = r.get("timings", {})
    return [out.get(l, floor) for l in L], ms, {"tokens_evaluated": r.get("tokens_evaluated"), "prompt_n": tm.get("prompt_n"),
                                                "cache_n": tm.get("cache_n"), "prompt_ms": tm.get("prompt_ms")}


def permute(s, perm):
    return dict(s, options=[s["options"][i] for i in perm])


def perms_for(n, mode):
    if mode == "single": return [list(range(n))]
    if mode == "rev": return [list(range(n)), list(range(n))[::-1]]
    if mode.startswith("cyc"):
        k = n if mode == "cycall" else min(n, int(mode[3:]))
        return [[(r + j) % n for j in range(n)] for r in range(k)]
    raise ValueError(mode)


_cf = {}
def cf_logp(s, v, perm):
    key = (v, s["type"], len(s["options"]), tuple(perm))
    if key not in _cf:
        ps = permute(s, perm); L = prompts.letters(ps); acc = [0.0] * len(L)
        for c in rpv.CF_CONTEXTS:
            p = rpv.softmax(call(rpv.render(ps, c, v), L)[0])
            acc = [a + x / len(rpv.CF_CONTEXTS) for a, x in zip(acc, p)]
        _cf[key] = [math.log(max(x, 1e-9)) for x in acc]
    return _cf[key]


def score_item(g, perms_mode, v="v2", cc=True):
    """Returns per-permutation id-space distributions + combined mean/geo distributions for one item."""
    s = prompts.get_set(g["type"], g.get("candidates")); ids = [o["id"] for o in s["options"]]; n = len(ids)
    base = s if g["type"] not in ("contactPick", "eventPick") else prompts.get_set(g["type"], [f"Person {i+1}" for i in range(n - 1)])
    per, ms_tot, tok = [], 0.0, []
    for perm in perms_for(n, perms_mode):
        ps = permute(s, perm); L = prompts.letters(ps)
        lp, ms, t = call(rpv.render(ps, g["context"], v), L)
        if cc: lp = [a - b for a, b in zip(lp, cf_logp(base, v, perm))]
        p_letter = rpv.softmax(lp); p_id = [0.0] * n
        for i, oi in enumerate(perm): p_id[oi] = p_letter[i]
        per.append(p_id); ms_tot += ms; t["ms"] = ms; tok.append(t)
    mean = [sum(p[j] for p in per) / len(per) for j in range(n)]
    gl = [sum(math.log(max(p[j], 1e-12)) for p in per) / len(per) for j in range(n)]
    geo = rpv.softmax(gl)
    return {"ids": ids, "per_perm": per, "mean": mean, "geo": geo, "ms": ms_tot, "n_calls": len(per), "timings": tok}


def summarize(rows, tau=0.8):
    n = len(rows); cov = [r for r in rows if r["conf"] >= tau]
    conf = [r["conf"] for r in rows]; ok = [bool(r["ok"]) for r in rows]
    t = conformal.tightest_bound(conf, ok, 0.1); c = conformal.calibrate(conf, ok, 0.05, 0.1)
    ms = sorted(r["ms"] for r in rows)
    return {"n": n, "acc": sum(ok) / n, "handled_at_0.8": len(cov) / n, "handled_n_at_0.8": len(cov),
            "acc_on_handled_at_0.8": (sum(r["ok"] for r in cov) / len(cov)) if cov else None,
            "ece_10bin": reliability.ece(list(zip(conf, ok)), 10), "ltt_tightest": t, "ltt_alpha05": c,
            "per_type_acc": {ty: round(sum(r["ok"] for r in rows if r["type"] == ty) / max(1, sum(1 for r in rows if r["type"] == ty)), 3) for ty in sorted({r["type"] for r in rows})},
            "median_ms_per_decision": ms[n // 2], "p90_ms_per_decision": ms[min(n - 1, int(math.ceil(0.9 * n)) - 1)]}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", default="cal"); ap.add_argument("--modes", default="rev,cyc4,cycall")
    ap.add_argument("--url", default=URL); ap.add_argument("--out", required=True)
    a = ap.parse_args(); URL = a.url
    rows_in = rpv.load(a.set); res = {"set": a.set, "url": a.url, "modes": {}}
    for mode in a.modes.split(","):
        t0 = time.time(); items = []
        for g in rows_in:
            r = score_item(g, mode); items.append({"type": g["type"], "gold": g["gold"], "context": g["context"], **r})
        wall = time.time() - t0; out = {"wall_s_including_cf": wall, "items": items}
        for comb in (["single"] if mode == "single" else ["order0", "mean", "geo"]):
            rows = []
            for it in items:
                p = it["per_perm"][0] if comb in ("order0", "single") else it[comb]
                k = max(range(len(p)), key=lambda i: p[i])
                ms = it["timings"][0]["ms"] if comb == "order0" else it["ms"]  # order0 = single-order cost; mean/geo = K calls
                rows.append({"type": it["type"], "gold": it["gold"], "pred": it["ids"][k], "conf": p[k], "ok": it["ids"][k] == it["gold"], "ms": ms})
            out[comb] = {"summary": summarize(rows), "rows": rows}
            sm = out[comb]["summary"]; tb = sm["ltt_tightest"]
            print(f"{a.set} {mode:6s} {comb:6s} acc={sm['acc']:.3f} h@0.8={sm['handled_at_0.8']:.2f} aoh={sm['acc_on_handled_at_0.8']} "
                  f"ece={sm['ece_10bin']:.3f} bound={tb['error_upper_bound']:.3f}@{tb['tau']} ({tb['handled']}/{sm['n']}, {tb['errors']} err) "
                  f"med_ms={sm['median_ms_per_decision']:.0f}", flush=True)
        res["modes"][mode] = out
        Path(a.out).write_text(json.dumps(res, indent=1))
