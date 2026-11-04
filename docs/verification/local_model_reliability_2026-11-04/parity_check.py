"""Python mirror vs Swift pg-cli e2e on identical contexts. Usage: python3 -I parity_check.py <repo root> [URL]"""
import importlib.util, sys
root = sys.argv[1]
sys.argv = [sys.argv[0], root, "/dev/null"] + sys.argv[2:]
spec = importlib.util.spec_from_file_location("bench", root + "/docs/verification/local_model_reliability_2026-11-04/memory_context_bench.py")
src = open(spec.origin).read().split("CONDITIONS = ")[0]
ns = {"__name__": "parity"}; exec(compile(src, spec.origin, "exec"), ns)
for kind, ctx in [("route", "User: Remind me to take my vitamins at 8pm"), ("route", "User: Text Maya that I'm on my way"),
                  ("route", "User: Thanks, that's all for now!"), ("route", "User: Move it"),
                  ("toolChoice", "User: Send Sam a message saying happy birthday")]:
    a, c = ns["decide"](kind, ctx); print(f"{kind:10} {a:15} {c:.3f}  {ctx}")
