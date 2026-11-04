"""Summaries for the Nov 4 box runs: T1 repro (single-order v2+cc) metrics + diff vs the Nov 1 headline rows.
Usage: python3 eval/experiments/summarize_repro.py <run_prompt_variants out json> <key> <out json> [--ref eval/results/after_floor.calibration_split.json]"""
import argparse, json, math, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent; ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "training"))
from pg_train import conformal  # noqa: E402
import reliability  # noqa: E402


def metrics(rows, tau=0.8):
    n = len(rows); conf = [r["conf"] for r in rows]; ok = [bool(r["ok"]) for r in rows]
    cov = [r for r in rows if r["conf"] >= tau]; ms = sorted(r["ms"] for r in rows)
    return {"n": n, "acc": sum(ok) / n, "correct": sum(ok), "handled_at_0.8": len(cov) / n, "handled_n_at_0.8": len(cov),
            "acc_on_handled_at_0.8": sum(r["ok"] for r in cov) / len(cov) if cov else None,
            "ece_10bin": reliability.ece(list(zip(conf, ok)), 10),
            "ltt_tightest": conformal.tightest_bound(conf, ok, 0.1), "ltt_alpha05": conformal.calibrate(conf, ok, 0.05, 0.1),
            "nudgeNow_correct": sum(r["ok"] for r in rows if r["type"] == "nudgeNow"),
            "median_ms": ms[n // 2], "p90_ms": ms[int(math.ceil(0.9 * n)) - 1]}


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("run"); ap.add_argument("key"); ap.add_argument("out")
    ap.add_argument("--ref", default=str(ROOT / "eval/results/after_floor.calibration_split.json"))
    a = ap.parse_args()
    rows = json.loads(Path(a.run).read_text())[a.key]["rows"]
    ref = json.loads(Path(a.ref).read_text())["rows"]
    out = {"source": a.run, "key": a.key, "ref": a.ref, "box": metrics(rows), "ref_metrics": metrics(ref) if all("ms" in r for r in ref) else None}
    if len(ref) == len(rows):
        pd = [i for i in range(len(rows)) if rows[i]["pred"] != ref[i]["pred"]]
        out["diff_vs_ref"] = {"n_pred_changed": len(pd), "changed_idx": pd, "n_ok_changed": sum(rows[i]["ok"] != ref[i]["ok"] for i in range(len(rows))),
                              "max_abs_conf_diff": max(abs(rows[i]["conf"] - ref[i]["conf"]) for i in range(len(rows))),
                              "mean_abs_conf_diff": sum(abs(rows[i]["conf"] - ref[i]["conf"]) for i in range(len(rows))) / len(rows),
                              "gold_order_match": all(rows[i]["gold"] == ref[i]["gold"] and rows[i]["type"] == ref[i]["type"] for i in range(len(rows)))}
    Path(a.out).write_text(json.dumps(out, indent=1)); print(json.dumps({k: v for k, v in out.items() if k != "diff_vs_ref"} | {"diff": {k: v for k, v in out.get("diff_vs_ref", {}).items() if k != "changed_idx"}}, indent=1, default=str))
