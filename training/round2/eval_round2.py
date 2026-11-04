"""Headline chain for one GGUF, same as eval/quant/run_quant_eval.sh but on a private port:
llama-server (-c 4096 -t 4) -> eval/experiments/run_prompt_variants.py run() with variant v2+cc (imported unchanged; only its URL
constant is pointed at our port, so prompts are byte-identical) -> reliability.ece (10 bins) -> pg_train.conformal
(LTT alpha 0.05, delta 0.1, tightest bound over the fixed grid). Graded against the gold field of eval/gold/*.
  python3 training/round2/eval_round2.py --gguf X.gguf --name V1 --port 8092 [--sets cal|test] [--rep 1]
Writes eval/experiments/round2_<name>_<set>[_repN].json (run_prompt_variants format) and ..._summary.json."""
import argparse, json, subprocess, sys, time, urllib.request
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "training")); sys.path.insert(0, str(ROOT / "eval/experiments"))
import run_prompt_variants as R  # noqa: E402
from summarize_repro import metrics  # noqa: E402
ap = argparse.ArgumentParser()
ap.add_argument("--gguf", required=True); ap.add_argument("--name", required=True); ap.add_argument("--port", type=int, required=True)
ap.add_argument("--sets", default="cal"); ap.add_argument("--rep", type=int, default=1); ap.add_argument("--threads", type=int, default=4)
a = ap.parse_args()
assert a.port >= 8092, "ports 8088-8091 belong to other agents"
srv = subprocess.Popen(["/tmp/gencode/llama.cpp/build/bin/llama-server", "-m", a.gguf, "--port", str(a.port), "-t", str(a.threads), "-c", "4096"],
                       stdout=open(f"/tmp/gencode/round2/server_{a.name}_{a.port}.log", "w"), stderr=subprocess.STDOUT)
try:
    for _ in range(120):
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{a.port}/health", timeout=2); break
        except Exception: time.sleep(1)
    R.URL = f"http://127.0.0.1:{a.port}"
    for which in a.sets.split(","):
        rows = R.load(which); t0 = time.time()
        r = R.run(rows, "v2", True, 0.8)
        suf = "" if a.rep == 1 else f"_rep{a.rep}"
        out = ROOT / f"eval/experiments/round2_{a.name}_{which}{suf}.json"
        out.write_text(json.dumps({f"{which}/v2+cc": r}, indent=1))
        m = metrics(r["rows"]); m["eval_seconds"] = round(time.time() - t0, 1); m["gguf"] = a.gguf; m["set"] = which; m["rep"] = a.rep
        (ROOT / f"eval/experiments/round2_{a.name}_{which}{suf}_summary.json").write_text(json.dumps(m, indent=1, default=str))
        lt = m["ltt_tightest"]
        print(f"{a.name} {which} rep{a.rep}: acc {m['acc']:.3f} handled@0.8 {m['handled_at_0.8']:.3f} acc_on_handled {m['acc_on_handled_at_0.8']} "
              f"ECE {m['ece_10bin']:.3f} LTT {lt['error_upper_bound']*100:.1f}% @tau {lt['tau']} {lt['handled']}/{m['n']} err {lt['errors']} "
              f"alpha05 tau {m['ltt_alpha05']['tau']} ({m['eval_seconds']}s)", flush=True)
finally:
    srv.terminate(); srv.wait(timeout=20)
