"""Side-by-side OOS stress summary (shipping vs base, full 2000 and the first-300 replicate) + mean confidences + run-to-run diff.
Usage: python3 eval/experiments/summarize_oos.py --out eval/experiments/oos_stress_summary.json"""
import argparse, json, statistics
from pathlib import Path
HERE = Path(__file__).resolve().parent
LOCAL = {"route": {"answer_local", "tool"}, "answerability": {"yes"}}
if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--out", required=True); a = ap.parse_args(); res = {}
    for lab in ("ship", "base"):
        full = json.loads((HERE / f"oos_{lab}_full2000.json").read_text()); n3 = json.loads((HERE / f"oos_{lab}_n300.json").read_text())
        m = {r["id"]: r for r in full["rows"]}
        res[lab] = {"full2000_summary": full["summary"], "n300_summary": n3["summary"], "wall_s_full": full["wall_s"],
                    "mean_conf": {ty: statistics.mean(r["conf"] for r in full["rows"] if r["type"] == ty) for ty in ("route", "answerability")},
                    "n300_vs_full_same_items_pred_changed": sum(m[r["id"]]["pred"] != r["pred"] for r in n3["rows"]),
                    "n300_vs_full_same_items_max_conf_diff": max(abs(m[r["id"]]["conf"] - r["conf"]) for r in n3["rows"]),
                    "full_false_confident_items_tau0.9": [{"id": r["id"], "pred": r["pred"], "conf": r["conf"], "utterance": r["context"].split("User: ")[-1]}
                                                          for r in full["rows"] if r["conf"] >= 0.9 and r["pred"] in LOCAL[r["type"]]]}
    Path(a.out).write_text(json.dumps(res, indent=1)); print(json.dumps({k: {kk: v[kk] for kk in ("mean_conf", "n300_vs_full_same_items_pred_changed", "n300_vs_full_same_items_max_conf_diff")} for k, v in res.items()}, indent=1))
