"""Candidate-only runtime calibration and evaluation harness.

Scores a GGUF with the shipping DecisionPrompt geometry (zeroShot or
fewShot), records per-row letter logprobs, fits temperature and contextual
priors on calfit only, and reports raw versus calibrated metrics on dev.
A letter absent from the server top list is censored evidence. The row is
recorded unusable and never floored, filled, or scored.

  python3 training/round3/phone_runtime_eval.py score --gguf X.gguf \
      --rows phone_dev_eval.jsonl --style zeroShot --out scored.jsonl
  python3 training/round3/phone_runtime_eval.py priors --gguf X.gguf \
      --rows phone_calfit_eval.jsonl --style zeroShot --out priors.json
  python3 training/round3/phone_runtime_eval.py report \
      --calfit calfit_scored.jsonl --dev dev_scored.jsonl \
      --priors priors.json --out report.json

Gold in the phone eval rows is Glimmer-top on developer templates. Every
report carries that label. Nothing here touches shipping assets.
"""
import argparse, json, math, subprocess, sys, time, urllib.request
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "training"))
from pg_train import prompts

SERVER = "/tmp/gencode/llama.cpp/build/bin/llama-server"
LETTERS = "ABCDEFGH"
CONTENT_FREE = ["N/A", "", "[MASK]"]


def extended_get_set(kind, candidates=None):
    if kind == "skillPick":
        c = list(candidates or [])[:7]
        return {"type": "skillPick",
                "question": "Which phone action does the user want?",
                "fallback": "ask",
                "options": [{"id": f"s{i}", "label": x} for i, x in enumerate(c)]
                + [{"id": "ask", "label": "None of these: ask the user"}]}
    return prompts.get_set(kind, candidates)


def prior_key(option_set):
    t = option_set["type"]
    if t in ("contactPick", "eventPick", "skillPick"):
        return f"{t}#{len(option_set['options'])}"
    return t


def extract_letter_logprobs(top_list, letters):
    agg = {}
    for t in top_list or []:
        k = str(t.get("token", "")).strip()
        if k not in letters:
            continue
        try:
            lp = float(t.get("logprob"))
        except Exception:
            return None, list(letters)
        if not math.isfinite(lp):
            return None, [k]
        agg[k] = math.log(math.exp(agg[k]) + math.exp(lp)) if k in agg else lp
    missing = [l for l in letters if l not in agg]
    if missing:
        return None, missing
    return [agg[l] for l in letters], []


def softmax(v):
    m = max(v)
    e = [math.exp(x - m) for x in v]
    s = sum(e)
    return [x / s for x in e]


def ece(pairs, bins=10):
    if not pairs:
        return None
    b = defaultdict(list)
    for p, ok in pairs:
        b[min(bins - 1, int(p * bins))].append((p, ok))
    return sum((len(v) / len(pairs)) * abs(sum(x[0] for x in v) / len(v)
               - sum(x[1] for x in v) / len(v)) for v in b.values())


def nll(samples, temp):
    tot = 0.0
    for logits, label in samples:
        p = softmax([x / temp for x in logits])
        tot -= math.log(max(p[label], 1e-12))
    return tot / max(1, len(samples))


def fit_temperature(samples, lo=0.05, hi=10.0):
    if not samples:
        return 1.0
    g = (math.sqrt(5.0) - 1) / 2
    a, b = lo, hi
    c, d = b - g * (b - a), a + g * (b - a)
    for _ in range(80):
        if nll(samples, c) < nll(samples, d):
            b = d
        else:
            a = c
        c, d = b - g * (b - a), a + g * (b - a)
    return (a + b) / 2


def apply_calibration(logprobs, temp, prior):
    v = list(logprobs)
    if prior:
        v = [x - p for x, p in zip(v, prior)]
    return [x / temp for x in v]


def metrics(scored, temp_by_type, priors):
    """scored rows carry logprobs, gold_index, type, prior_key."""
    out = {}
    for name, fn in (("raw", lambda lp, t, k: lp),
                     ("calibrated", lambda lp, t, k: apply_calibration(
                         lp, temp_by_type.get(t, temp_by_type.get("*", 1.0)),
                         priors.get(k)))):
        pairs, per = [], defaultdict(lambda: [0, 0])
        nll_sum = 0.0
        for r in scored:
            p = softmax(fn(r["logprobs"], r["type"], r["prior_key"]))
            k = max(range(len(p)), key=lambda i: p[i])
            ok = int(k == r["gold_index"])
            pairs.append((p[k], ok))
            per[r["type"]][0] += ok
            per[r["type"]][1] += 1
            nll_sum -= math.log(max(p[r["gold_index"]], 1e-12))
        out[name] = {
            "n": len(scored),
            "acc": (sum(o for _, o in pairs) / len(pairs)) if pairs else None,
            "ece": ece(pairs),
            "nll": (nll_sum / len(pairs)) if pairs else None,
            "mean_conf": (sum(p for p, _ in pairs) / len(pairs)) if pairs else None,
            "per_type": {t: {"ok": v[0], "n": v[1]} for t, v in sorted(per.items())},
        }
    return out


def select_tau(scored, temp_by_type, priors, target_acc=0.95):
    """Smallest calfit tau reaching target handled accuracy, else None."""
    confs = []
    for r in scored:
        v = apply_calibration(r["logprobs"],
                              temp_by_type.get(r["type"], temp_by_type.get("*", 1.0)),
                              priors.get(r["prior_key"]))
        p = softmax(v)
        k = max(range(len(p)), key=lambda i: p[i])
        confs.append((p[k], int(k == r["gold_index"])))
    for tau in sorted({c for c, _ in confs}):
        h = [(c, o) for c, o in confs if c >= tau]
        if h and sum(o for _, o in h) / len(h) >= target_acc:
            return {"tau": tau, "handled_share": len(h) / len(confs),
                    "handled_acc": sum(o for _, o in h) / len(h), "handled_n": len(h)}
    return {"tau": None, "handled_share": 0.0, "handled_acc": None, "handled_n": 0}


def handled_at(scored, temp_by_type, priors, tau):
    if tau is None:
        return {"handled_share": 0.0, "handled_acc": None, "handled_n": 0}
    h = []
    for r in scored:
        v = apply_calibration(r["logprobs"],
                              temp_by_type.get(r["type"], temp_by_type.get("*", 1.0)),
                              priors.get(r["prior_key"]))
        p = softmax(v)
        k = max(range(len(p)), key=lambda i: p[i])
        if p[k] >= tau:
            h.append(int(k == r["gold_index"]))
    return {"handled_share": len(h) / max(1, len(scored)),
            "handled_acc": (sum(h) / len(h)) if h else None,
            "handled_n": len(h)}


class Server:
    def __init__(self, gguf, port):
        self.proc = subprocess.Popen(
            [SERVER, "-m", str(gguf), "--port", str(port), "-t", "4", "-c", "4096"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.url = f"http://127.0.0.1:{port}"
        for _ in range(180):
            if self.proc.poll() is not None:
                raise RuntimeError(f"llama-server exited rc={self.proc.returncode}")
            try:
                urllib.request.urlopen(self.url + "/health", timeout=2)
                return
            except Exception:
                time.sleep(1)
        raise RuntimeError("server did not become healthy")

    def letter_logprobs(self, prompt, letters):
        req = urllib.request.Request(
            self.url + "/completion",
            json.dumps({"prompt": prompt, "n_predict": 1, "n_probs": 40,
                        "temperature": 0, "cache_prompt": True}).encode(),
            {"Content-Type": "application/json"})
        r = json.loads(urllib.request.urlopen(req, timeout=180).read())
        probs = r.get("completion_probabilities") or []
        if not probs or not probs[0].get("top_logprobs"):
            return None, list(letters)
        return extract_letter_logprobs(probs[0]["top_logprobs"], letters)

    def close(self):
        self.proc.terminate()
        try:
            self.proc.wait(timeout=10)
        except Exception:
            self.proc.kill()


def score_rows(server, rows, style):
    scored, unusable = [], []
    for g in rows:
        s = extended_get_set(g["type"], g.get("candidates"))
        ids = [o["id"] for o in s["options"]]
        if g["gold"] not in ids:
            unusable.append({"id": g.get("id"), "missing": ["gold-not-in-options"]})
            continue
        prompt = prompts.llama3(s, g["context"], style)
        lp, missing = server.letter_logprobs(prompt, list(LETTERS[:len(ids)]))
        if lp is None:
            unusable.append({"id": g.get("id"), "missing": missing})
            continue
        scored.append({"id": g.get("id"), "type": g["type"],
                       "prior_key": prior_key(s), "logprobs": lp,
                       "gold_index": ids.index(g["gold"]), "gold": g["gold"],
                       "pred_index": max(range(len(lp)), key=lambda i: lp[i])})
    return scored, unusable


def cmd_score(a):
    rows = [json.loads(l) for l in open(a.rows) if l.strip()]
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    done = {}
    if Path(a.out).exists():
        for r in load_scored(a.out):
            done[r["id"]] = r
    srv = Server(a.gguf, a.port)
    scored = [done[g["id"]] for g in rows if g.get("id") in done]
    todo = [g for g in rows if g.get("id") not in done]
    try:
        with open(a.out, "a") as f:
            for i, g in enumerate(todo):
                s = extended_get_set(g["type"], g.get("candidates"))
                ids = [o["id"] for o in s["options"]]
                if g["gold"] not in ids:
                    continue
                lp, missing = srv.letter_logprobs(
                    prompts.llama3(s, g["context"], a.style),
                    list(LETTERS[:len(ids)]))
                if lp is None:
                    continue
                r = {"id": g.get("id"), "type": g["type"],
                     "prior_key": prior_key(s), "logprobs": lp,
                     "gold_index": ids.index(g["gold"]), "gold": g["gold"],
                     "pred_index": max(range(len(lp)), key=lambda j: lp[j])}
                f.write(json.dumps(r) + "\n")
                f.flush()
                scored.append(r)
                if (i + 1) % 100 == 0:
                    print(f"scored {i + 1}/{len(todo)}", flush=True)
    finally:
        srv.close()
    scored_ids = {r["id"] for r in scored}
    unusable = [{"id": g.get("id"), "missing": ["censored-or-gold-missing"]}
                for g in rows if g.get("id") not in scored_ids]
    meta = {"gguf": str(a.gguf), "rows": str(a.rows), "style": a.style,
            "n": len(rows), "usable": len(scored), "unusable": unusable,
            "coverage_complete": not unusable and len(scored) == len(rows)}
    Path(str(a.out) + ".meta.json").write_text(json.dumps(meta, indent=2))
    print(json.dumps(meta, indent=2))
    if unusable:
        raise SystemExit("FAIL: censored letters present; rows recorded unusable, never filled")


def cmd_priors(a):
    rows = [json.loads(l) for l in open(a.rows) if l.strip()]
    keys = {}
    for g in rows:
        s = extended_get_set(g["type"], g.get("candidates"))
        keys.setdefault(prior_key(s), s)
    srv = Server(a.gguf, a.port)
    priors = {}
    try:
        for key, s in sorted(keys.items()):
            letters = list(LETTERS[:len(s["options"])])
            acc = None
            for cf in CONTENT_FREE:
                lp, missing = srv.letter_logprobs(prompts.llama3(s, cf, a.style), letters)
                if lp is None:
                    raise SystemExit(f"FAIL: content-free prior censored for {key}: {missing}")
                acc = lp if acc is None else [x + y for x, y in zip(acc, lp)]
            priors[key] = [x / len(CONTENT_FREE) for x in acc]
    finally:
        srv.close()
    Path(a.out).write_text(json.dumps(
        {"gguf": str(a.gguf), "style": a.style, "content_free": CONTENT_FREE,
         "priors": priors}, indent=2))
    print(json.dumps({"priors_for_keys": sorted(priors), "out": str(a.out)}, indent=2))


def load_scored(path):
    return [json.loads(l) for l in open(path) if l.strip()]


def cmd_report(a):
    cal = load_scored(a.calfit)
    dev = load_scored(a.dev)
    priors = {}
    if a.priors:
        priors = json.loads(Path(a.priors).read_text()).get("priors", {})
    samples = [(r["logprobs"], r["gold_index"]) for r in cal]
    temp_by_type = {"*": fit_temperature(samples)}
    by_type = defaultdict(list)
    for r in cal:
        by_type[r["type"]].append((r["logprobs"], r["gold_index"]))
    for t, ss in by_type.items():
        if len(ss) >= 30:
            temp_by_type[t] = fit_temperature(ss)
    tau = select_tau(cal, temp_by_type, priors)
    rep = {
        "gold_note": "Glimmer-top on developer templates. Not human gold, not iPhone traces.",
        "fit_split": "calfit only", "selection_split": "dev",
        "temperature": temp_by_type, "tau_from_calfit": tau,
        "calfit": metrics(cal, temp_by_type, priors),
        "dev": metrics(dev, temp_by_type, priors),
        "dev_handled_at_calfit_tau": handled_at(
            dev, temp_by_type, priors, tau["tau"]),
        "dev_ablation": {
            "temperature_only": metrics(dev, temp_by_type, {})["calibrated"],
            "priors_only": metrics(dev, {"*": 1.0}, priors)["calibrated"],
        },
        "calibration_artifact": {
            "temperature": temp_by_type, "tau": tau["tau"], "priors": priors},
    }
    Path(a.out).write_text(json.dumps(rep, indent=2))
    print(json.dumps({k: rep[k] for k in ("temperature", "tau_from_calfit")}, indent=2))
    print(json.dumps({"calfit": rep["calfit"], "dev": rep["dev"],
                      "dev_handled_at_calfit_tau": rep["dev_handled_at_calfit_tau"]},
                     indent=2))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("score", "priors"):
        p = sub.add_parser(name)
        p.add_argument("--gguf", required=True)
        p.add_argument("--rows", required=True)
        p.add_argument("--style", default="zeroShot", choices=["zeroShot", "fewShot"])
        p.add_argument("--port", type=int, default=8241)
        p.add_argument("--out", required=True)
    p = sub.add_parser("report")
    p.add_argument("--calfit", required=True)
    p.add_argument("--dev", required=True)
    p.add_argument("--priors")
    p.add_argument("--out", required=True)
    a = ap.parse_args()
    {"score": cmd_score, "priors": cmd_priors, "report": cmd_report}[a.cmd](a)


if __name__ == "__main__":
    main()
