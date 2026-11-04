"""R3E2 duration diagnostic. Matched cal180 v2+cc evaluation for three GGUFs.

Protocol frozen in docs/training/ROUND3_EXECUTION.md Evaluate the completed
duration pilot now. Two fresh llama-server starts per model, each start runs
one fresh pass then one warm pass on the same server. Four passes per model.
Row order, v2 relabeling, few-shot rendering and empty-context priors reuse
eval/experiments/run_prompt_variants.py unchanged. Only its URL is pointed
at the isolated server. Metrics reuse eval/experiments/summarize_repro.py
which uses training/reliability.py ECE and training/pg_train/conformal.py.

Server flags are fixed: llama-server -c 4096 -t 4. No test120. No threshold
or prior fitting. This is a historical diagnostic, not promotion evidence.

Usage:
  python3 training/round3/duration_eval.py --gguf PATH --name SHIP --port 8124
  python3 training/round3/duration_eval.py --aggregate
  python3 training/round3/duration_eval.py --drift-gguf PATH --port 8124
"""
import argparse
import hashlib
import json
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "training"))
sys.path.insert(0, str(ROOT / "eval" / "experiments"))
import run_prompt_variants as R  # noqa: E402
from summarize_repro import metrics  # noqa: E402

SERVER = "/tmp/gencode/llama.cpp/build/bin/llama-server"
LOGDIR = Path("/tmp/pocket-glimmer-training-scale/r3e2-eval")
GOLD_CAL = ROOT / "eval" / "gold" / "gold_calibration.jsonl"


def sha256_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def legacy_gate(m):
    lt = m["ltt_tightest"]
    bound = lt["error_upper_bound"]
    share = lt["handled_share"]
    acc_handled = m.get("acc_on_handled_at_0.8")
    clause_a = bound is not None and bound < 0.10 and share is not None and share >= 0.35
    clause_b = acc_handled is not None and acc_handled >= 0.95
    clause_c = m["ece_10bin"] <= 0.06
    return {
        "clause_a_bound_lt_10pct_share_ge_35pct": bool(clause_a),
        "clause_b_acc_on_handled_at_0.8_ge_0.95": bool(clause_b),
        "clause_c_ece_le_0.06": bool(clause_c),
        "overall": bool(clause_a and clause_b and clause_c),
        "bound": bound,
        "handled_share_at_bound_tau": share,
        "tau_at_bound": lt["tau"],
        "handled_at_bound": lt["handled"],
        "errors_at_bound": lt["errors"],
    }


def per_type_counts(rows):
    out = {}
    for r in rows:
        t = r["type"]
        d = out.setdefault(t, {"n": 0, "correct": 0, "handled_at_0.8": 0, "correct_on_handled_at_0.8": 0})
        d["n"] += 1
        d["correct"] += int(bool(r["ok"]))
        if r["conf"] >= 0.8:
            d["handled_at_0.8"] += 1
            d["correct_on_handled_at_0.8"] += int(bool(r["ok"]))
    return out


def prompt_identity_hash(gold_rows):
    parts = []
    for g in gold_rows:
        s = R.prompts.get_set(g["type"], g.get("candidates"))
        parts.append(R.render(s, g["context"], "v2"))
    blob = "\n\x00\n".join(parts).encode()
    return hashlib.sha256(blob).hexdigest(), len(parts)


def cf_identity():
    items = sorted((str(k), list(v)) for k, v in R._cf_cache.items())
    blob = json.dumps(items, sort_keys=True).encode()
    return hashlib.sha256(blob).hexdigest(), len(items)


def verify_rows(rows, gold_rows):
    n = len(rows)
    gold_seq = [(g["type"], g["gold"]) for g in gold_rows]
    got_seq = [(r["type"], r["gold"]) for r in rows]
    errors = sum(1 for r in rows if not r["ok"])
    correct = sum(1 for r in rows if r["ok"])
    return {
        "n": n,
        "expected_n": len(gold_rows),
        "count_ok": n == len(gold_rows) == 180,
        "order_match": got_seq == gold_seq,
        "errors": errors,
        "correct": correct,
        "error_count_check": errors + correct == n,
    }


def load_gold():
    return [json.loads(l) for l in GOLD_CAL.read_text().splitlines() if l.strip()]


def wait_health(port, timeout_s=120):
    for _ in range(timeout_s):
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=2)
            return True
        except Exception:
            time.sleep(1)
    return False


def port_free(port):
    import socket
    s = socket.socket()
    try:
        s.bind(("127.0.0.1", port))
        return True
    except OSError:
        return False
    finally:
        s.close()


def run_one_model(gguf, name, port):
    LOGDIR.mkdir(parents=True, exist_ok=True)
    gguf_path = str(gguf)
    digest = sha256_file(gguf)
    gold = load_gold()
    phash, pn = prompt_identity_hash(gold)
    print(f"{name} gguf_sha256 {digest} prompt_hash {phash} prompts {pn} gold_n {len(gold)}", flush=True)
    summaries = []
    for start in (1, 2):
        log_path = LOGDIR / f"server_{name}_s{start}_{port}.log"
        cmd = [SERVER, "-m", gguf_path, "--port", str(port), "-t", "4", "-c", "4096"]
        print(f"{name} start {start} cmd {' '.join(cmd)} log {log_path}", flush=True)
        with open(log_path, "w") as lf:
            srv = subprocess.Popen(cmd, stdout=lf, stderr=subprocess.STDOUT)
            try:
                if not wait_health(port):
                    raise RuntimeError(f"server did not become healthy on port {port}; see {log_path}")
                R.URL = f"http://127.0.0.1:{port}"
                R._cf_cache.clear()
                rows_in = R.load("cal")
                assert len(rows_in) == 180, f"cal rows {len(rows_in)}"
                for k in range(2):
                    server_pass = k + 1
                    state = "fresh" if k == 0 else "warm"
                    global_pass = (start - 1) * 2 + k + 1
                    t0 = time.time()
                    r = R.run(rows_in, "v2", True, 0.8)
                    elapsed = round(time.time() - t0, 1)
                    raw_name = f"r3e2_{name}_cal_s{start}p{server_pass}.json"
                    raw_path = ROOT / "eval" / "experiments" / raw_name
                    raw_path.write_text(json.dumps({"cal/v2+cc": r}, indent=1))
                    m = metrics(r["rows"])
                    m["eval_seconds"] = elapsed
                    ver = verify_rows(r["rows"], gold)
                    cfh, cfn = cf_identity()
                    gate = legacy_gate(m)
                    summary = dict(m)
                    summary.update({
                        "gguf": gguf_path,
                        "gguf_sha256": digest,
                        "model_name": name,
                        "set": "cal",
                        "variant": "v2+cc",
                        "start": start,
                        "pass_in_start": server_pass,
                        "global_pass": global_pass,
                        "server_pass": server_pass,
                        "server_state": state,
                        "server": f"{state} (start {start} pass {server_pass})",
                        "threads": 4,
                        "context": 4096,
                        "server_cmd": " ".join(cmd),
                        "raw_file": f"eval/experiments/{raw_name}",
                        "prompt_identity_sha256": phash,
                        "prompt_count": pn,
                        "cf_identity_sha256": cfh,
                        "cf_entries": cfn,
                        "verification": ver,
                        "per_type": per_type_counts(r["rows"]),
                        "legacy_gate": gate,
                    })
                    sum_path = ROOT / "eval" / "experiments" / f"r3e2_{name}_cal_s{start}p{server_pass}_summary.json"
                    sum_path.write_text(json.dumps(summary, indent=1, default=str))
                    summaries.append(summary)
                    lt = m["ltt_tightest"]
                    print(f"{name} s{start}p{server_pass} global{global_pass} {state}: n={m['n']} acc {m['acc']:.4f} "
                          f"handled@0.8 {m['handled_at_0.8']:.4f} acc_on {m['acc_on_handled_at_0.8']} ECE {m['ece_10bin']:.4f} "
                          f"LTT {lt['error_upper_bound']*100:.2f}% @tau {lt['tau']} {lt['handled']}/{m['n']} err {lt['errors']} "
                          f"gate {gate['overall']} a={gate['clause_a_bound_lt_10pct_share_ge_35pct']} "
                          f"b={gate['clause_b_acc_on_handled_at_0.8_ge_0.95']} c={gate['clause_c_ece_le_0.06']} "
                          f"ver_order={ver['order_match']} ({elapsed}s)", flush=True)
            finally:
                srv.terminate()
                try:
                    srv.wait(timeout=20)
                except Exception:
                    srv.kill()
        time.sleep(2)
    return summaries


def paired_delta(cand, base):
    def d(k):
        a, b = cand.get(k), base.get(k)
        return (a - b) if (a is not None and b is not None) else None
    lt_c, lt_b = cand["ltt_tightest"], base["ltt_tightest"]
    return {
        "candidate": cand["model_name"],
        "baseline": base["model_name"],
        "global_pass": cand["global_pass"],
        "server_state": cand["server_state"],
        "delta_acc": d("acc"),
        "delta_ece": d("ece_10bin"),
        "delta_bound": lt_c["error_upper_bound"] - lt_b["error_upper_bound"],
        "delta_handled_share_at_bound": lt_c["handled_share"] - lt_b["handled_share"],
        "delta_handled_at_0.8": d("handled_at_0.8"),
        "delta_acc_on_handled_at_0.8": d("acc_on_handled_at_0.8"),
        "delta_errors_at_bound": lt_c["errors"] - lt_b["errors"],
        "candidate_gate": cand["legacy_gate"]["overall"],
        "baseline_gate": base["legacy_gate"]["overall"],
    }


def aggregate():
    exp = ROOT / "eval" / "experiments"
    files = sorted(exp.glob("r3e2_*_cal_s*p*_summary.json"))
    by_model = {}
    for f in files:
        s = json.loads(f.read_text())
        by_model.setdefault(s["model_name"], []).append(s)
    for v in by_model.values():
        v.sort(key=lambda x: x["global_pass"])
    deltas = []
    names = list(by_model)
    cand_name = "R3E2"
    if cand_name in by_model:
        for base_name in names:
            if base_name == cand_name:
                continue
            base_by_pass = {s["global_pass"]: s for s in by_model[base_name]}
            for cs in by_model[cand_name]:
                bs = base_by_pass.get(cs["global_pass"])
                if bs is not None:
                    deltas.append(paired_delta(cs, bs))
    out = {"models": by_model, "paired_deltas_candidate_vs_baseline": deltas,
           "note": "Legacy gate is per pass. Averaging across passes must not hide a failing pass. Even a legacy pass is not promotion; independent new benchmark pending."}
    out_path = exp / "r3e2_aggregate.json"
    out_path.write_text(json.dumps(out, indent=1, default=str))
    print(f"wrote {out_path} models {list(by_model)} deltas {len(deltas)}")
    for model, rows in by_model.items():
        for s in rows:
            g = s["legacy_gate"]
            lt = s["ltt_tightest"]
            print(f"{model} g{s['global_pass']} {s['server_state']} start{s['start']}: bound {lt['error_upper_bound']*100:.2f}% "
                  f"share {lt['handled_share']:.3f} tau {lt['tau']} handled {lt['handled']} err {lt['errors']} "
                  f"handled@0.8 {s['handled_at_0.8']:.3f} acc_on {s['acc_on_handled_at_0.8']} ECE {s['ece_10bin']:.4f} gate {g['overall']}")
    for dd in deltas:
        print(f"delta {dd['candidate']} vs {dd['baseline']} g{dd['global_pass']} {dd['server_state']}: "
              f"dBound {dd['delta_bound']*100:+.2f}pp dECE {dd['delta_ece']:+.4f} dHandled@0.8 {dd['delta_handled_at_0.8']:+.4f} "
              f"dAccOn {dd['delta_acc_on_handled_at_0.8']} dAcc {dd['delta_acc']:+.4f}")
    return out


COLLAPSE = re.compile(r'^\s*[\{\[]|"\w+"\s*:|\b(request_type|route|label|intent|category)\b\s*[:=]|^\s*[A-Z_]{4,}\s*$', re.I | re.M)


def drift_check(text, answers):
    if not answers:
        return None
    t = text.lower()
    return any((re.search(r'(?<!\d)' + re.escape(a) + r'(?!\d)', t) if a.isdigit() else a in t) for a in answers)


def drift_prompt_text(user_prompt):
    return ("<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n"
            "Cutting Knowledge Date: December 2023\nToday Date: 26 Jul 2024\n\n<|eot_id|>"
            "<|start_header_id|>user<|end_header_id|>\n\n" + user_prompt.strip() + "<|eot_id|>"
            "<|start_header_id|>assistant<|end_header_id|>\n\n")


def run_drift(gguf, port, label):
    LOGDIR.mkdir(parents=True, exist_ok=True)
    prompts_path = ROOT / "eval" / "drift" / "prompts.jsonl"
    rows = [json.loads(l) for l in prompts_path.read_text().splitlines() if l.strip()]
    digest = sha256_file(gguf)
    log_path = LOGDIR / f"server_drift_{label}_{port}.log"
    cmd = [SERVER, "-m", str(gguf), "--port", str(port), "-t", "4", "-c", "4096"]
    print(f"drift {label} sha {digest} cmd {' '.join(cmd)} prompts {len(rows)}", flush=True)
    out_path = ROOT / "eval" / "experiments" / f"r3e2_drift_{label}.jsonl"
    with open(log_path, "w") as lf:
        srv = subprocess.Popen(cmd, stdout=lf, stderr=subprocess.STDOUT)
        try:
            if not wait_health(port):
                raise RuntimeError(f"drift server unhealthy; see {log_path}")
            t0 = time.time()
            with open(out_path, "w") as out:
                for r in rows:
                    body = json.dumps({"prompt": drift_prompt_text(r["prompt"]), "n_predict": 96,
                                       "temperature": 0, "top_k": 1, "cache_prompt": False, "seed": 0}).encode()
                    req = urllib.request.Request(f"http://127.0.0.1:{port}/completion", body,
                                                 {"Content-Type": "application/json"})
                    res = json.loads(urllib.request.urlopen(req, timeout=180).read())
                    txt = res["content"].strip()
                    rec = {"id": r["id"], "category": r["category"], "model": label,
                           "gguf_sha256": digest, "out": txt,
                           "ok": drift_check(txt, r["answers"]), "collapse": bool(COLLAPSE.search(txt))}
                    out.write(json.dumps(rec) + "\n")
                    out.flush()
            print(f"drift {label} done {round(time.time()-t0,1)}s -> {out_path}", flush=True)
        finally:
            srv.terminate()
            try:
                srv.wait(timeout=20)
            except Exception:
                srv.kill()
    recs = [json.loads(l) for l in out_path.read_text().splitlines() if l.strip()]
    checkable = [r for r in recs if r["ok"] is not None]
    correct = sum(1 for r in checkable if r["ok"])
    collapse = sum(1 for r in recs if r["collapse"])
    summ = {"label": label, "gguf_sha256": digest, "n_prompts": len(recs),
            "n_checkable": len(checkable), "checkable_correct": correct,
            "collapse": collapse, "raw_file": f"eval/experiments/r3e2_drift_{label}.jsonl",
            "method": "llama-server /completion, HF Llama-3.2 single-user chat string (26 Jul 2024 date), greedy temp0 top_k1 n_predict96 seed0, check/collapse logic copied from eval/drift/run_drift_gguf.py"}
    (ROOT / "eval" / "experiments" / f"r3e2_drift_{label}_summary.json").write_text(json.dumps(summ, indent=1))
    print(json.dumps(summ, indent=1), flush=True)
    return summ


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gguf")
    ap.add_argument("--name")
    ap.add_argument("--port", type=int, default=8124)
    ap.add_argument("--aggregate", action="store_true")
    ap.add_argument("--drift-gguf")
    ap.add_argument("--drift-label", default="R3E2")
    a = ap.parse_args()
    if a.aggregate:
        aggregate()
        return
    if a.drift_gguf:
        p = a.port
        while not port_free(p):
            p += 1
        print(f"drift port selected {p}")
        run_drift(a.drift_gguf, p, a.drift_label)
        return
    assert a.gguf and a.name, "need --gguf and --name or --aggregate/--drift-gguf"
    assert a.port >= 8124, "isolated ports start at 8124"
    p = a.port
    while not port_free(p):
        p += 1
    print(f"port selected {p} (requested {a.port})")
    run_one_model(a.gguf, a.name, p)


if __name__ == "__main__":
    main()
