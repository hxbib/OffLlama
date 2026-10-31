"""Zero-training debiasing experiments for the untrained Reflex student (Llama 3.2 1B Q4) via llama-server.

Variants
  v0  production prompt (core DecisionPrompt.llama3)
  v1  v0 + sharper option labels
  v2  v1 + few-shot exemplars (as prior chat turns)
  +cc contextual calibration (Zhao et al. 2021): p_cc(y) ∝ p(y|x) / p(y|content-free), CF contexts "N/A", "", "[MASK]" averaged
Usage: python3 eval/experiments/run_prompt_variants.py --sets dev|gold36|e2e18|gold100 --variants v0,v1,v2 --out ..."""
import argparse, json, math, sys, time, urllib.request
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "training")); sys.path.insert(0, str(Path(__file__).parent))
from pg_train import prompts, scenarios
from fewshot import LABELS_V2, SHOTS

URL = "http://127.0.0.1:8088"
CF_CONTEXTS = ["N/A", "", "[MASK]"]
E2E = [("route", "User: Remind me to take my vitamins at 8pm", "tool"), ("route", "User: Text Maya that I'm on my way", "tool"),
       ("route", "User: Thanks, that's all for now!", "answer_local"),
       ("route", "User: Compare the tax treatment of ISOs vs RSOs for an early-stage startup employee and recommend a strategy", "escalate_cloud"),
       ("route", "User: Move it", "clarify"), ("toolChoice", "User: Remind me to buy oat milk when I get to the store", "create_reminder"),
       ("toolChoice", "User: What's on my calendar tomorrow morning?", "find_event"), ("toolChoice", "User: Send Sam a message saying happy birthday", "send_message"),
       ("rememberOrNot", "User: By the way, I'm allergic to peanuts.", "remember_fact"), ("rememberOrNot", "User: What time is it?", "no"),
       ("memoryConflict", "Existing memory: User lives in Boston\nNew statement: I just moved to Brooklyn last week", "update"),
       ("notificationTriage", "Notification from Mom: 'Call me ASAP, Dad is in the hospital'", "interrupt"),
       ("notificationTriage", "Notification from ShopMart: '20% off sneakers this weekend only!'", "ignore"),
       ("confirmBeforeAct", "Planned action: delete all calendar events next week", "confirm"),
       ("timing", "User: Every Monday at 9 remind me to submit my timesheet", "recurring"),
       ("sensitivity", "User: Summarize my HIV test results and my bank account balance", "sensitive"),
       ("contactPick", "User: Tell my brother Sam I'll be late to dinner", "c1", ["Sam Lee (coworker)", "Sam Ortiz (brother)", "Samantha Diaz (dentist)"]),
       ("nudgeNow", "Trigger: arrive, place: Trader Joe's\nMemory: User needs to buy oat milk", "nudge")]


def relabel(s, v):
    if v == "v0" or s["type"] not in LABELS_V2: return s
    return dict(s, options=[dict(o, label=LABELS_V2[s["type"]].get(o["id"], o["label"])) for o in s["options"]])


def render(s, ctx, v):
    s = relabel(s, v)
    head = "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n" + prompts.SYSTEM + "<|eot_id|>"
    shots = ""
    if v == "v2":
        for sh in [x for x in SHOTS if x[0] == s["type"]]:
            ss = relabel(prompts.get_set(sh[0], sh[3] if len(sh) > 3 else None), v)
            letter = prompts.LETTERS[[o["id"] for o in ss["options"]].index(sh[2])]
            shots += ("<|start_header_id|>user<|end_header_id|>\n\n" + prompts.body(ss, sh[1]) + "<|eot_id|>"
                      "<|start_header_id|>assistant<|end_header_id|>\n\nAnswer: " + letter + "<|eot_id|>")
    return head + shots + "<|start_header_id|>user<|end_header_id|>\n\n" + prompts.body(s, ctx) + "<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\nAnswer:"


def letter_logprobs(prompt, L):
    req = urllib.request.Request(URL + "/completion", json.dumps({"prompt": prompt, "n_predict": 1, "n_probs": 40, "temperature": 0, "cache_prompt": True}).encode(),
                                 {"Content-Type": "application/json"})
    t0 = time.time(); r = json.loads(urllib.request.urlopen(req, timeout=120).read()); ms = (time.time() - t0) * 1000
    out = {}
    for t in r["completion_probabilities"][0]["top_logprobs"]:
        k = t["token"].strip()
        if k in L: out[k] = max(out.get(k, -1e9), t["logprob"]) if k not in out else math.log(math.exp(out[k]) + math.exp(t["logprob"]))
    floor = (min(out.values()) if out else -20) - 2
    return [out.get(l, floor) for l in L], ms


def softmax(v):
    m = max(v); e = [math.exp(x - m) for x in v]; s = sum(e); return [x / s for x in e]


_cf_cache = {}
def cf_logp(s, v):
    key = (v, s["type"], len(s["options"]))
    if key not in _cf_cache:
        L = prompts.letters(s); acc = [0.0] * len(L)
        for c in CF_CONTEXTS:
            p = softmax(letter_logprobs(render(s, c, v), L)[0])
            acc = [a + x / len(CF_CONTEXTS) for a, x in zip(acc, p)]
        _cf_cache[key] = [math.log(max(x, 1e-9)) for x in acc]
    return _cf_cache[key]


def load(which):
    if which == "e2e18": return [{"type": t[0], "context": t[1], "gold": t[2], "candidates": t[3] if len(t) > 3 else None} for t in E2E]
    if which == "dev":
        rows = scenarios.generate(120, 99)
        return [{"type": r["type"], "context": r["context"], "gold": r["hint"], "candidates": r.get("candidates")} for r in rows]
    f = {"gold36": "gold_decisions.jsonl", "gold100": "gold/gold_all.jsonl", "cal": "gold/gold_calibration.jsonl", "test": "gold/gold_test.jsonl"}[which]
    return [json.loads(l) for l in (ROOT / "eval" / f).read_text().splitlines() if l.strip()]


def run(rows, v, cc, tau):
    res = []
    for g in rows:
        s = prompts.get_set(g["type"], g.get("candidates"))
        L = prompts.letters(s); ids = [o["id"] for o in s["options"]]
        lp, ms = letter_logprobs(render(s, g["context"], v), L)
        if cc:
            # positional prior for dynamic sets: CF with neutral candidate names of the same count
            base = s if g["type"] not in ("contactPick", "eventPick") else prompts.get_set(g["type"], [f"Person {i+1}" for i in range(len(s["options"]) - 1)])
            lp = [a - b for a, b in zip(lp, cf_logp(base, v))]
        p = softmax(lp); k = max(range(len(p)), key=lambda i: p[i])
        res.append({"type": g["type"], "gold": g["gold"], "pred": ids[k], "conf": p[k], "ok": ids[k] == g["gold"], "ms": ms})
    n = len(res); cov = [r for r in res if r["conf"] >= tau]
    from collections import Counter
    return {"n": n, "acc": sum(r["ok"] for r in res) / n, "coverage": len(cov) / n,
            "acc_on_covered": (sum(r["ok"] for r in cov) / len(cov)) if cov else None,
            "route_preds": dict(Counter(r["pred"] for r in res if r["type"] == "route")),
            "per_type_acc": {t: round(sum(r["ok"] for r in res if r["type"] == t) / max(1, sum(1 for r in res if r["type"] == t)), 2) for t in sorted({r["type"] for r in res})},
            "median_ms": sorted(r["ms"] for r in res)[n // 2], "rows": res}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--sets", default="dev"); ap.add_argument("--variants", default="v0,v0+cc,v1,v1+cc,v2,v2+cc")
    ap.add_argument("--tau", type=float, default=0.8); ap.add_argument("--out")
    a = ap.parse_args()
    allres = {}
    for which in a.sets.split(","):
        rows = load(which)
        for var in a.variants.split(","):
            v, cc = var.split("+")[0], var.endswith("+cc")
            r = run(rows, v, cc, a.tau)
            allres[f"{which}/{var}"] = r
            ac = "-" if r["acc_on_covered"] is None else f"{r['acc_on_covered']:.2f}"
            print(f"{which:7s} {var:7s} n={r['n']:3d} acc={r['acc']:.2f} cov@{a.tau}={r['coverage']:.2f} acc@cov={ac} route_preds={r['route_preds']} ms={r['median_ms']:.0f}", flush=True)
    if a.out: Path(a.out).write_text(json.dumps(allres, indent=1))
