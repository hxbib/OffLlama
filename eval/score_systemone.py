"""Score a llama.cpp /v1/systemone decision model (PR ggml-org/llama.cpp#29818) on the gold decisions, same metrics
and JSON shape as score_decisions.py so --compare works.

  python3 eval/score_systemone.py --url http://127.0.0.1:8095 --name Laya-Q8_0 --out eval/results/laya-q8.json

Mapping: each gold item -> one `choice` question; state = gold context, instructions = our set's question,
criteria = {option id: option label}. conf = max option probability (same as our Reflex), NOT upstream's
rescaled `confidence` (which maps uniform->0); both are saved per row."""
import argparse, json, statistics, sys, time, urllib.request
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "training")); sys.path.insert(0, str(ROOT / "eval"))
from pg_train import prompts, calibrate as C
from score_decisions import load_gold


def ask(url, s, context):
    body = {"state": context, "questions": {"q": {"type": "choice", "instructions": s["question"],
            "criteria": {o["id"]: o["label"] for o in s["options"]}}}}
    req = urllib.request.Request(url + "/v1/systemone", json.dumps(body).encode(), {"Content-Type": "application/json"})
    t = time.time(); r = json.load(urllib.request.urlopen(req, timeout=120)); return r["answers"]["q"], (time.time() - t) * 1000


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--url", required=True); ap.add_argument("--name", required=True)
    ap.add_argument("--tau", type=float, default=0.8); ap.add_argument("--gold", default=str(ROOT / "eval/gold_decisions.jsonl")); ap.add_argument("--out")
    a = ap.parse_args(); rows = []
    for g in load_gold(a.gold):
        s = prompts.get_set(g["type"], g.get("candidates"))
        ans, ms = ask(a.url, s, g["context"]); p = ans["probabilities"]; pred = max(p, key=p.get)
        rows.append({"id": g["id"], "type": g["type"], "gold": g["gold"], "pred": pred, "conf": p[pred], "upstream_confidence": ans.get("confidence"),
                     "ok": pred == g["gold"], "covered": p[pred] >= a.tau, "latency_ms": ms})
    cov = [r for r in rows if r["covered"]]
    out = {"model": a.name, "tau": a.tau, "n": len(rows), "accuracy": sum(r["ok"] for r in rows) / len(rows),
           "ece": C.ece([r["conf"] for r in rows], [r["ok"] for r in rows]), "coverage": len(cov) / len(rows),
           "accuracy_on_covered": (sum(r["ok"] for r in cov) / len(cov)) if cov else None,
           "median_latency_ms": statistics.median(r["latency_ms"] for r in rows), "rows": rows}
    print(json.dumps({k: v for k, v in out.items() if k != "rows"}, indent=1))
    if a.out: Path(a.out).write_text(json.dumps(out, indent=1))


if __name__ == "__main__":
    main()
