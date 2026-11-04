"""Poll the Modal volume pg-round2 for finished Q4_K_M GGUFs, download each to /tmp/gencode/round2/<name>.gguf (not the repo),
and run the cal180 headline chain (training/round2/eval_round2.py) on ports 8092-8095, 4 at a time. A second repeat run is
scheduled for every candidate whose first run passes the loose gate or has an LTT bound < 11% (noise rule: finalists get 2 runs).
Run with the Modal venv python:  /tmp/gencode/modalenv/bin/python training/round2/eval_poller.py --expect V0-s720,...
Never touches test120."""
import argparse, json, queue, subprocess, threading, time, datetime
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from zoneinfo import ZoneInfo
import modal
ROOT = Path(__file__).resolve().parents[2]
ap = argparse.ArgumentParser(); ap.add_argument("--expect", required=True); ap.add_argument("--until", default="08:14")
ap.add_argument("--ports", default="8092,8093,8094,8095")
a = ap.parse_args()
hh, mm = map(int, a.until.split(":"))
STOP = datetime.datetime.now(ZoneInfo("America/New_York")).replace(hour=hh, minute=mm, second=0).timestamp()
vol = modal.Volume.from_name("pg-round2")
expect = a.expect.split(","); ports = queue.Queue()
for p in map(int, a.ports.split(",")): ports.put(p)
ex = ThreadPoolExecutor(len(a.ports.split(","))); lock = threading.Lock(); submitted = set(); log = open("/tmp/gencode/round2/poller.log", "a")


def P(*x):
    with lock: print(datetime.datetime.now(ZoneInfo("America/New_York")).strftime("%H:%M:%S"), *x, file=log, flush=True)


def run_eval(name, rep):
    port = ports.get()
    try:
        r = subprocess.run(["python3", str(ROOT / "training/round2/eval_round2.py"), "--gguf", f"/tmp/gencode/round2/{name}.gguf", "--name", name,
                            "--port", str(port), "--rep", str(rep)], capture_output=True, text=True, cwd=ROOT)
        P(name, f"rep{rep}", r.stdout.strip()[-400:], r.stderr.strip()[-300:] if r.returncode else "")
    finally:
        ports.put(port)
    if rep == 1:
        f = ROOT / f"eval/experiments/round2_{name}_cal_summary.json"
        if f.exists():
            m = json.loads(f.read_text()); lt = m["ltt_tightest"]
            loose = (lt["error_upper_bound"] < 0.1040 and lt["handled_share"] >= 0.35 or m["ltt_alpha05"]["tau"] is not None) \
                and (m["acc_on_handled_at_0.8"] or 0) >= 0.95 and m["ece_10bin"] <= 0.06
            if (loose or lt["error_upper_bound"] < 0.11) and time.time() < STOP:
                P(name, "-> scheduling rep2"); ex.submit(run_eval, name, 2)


import hashlib


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 24), b""): h.update(b)
    return h.hexdigest()


def fetch(name, want):
    """returns True if a (new) verified file is in place and needs evaluating"""
    dst = Path(f"/tmp/gencode/round2/{name}.gguf")
    if dst.exists() and sha(dst) == want:
        P(name, "local file already verified", want[:12])
        return not (ROOT / f"eval/experiments/round2_{name}_cal_summary.json").exists()
    tmp = dst.with_suffix(".part")
    with open(tmp, "wb") as f:
        for chunk in vol.read_file(f"/gguf/{name}.gguf"): f.write(chunk)
    got = sha(tmp)
    if got != want: P(name, "SHA MISMATCH", got[:12], want[:12]); tmp.unlink(); raise RuntimeError("sha mismatch")
    tmp.rename(dst); P(name, "downloaded+verified", dst.stat().st_size, want[:12])
    (ROOT / f"eval/experiments/round2_{name}_cal_summary.json").unlink(missing_ok=True)
    return True


while time.time() < STOP and len(submitted) < len(expect):
    try:
        have = {Path(e.path).stem for e in vol.listdir("/logs")}
    except Exception as e:
        P("listdir error", e); have = set()
    for n in expect:
        if n in have and n not in submitted:
            submitted.add(n)
            try:
                d = json.loads(b"".join(vol.read_file(f"/logs/{n}.json")))
                tr = d.get("train_result", {})
                P(n, "modal log: ok", d.get("ok"), "train_s", d.get("train_s"), "total_s", d.get("total_s"), "steps", tr.get("steps_done"), "/", tr.get("steps"),
                  "zeroShot-cal acc", tr.get("after_zeroShot", {}).get("acc"), "mean_conf", tr.get("after_zeroShot", {}).get("mean_conf"), d.get("error", "")[-300:])
                (ROOT / "training/round2/out/modal_logs").mkdir(parents=True, exist_ok=True)
                (ROOT / f"training/round2/out/modal_logs/{n}.json").write_text(json.dumps(d, indent=1))
                if not d.get("ok"): continue
                if fetch(n, d["gguf_sha256"]): ex.submit(run_eval, n, 1)
            except Exception as e: P(n, "fetch error", e); submitted.discard(n); continue
    time.sleep(20)
P("poll loop done; submitted", sorted(submitted), "missing", sorted(set(expect) - submitted))
ex.shutdown(wait=True); P("all evals done")
