"""Latency summary for the Nov 4 box runs (box CPU, not iPhone). Reads per-decision HTTP ms and llama-server timings.
Usage: python3 eval/experiments/summarize_latency.py --out eval/experiments/latency_box.json \
         --single LABEL=path[:key] ... --perm LABEL=path:mode ...
single: run_prompt_variants.py output (rows[].ms, one /completion per decision; key default cal/v2+cc)
perm:   run_perm_avg.py output (items[].timings per permutation; reports order0 = single order, and the K-call total)"""
import argparse, json, math, statistics
from pathlib import Path


def pct(v, q):
    v = sorted(v); return v[max(0, int(math.ceil(q * len(v))) - 1)]


def stats(v):
    return {"n": len(v), "median": statistics.median(v), "p90": pct(v, 0.9), "mean": statistics.mean(v), "max": max(v)}


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--out", required=True)
    ap.add_argument("--single", nargs="*", default=[]); ap.add_argument("--perm", nargs="*", default=[])
    a = ap.parse_args(); res = {"note": "box CPU (AMD EPYC-Turin, x86 AVX2/AVX-512), llama.cpp 13ec8f6 llama-server, HTTP round trip on localhost; NOT iPhone", "runs": {}}
    for s in a.single:
        lab, rest = s.split("=", 1); path, key = (rest.split(":", 1) + ["cal/v2+cc"])[:2]
        rows = json.loads(Path(path).read_text())[key]["rows"]
        res["runs"][lab] = {"source": f"{path} [{key}] rows[].ms", "k": 1, "ms_per_decision": stats([r["ms"] for r in rows])}
    for s in a.perm:
        lab, rest = s.split("=", 1); path, mode = rest.rsplit(":", 1)
        items = json.loads(Path(path).read_text())["modes"][mode]["items"]
        o0 = [it["timings"][0] for it in items]
        res["runs"][lab + "/order0"] = {"source": f"{path} modes.{mode}.items[].timings[0]", "k": 1,
                                        "ms_per_decision": stats([t["ms"] for t in o0]),
                                        "prompt_tokens": stats([t["tokens_evaluated"] for t in o0]),
                                        "uncached_prompt_tokens": stats([t["prompt_n"] for t in o0]),
                                        "server_prompt_ms": stats([t["prompt_ms"] for t in o0])}
        res["runs"][lab + "/all_K"] = {"source": f"{path} modes.{mode}.items[].timings (sum over permutations)",
                                       "k_mean": statistics.mean(len(it["timings"]) for it in items),
                                       "ms_per_decision": stats([sum(t["ms"] for t in it["timings"]) for it in items]),
                                       "prompt_tokens_per_decision": stats([sum(t["tokens_evaluated"] for t in it["timings"]) for it in items]),
                                       "uncached_prompt_tokens_per_decision": stats([sum(t["prompt_n"] for t in it["timings"]) for it in items]),
                                       "wall_s_including_cf": json.loads(Path(path).read_text())["modes"][mode]["wall_s_including_cf"]}
    Path(a.out).write_text(json.dumps(res, indent=1))
    for k, v in res["runs"].items():
        m = v["ms_per_decision"]; print(f"{k:28s} K={v.get('k', v.get('k_mean')):.2f} median {m['median']:.0f} ms p90 {m['p90']:.0f} ms", 
                                        "" if "prompt_tokens" not in v else f"prompt tok med {v['prompt_tokens']['median']:.0f} uncached med {v['uncached_prompt_tokens']['median']:.0f}")
