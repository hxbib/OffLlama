"""CLINC out-of-scope stress test (abstention), single-order v2+cc readout, no gold labels.

Input: training/data_scale/out/clinc_oos_test_stress.jsonl (route + answerability items built from CLINC150 'oos' test
utterances). Prompt/readout byte-identical to run_prompt_variants.py v2+cc (reuses its render/letter_logprobs/cf_logp).
Reports chosen-option distribution and confident shares at tau 0.80 / 0.90. NOT a gold-distribution eval: no accuracy,
no conformal claim. Usage:
  python3 eval/experiments/run_oos_stress.py --url http://127.0.0.1:8089 --n 300 --label ship --out eval/experiments/oos_ship_n300.json"""
import argparse, json, sys, time
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent; ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import run_prompt_variants as rpv  # noqa: E402
from pg_train import prompts  # noqa: E402  (path added by rpv)

TAUS = (0.8, 0.9)
LOCAL = {"route": {"answer_local", "tool"}, "answerability": {"yes"}}  # "handle on device" choices


def summarize(rows):
    out = {}
    for ty in ("route", "answerability"):
        rs = [r for r in rows if r["type"] == ty]
        if not rs: continue
        n = len(rs); d = {"n": n, "pred_dist": dict(Counter(r["pred"] for r in rs)),
                          "pred_share": {k: v / n for k, v in Counter(r["pred"] for r in rs).items()}}
        for t in TAUS:
            conf = [r for r in rs if r["conf"] >= t]
            fc = [r for r in conf if r["pred"] in LOCAL[ty]]
            d[f"tau{t}"] = {"confident_share": len(conf) / n, "confident_pred_dist": dict(Counter(r["pred"] for r in conf)),
                           "false_confident_n": len(fc), "false_confident_rate": len(fc) / n}
        out[ty] = d
    allr = rows; n = len(allr)
    out["all"] = {"n": n, **{f"tau{t}": {"false_confident_n": sum(1 for r in allr if r["conf"] >= t and r["pred"] in LOCAL[r["type"]]),
                                         "false_confident_rate": sum(1 for r in allr if r["conf"] >= t and r["pred"] in LOCAL[r["type"]]) / n} for t in TAUS}}
    ms = sorted(r["ms"] for r in allr); out["median_ms"] = ms[n // 2]; out["p90_ms"] = ms[int(0.9 * n) - 1]
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8089"); ap.add_argument("--n", type=int, default=300, help="first N per type")
    ap.add_argument("--label", required=True); ap.add_argument("--out", required=True)
    a = ap.parse_args(); rpv.URL = a.url
    src = ROOT / "training/data_scale/out/clinc_oos_test_stress.jsonl"
    allrows = [json.loads(l) for l in src.read_text().splitlines() if l.strip()]
    items = [r for r in allrows if r["type"] == "route"][: a.n] + [r for r in allrows if r["type"] == "answerability"][: a.n]
    rows = []; t0 = time.time()
    for g in items:
        s = prompts.get_set(g["type"]); L = prompts.letters(s); ids = [o["id"] for o in s["options"]]
        lp, ms = rpv.letter_logprobs(rpv.render(s, g["context"], "v2"), L)
        lp = [x - y for x, y in zip(lp, rpv.cf_logp(s, "v2"))]
        p = rpv.softmax(lp); k = max(range(len(p)), key=lambda i: p[i])
        rows.append({"id": g["id"], "type": g["type"], "context": g["context"], "pred": ids[k], "conf": p[k], "p": dict(zip(ids, p)), "ms": ms})
    res = {"label": a.label, "url": a.url, "source": str(src.relative_to(ROOT)), "n_per_type": a.n, "wall_s": time.time() - t0,
           "summary": summarize(rows), "rows": rows}
    Path(a.out).write_text(json.dumps(res, indent=1))
    print(json.dumps(res["summary"], indent=1))
