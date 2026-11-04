"""Bounded repeat of the 15 cal180 route rows (bare, and mem4 seed 1 with the bench's exact facts), saving raw letter
log-probs, to measure run-to-run variance against memory_context_bench.json.
Usage: python3 -I repeat_check.py <repo root> <bench.json> <out.json> [URL]"""
import json, math, sys
root, bench_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
sys.argv = [sys.argv[0], root, "/dev/null"] + sys.argv[4:]
src_path = root + "/docs/verification/local_model_reliability_2026-11-04/memory_context_bench.py"
ns = {"__name__": "repeat"}; exec(compile(open(src_path).read().split("CONDITIONS = ")[0], src_path, "exec"), ns)
prompts, cal = ns["prompts"], ns["cal"]
first = [r for r in json.load(open(bench_path))["results"] if r["src"] == "cal180" and r["kind"] == "route"
         and (r["cond"] == "bare" or (r["cond"] == "mem4" and r["seed"] == 1))]
out = []
for r in first:
    s = prompts.get_set("route"); L = prompts.letters(s)
    raw = ns["readout"](prompts.llama3(s, ns["render"](r["facts"]) + r["base"], cal["promptStyle"]), L)
    a, c = ns["decide"]("route", ns["render"](r["facts"]) + r["base"])
    out.append({"row": r["row"], "cond": r["cond"], "gold": r["gold"], "facts": r["facts"], "raw_letter_logprobs": raw,
                "run1": {"argmax": r["argmax"], "conf": r["conf"]}, "run2": {"argmax": a, "conf": round(c, 4)}})
d = [abs(o["run2"]["conf"] - o["run1"]["conf"]) for o in out]
flips = sum(o["run2"]["argmax"] != o["run1"]["argmax"] for o in out)
tau_flips = sum((o["run2"]["conf"] >= 0.9) != (o["run1"]["conf"] >= 0.9) for o in out)
summary = {"decisions": len(out), "max_abs_conf_diff": max(d), "mean_abs_conf_diff": sum(d) / len(d),
           "argmax_changes": flips, "tau_side_changes": tau_flips}
json.dump({"summary": summary, "rows": out}, open(out_path, "w"), indent=1)
print(json.dumps(summary))
