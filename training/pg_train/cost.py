"""Estimate labeling spend BEFORE any paid call. Counts prompt tokens from the real rendered prompts
(chars/3.6 heuristic, or exact with --tokenizer-url pointing at a llama-server /tokenize), then multiplies by
per-provider prices in config/pricing.json. Prices there are PLACEHOLDERS: confirm on each provider's pricing page.

  python -m pg_train.cost --scenarios out/scenarios.jsonl --teachers spark-baseten,glimmer-modal"""
import argparse, json, urllib.request
from pathlib import Path
from . import prompts

PRICING = Path(__file__).resolve().parent.parent / "config" / "pricing.json"


def count_tokens(text, url=None):
    if url:
        req = urllib.request.Request(url.rstrip("/") + "/tokenize", data=json.dumps({"content": text}).encode(), headers={"Content-Type": "application/json"})
        return len(json.loads(urllib.request.urlopen(req, timeout=30).read())["tokens"])
    return int(len(text) / 3.6) + 1


def estimate(rows, teachers, pricing, url=None, overhead=1.1):
    tin = sum(count_tokens(prompts.SYSTEM + prompts.body(prompts.get_set(r["type"], r.get("candidates")), r["context"]), url) + 12 for r in rows)
    tout = len(rows) * 1
    out = {}
    for t in teachers:
        p = pricing[t]
        if p.get("billing") == "gpu_hour":
            hours = len(rows) / p["requests_per_hour"]
            usd = hours * p["usd_per_gpu_hour"] * p.get("gpus", 1) + p.get("fixed_usd", 0)
        else:
            usd = tin / 1e6 * p["usd_per_m_input"] + tout / 1e6 * p["usd_per_m_output"]
        out[t] = {"rows": len(rows), "input_tokens": tin, "output_tokens": tout, "usd": round(usd * overhead, 2), "verified": p.get("verified", False)}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scenarios", default="out/scenarios.jsonl"); ap.add_argument("--teachers", default="spark-baseten,glimmer-modal,meta")
    ap.add_argument("--n", type=int, default=0, help="estimate for N rows (scales the scenario file)"); ap.add_argument("--tokenizer-url")
    a = ap.parse_args()
    pricing = json.loads(PRICING.read_text())
    rows = [json.loads(l) for l in Path(a.scenarios).read_text().splitlines() if l.strip()]
    est = estimate(rows, a.teachers.split(","), pricing, a.tokenizer_url)
    scale = (a.n / len(rows)) if a.n else 1
    print(f"{'teacher':18s} {'rows':>7s} {'in tok':>10s} {'USD':>9s}  note")
    total = 0
    for t, e in est.items():
        usd = e["usd"] * scale; total += usd
        print(f"{t:18s} {int(e['rows']*scale):7d} {int(e['input_tokens']*scale):10d} {usd:9.2f}  {'' if e['verified'] else 'UNVERIFIED price - check provider page'}")
    print(f"{'TOTAL':18s} {'':7s} {'':10s} {total:9.2f}  (+10% overhead included; nothing was called)")


if __name__ == "__main__":
    main()
