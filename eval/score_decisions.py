"""Score Reflex students and teachers on the hand-labeled gold set (gold_decisions.jsonl).

  # student or local model served by llama-server (free)
  python3 eval/score_decisions.py --model local --url http://127.0.0.1:8088 --tau 0.8 --out eval/out/llama1b-base.json
  # teacher (paid; refuses without PG_ALLOW_SPEND=1)
  python3 eval/score_decisions.py --model spark-baseten
  # compare saved runs
  python3 eval/score_decisions.py --compare eval/out/*.json

Metrics: argmax accuracy, ECE, coverage at tau (share handled locally), accuracy on covered (what users feel),
and median per-decision latency (HTTP round-trip; NOT a phone number)."""
import argparse, glob, json, statistics, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "training"))
from pg_train import prompts, teachers as T, calibrate as C


def load_gold(p=ROOT / "eval/gold/gold_test.jsonl"):
    return [json.loads(l) for l in Path(p).read_text().splitlines() if l.strip()]


def score(model, gold, tau, temperature=1.0, profile=None):
    rows = []
    for g in gold:
        s = prompts.get_set(g["type"], g.get("candidates"))
        L = prompts.letters(s); ids = [o["id"] for o in s["options"]]
        lab = model.label(s, g["context"])
        p = lab["probs"] or ({lab["letter"]: 1.0} if lab["letter"] else {})
        t = (profile or {}).get("temperature", {}).get(g["type"], temperature)
        logits = [C.math.log(max(p.get(l, 1e-9), 1e-9)) for l in L]
        key = g["type"] + (f"#{len(L)}" if g["type"] in ("contactPick", "eventPick") else "")
        pr = (profile or {}).get("prior", {}).get(key)
        if pr and len(pr) == len(L): logits = [a - b for a, b in zip(logits, pr)]   # contextual calibration
        q = C.softmax(logits, t)
        k = max(range(len(L)), key=lambda i: q[i])
        th = (profile or {}).get("tau", {}).get(g["type"], tau)
        rows.append({"id": g["id"], "type": g["type"], "gold": g["gold"], "pred": ids[k], "conf": q[k], "ok": ids[k] == g["gold"],
                     "covered": q[k] >= th, "latency_ms": lab["latency_ms"]})
    cov = [r for r in rows if r["covered"]]
    return {"model": model.name, "tau": tau, "n": len(rows),
            "accuracy": sum(r["ok"] for r in rows) / len(rows),
            "ece": C.ece([r["conf"] for r in rows], [r["ok"] for r in rows]),
            "coverage": len(cov) / len(rows),
            "accuracy_on_covered": (sum(r["ok"] for r in cov) / len(cov)) if cov else None,
            "median_latency_ms": statistics.median(r["latency_ms"] for r in rows), "rows": rows}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="local"); ap.add_argument("--url", default="http://127.0.0.1:8088")
    ap.add_argument("--name"); ap.add_argument("--tau", type=float, default=0.8); ap.add_argument("--calibration")
    ap.add_argument("--out"); ap.add_argument("--compare", nargs="*"); ap.add_argument("--gold", default=str(ROOT / "eval/gold/gold_test.jsonl"))
    ap.add_argument("--style", default="fewShot")
    a = ap.parse_args()
    if a.compare:
        print(f"{'model':40s} {'acc':>5s} {'ECE':>5s} {'cov':>5s} {'acc@cov':>7s} {'ms':>6s}")
        for f in a.compare:
            r = json.loads(Path(f).read_text())
            ac = "-" if r["accuracy_on_covered"] is None else f"{r['accuracy_on_covered']:.2f}"
            print(f"{r['model']:40s} {r['accuracy']:5.2f} {r['ece']:5.2f} {r['coverage']:5.2f} {ac:>7s} {r['median_latency_ms']:6.0f}")
        return
    reg = {"local": lambda: T.LocalLlamaServerTeacher(url=a.url, name=a.name or "local", style=a.style),
           "spark-baseten": T.muse_spark_open_baseten, "spark-fireworks": T.spark_open_fireworks, "glimmer-modal": T.glimmer_modal, "meta": T.meta_model_api}
    prof = json.loads(Path(a.calibration).read_text()) if a.calibration else None
    res = score(reg[a.model](), load_gold(a.gold), a.tau, profile=prof)
    print(json.dumps({k: v for k, v in res.items() if k != "rows"}, indent=2))
    for r in res["rows"]:
        if not r["ok"]: print(f"  ✗ {r['id']} {r['type']}: gold={r['gold']} pred={r['pred']} conf={r['conf']:.2f}")
    if a.out:
        Path(a.out).parent.mkdir(parents=True, exist_ok=True); Path(a.out).write_text(json.dumps(res, indent=2))


if __name__ == "__main__":
    main()
