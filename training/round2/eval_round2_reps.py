"""Repeat-run probe for gate finalists: ONE fresh llama-server start (same flags as eval_round2.py: -c 4096 -t 4), then several
back-to-back passes of the identical cal180 v2+cc chain (run_prompt_variants.run, reliability ECE, pg_train.conformal LTT).
Pass 1 on the fresh server = the "fresh-server repeat" (expected to reproduce rep1 exactly, PERM_AVG.md noise floor);
passes 2.. run on a server that has already served cal180 once (warm prompt cache / slot numerics) = the warm-server noise probe.
  python3 training/round2/eval_round2_reps.py --gguf X.gguf --name V4-gpuC --port 8096 --first-rep 2 --passes 2
Writes eval/experiments/round2_<name>_cal_rep<N>.json and ..._summary.json (summary gets "server_pass": 1 = fresh, >=2 = warm)."""
import argparse, json, subprocess, sys, time, urllib.request
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "training")); sys.path.insert(0, str(ROOT / "eval/experiments"))
import run_prompt_variants as R  # noqa: E402
from summarize_repro import metrics  # noqa: E402
ap = argparse.ArgumentParser()
ap.add_argument("--gguf", required=True); ap.add_argument("--name", required=True); ap.add_argument("--port", type=int, required=True)
ap.add_argument("--first-rep", type=int, default=2); ap.add_argument("--passes", type=int, default=2); ap.add_argument("--threads", type=int, default=4)
a = ap.parse_args()
assert a.port >= 8092, "ports 8088-8091 belong to other agents"
srv = subprocess.Popen(["/tmp/gencode/llama.cpp/build/bin/llama-server", "-m", a.gguf, "--port", str(a.port), "-t", str(a.threads), "-c", "4096"],
                       stdout=open(f"/tmp/gencode/round2/server_{a.name}_{a.port}_reps.log", "w"), stderr=subprocess.STDOUT)
try:
    for _ in range(120):
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{a.port}/health", timeout=2); break
        except Exception: time.sleep(1)
    R.URL = f"http://127.0.0.1:{a.port}"
    rows = R.load("cal")
    for k in range(a.passes):
        rep = a.first_rep + k; t0 = time.time()
        r = R.run(rows, "v2", True, 0.8)
        out = ROOT / f"eval/experiments/round2_{a.name}_cal_rep{rep}.json"
        out.write_text(json.dumps({"cal/v2+cc": r}, indent=1))
        m = metrics(r["rows"]); m.update(eval_seconds=round(time.time() - t0, 1), gguf=a.gguf, set="cal", rep=rep, server_pass=k + 1,
                                         server="fresh start" if k == 0 else f"warm (pass {k + 1} on the same server)")
        (ROOT / f"eval/experiments/round2_{a.name}_cal_rep{rep}_summary.json").write_text(json.dumps(m, indent=1, default=str))
        lt = m["ltt_tightest"]
        print(f"{a.name} cal rep{rep} (server pass {k + 1}): acc {m['acc']:.3f} handled@0.8 {m['handled_at_0.8']:.3f} "
              f"acc_on_handled {m['acc_on_handled_at_0.8']} ECE {m['ece_10bin']:.3f} LTT {lt['error_upper_bound']*100:.1f}% @tau {lt['tau']} "
              f"{lt['handled']}/{m['n']} err {lt['errors']} ({m['eval_seconds']}s)", flush=True)
finally:
    srv.terminate(); srv.wait(timeout=20)
