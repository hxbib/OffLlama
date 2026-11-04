"""Raw-GGUF evaluation on held-out phone dev/calfit (teacher-top gold).

Starts one llama-server per GGUF, renders trainer-matched zeroShot
prompts, and reads letter logprobs from /completion. A letter absent
from the returned top list is censored evidence: the row is unusable,
never floored or invented. Any unusable row fails evaluation coverage
and no ECE is reported. Gold is the held-out Glimmer teacher top
(selection diagnostic on developer templates, not human gold).

  python3 training/round3/phone_eval.py --gguf X.gguf --name X \
      --rows phone_dev_eval.jsonl --port 8231 --out result.json
"""
import argparse, json, math, subprocess, sys, time, urllib.request
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "training"))
sys.path.insert(0, str(HERE))
from pg_train import prompts
import phone_contracts as PC

SERVER = "/tmp/gencode/llama.cpp/build/bin/llama-server"


def extract_letter_logprobs(top_list, letters):
    """Aggregate token forms per letter. Returns (vals, missing).

    vals is None when any letter is missing or nonfinite.
    """
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


def fetch_letter_logprobs(url, prompt, letters):
    req = urllib.request.Request(
        url + "/completion",
        json.dumps({"prompt": prompt, "n_predict": 1, "n_probs": 40,
                    "temperature": 0, "cache_prompt": True}).encode(),
        {"Content-Type": "application/json"})
    r = json.loads(urllib.request.urlopen(req, timeout=120).read())
    probs = r.get("completion_probabilities") or []
    if not probs or not probs[0].get("top_logprobs"):
        return None, list(letters)
    return extract_letter_logprobs(probs[0]["top_logprobs"], letters)


def softmax(v):
    m = max(v); e = [math.exp(x - m) for x in v]; s = sum(e)
    return [x / s for x in e]


def ece(rows):
    bins = defaultdict(list)
    for p, ok in rows:
        bins[min(9, int(p * 10))].append((p, ok))
    return sum((len(v) / len(rows)) * abs(sum(x[0] for x in v) / len(v)
               - sum(x[1] for x in v) / len(v)) for v in bins.values() if v)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gguf", required=True); ap.add_argument("--name", required=True)
    ap.add_argument("--rows", required=True); ap.add_argument("--port", type=int, default=8231)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    rows = [json.loads(l) for l in open(a.rows) if l.strip()]
    if not rows:
        raise SystemExit(f"empty evaluation rows: {a.rows}")
    proc = subprocess.Popen(
        [SERVER, "-m", a.gguf, "--port", str(a.port), "-t", "4", "-c", "4096"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    url = f"http://127.0.0.1:{a.port}"
    try:
        for _ in range(120):
            if proc.poll() is not None:
                raise RuntimeError(f"llama-server exited early rc={proc.returncode}")
            try:
                urllib.request.urlopen(url + "/health", timeout=2)
                break
            except Exception:
                time.sleep(1)
        else:
            raise RuntimeError("server did not become healthy")
        scored, per = [], defaultdict(lambda: [0, 0])
        unusable = []
        for g in rows:
            if proc.poll() is not None:
                raise RuntimeError("llama-server exited during evaluation")
            s = PC.extended_get_set(g["type"], g.get("candidates"))
            prompt = prompts.llama3(s, g["context"], "zeroShot")
            letters = PC.letters_for(s)
            lp, missing = fetch_letter_logprobs(url, prompt, letters)
            if lp is None:
                unusable.append({"id": g.get("id"), "missing": missing})
                continue
            p = softmax(lp); k = max(range(len(p)), key=lambda i: p[i])
            pred = s["options"][k]["id"]; ok = int(pred == g["gold"])
            scored.append((p[k], ok)); per[g["type"]][0] += ok; per[g["type"]][1] += 1
        coverage_ok = not unusable and len(scored) == len(rows)
        result = {"name": a.name, "gguf": a.gguf, "rows_file": a.rows,
                  "n": len(rows), "usable": len(scored),
                  "unusable": unusable[:20], "unusable_count": len(unusable),
                  "coverage_complete": coverage_ok,
                  "finite_logits": coverage_ok,
                  "acc": (sum(o for _, o in scored) / len(scored)) if scored else None,
                  "ece": ece(scored) if coverage_ok else None,
                  "per_type": {t: {"ok": v[0], "n": v[1]} for t, v in sorted(per.items())},
                  "gold_note": "Held-out Glimmer teacher top on developer templates. Not human gold."}
        Path(a.out).write_text(json.dumps(result, indent=2))
        print(json.dumps(result, indent=2))
        if not coverage_ok:
            raise SystemExit("FAIL: evaluation coverage incomplete (censored letters); no ECE reported")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except Exception:
            proc.kill()


if __name__ == "__main__":
    main()
