"""System 2 answer-quality eval (Q&A items from Gate-1) against any OpenAI-compatible chat endpoint or llama-server
(/v1/chat/completions). Auto-graded by key phrases; spot-check by hand.

  python3 eval/run_system2.py --base-url http://127.0.0.1:8088/v1 --model local-llama1b
  PG_ALLOW_SPEND=1 python3 eval/run_system2.py --base-url https://api.meta.ai/v1 --model muse-spark-1.3 --key-env MODEL_API_KEY"""
import argparse, json, os, sys, urllib.request
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from system2_items import QA, NOW


def grade(answer, keys):
    a = answer.lower()
    return all(any(k.lower() in a for k in alts) for alts in keys)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", required=True); ap.add_argument("--model", required=True); ap.add_argument("--key-env")
    ap.add_argument("--max-tokens", type=int, default=300); ap.add_argument("--out")
    a = ap.parse_args()
    remote = not a.base_url.startswith(("http://127.", "http://localhost"))
    if remote and os.environ.get("PG_ALLOW_SPEND") != "1": sys.exit("remote endpoint: set PG_ALLOW_SPEND=1 after spend approval")
    hdr = {"Content-Type": "application/json"}
    if a.key_env: hdr["Authorization"] = "Bearer " + os.environ[a.key_env]
    res = []
    for i, q, ref, keys in QA:
        body = {"model": a.model, "max_tokens": a.max_tokens, "temperature": 0,
                "messages": [{"role": "system", "content": f"You are a concise assistant. {NOW}"}, {"role": "user", "content": q}]}
        r = json.loads(urllib.request.urlopen(urllib.request.Request(a.base_url.rstrip("/") + "/chat/completions", json.dumps(body).encode(), hdr), timeout=300).read())
        ans = r["choices"][0]["message"]["content"] or ""
        res.append({"id": i, "pass": grade(ans, keys), "answer": ans[:300]})
        print(f"{i} {'PASS' if res[-1]['pass'] else 'FAIL'} | {ans[:100]!r}")
    print(f"{a.model}: {sum(r['pass'] for r in res)}/{len(res)}")
    if a.out: Path(a.out).write_text(json.dumps(res, indent=2))


if __name__ == "__main__":
    main()
