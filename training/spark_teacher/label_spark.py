"""Muse Spark Open (Meta, open weights, Muse Model License) teacher via Baseten Model APIs (OpenAI-compatible).
Baseten returns logprobs=null for this model (verified 2026-11-01 on chat + completions), so soft labels are the
empirical distribution of K sampled answers (temperature 1.0 = Meta's recommended setting, reasoning_effort low).
Same system+user content as the Glimmer labeler (pg_train.prompts.chat_messages). Resumable, appends JSONL, logs spend.
--mode train re-dedupes every row against ALL eval/**/*.jsonl (frozen test guard). --mode cal is for calibration-split
QC only (never used for training). The frozen test120 is never labeled by this script (hard refusal)."""
import argparse, json, os, sys, time, datetime, threading, re, collections
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import urllib.request, urllib.error
HERE = Path(__file__).resolve().parent; ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "training")); sys.path.insert(0, str(ROOT / "training/local_teacher"))
from pg_train import prompts
import dedupe as D
URL = "https://inference.baseten.co/v1/chat/completions"
MODEL = os.environ.get("BASETEN_MODEL", "meta-models/muse-spark-open-1026")  # hackathon deployment of Muse-Spark-Open-816B-A42B-NVFP4
PIN, POUT = 1.25e-6, 4.25e-6
ap = argparse.ArgumentParser()
ap.add_argument("--input", required=True); ap.add_argument("--out", required=True)
ap.add_argument("--mode", choices=["train", "cal"], required=True); ap.add_argument("--k", type=int, default=8)
ap.add_argument("--limit", type=int, default=0); ap.add_argument("--workers", type=int, default=16)
ap.add_argument("--budget", type=float, default=40.0, help="stop if cumulative est. spend (this file's spend log) exceeds")
a = ap.parse_args()
if "gold_test" in a.input or "test" in Path(a.input).name: sys.exit("refusing: never label the frozen test split")
rows = [json.loads(l) for l in open(a.input) if l.strip()]
if a.limit: rows = rows[: a.limit]
if a.mode == "train":
    rows, dropped = D.check(rows, D.eval_items()); print(f"re-dedupe vs eval: dropped {len(dropped)}", flush=True)
done = {json.loads(l)["id"] for l in open(a.out)} if os.path.exists(a.out) else set()
todo = [r for r in rows if r["id"] not in done]; print(f"{len(done)} done, {len(todo)} to go", flush=True)
KEY = os.environ["BASETEN_API_KEY"]; lock = threading.Lock(); tot = collections.Counter()
spend_log = ROOT / "training/spark_teacher/spend.jsonl"
prev = sum(json.loads(l)["usd"] for l in open(spend_log)) if spend_log.exists() else 0.0  # NOTE: rows lost to a crash are not counted; see SPARK_TEACHER.md

def call(msgs):
    body = {"model": MODEL, "messages": msgs, "max_tokens": 768, "temperature": 1.0, "top_p": 1.0, "reasoning_effort": "low"}
    for att in range(8):
        try:
            rq = urllib.request.Request(URL, data=json.dumps(body).encode(), headers={"Content-Type": "application/json", "Authorization": "Api-Key " + KEY})
            return json.loads(urllib.request.urlopen(rq, timeout=180).read())
        except Exception as e:
            err = e; time.sleep((20 if '429' in str(e) else 3) * (att + 1))
    raise err

def parse(text, L):
    t = (text or "").strip(); m = re.match(r"^\(?([A-H])\b", t)
    if m and m.group(1) in L: return m.group(1)
    xs = [x for x in re.findall(r"\b([A-H])\b", t) if x in L]
    return xs[-1] if xs else None

def one(r):
    s = prompts.get_set(r["type"], r.get("candidates")); L = prompts.letters(s); msgs = prompts.chat_messages(s, r["context"])
    votes, tin, tout, t0 = [], 0, 0, time.time()
    with ThreadPoolExecutor(a.k) as ex:
        res = list(ex.map(lambda _: call(msgs), range(a.k)))
    for x in res:
        u = x.get("usage", {}); tin += u.get("prompt_tokens", 0); tout += u.get("completion_tokens", 0)
        votes.append(parse(x["choices"][0]["message"].get("content"), L))
    got = [v for v in votes if v]
    probs = {l: got.count(l) / len(got) for l in L} if got else None
    letter = max(probs, key=probs.get) if probs else None
    ids = [o["id"] for o in s["options"]]
    lab = {"teacher": "muse-spark-open-816b-a42b-nvfp4@baseten", "mode": f"sample-k{a.k}-t1.0-effort-low", "letter": letter, "probs": probs,
           "confidence": probs[letter] if probs else None, "letter_mass": len(got) / a.k, "votes": votes,
           "latency_ms": (time.time() - t0) * 1000, "tokens_in": tin, "tokens_out": tout}
    rec = {**r, "mode": a.mode, "option_ids": ids, "teacher_option": ids[L.index(letter)] if letter else None, "label": lab,
           "labeled_at": datetime.datetime.now().isoformat(timespec="seconds")}
    return rec, tin, tout

t_start = time.time(); n = 0
with open(a.out, "a") as f, ThreadPoolExecutor(max(1, a.workers // 1)) as ex:
    for rec, tin, tout in ex.map(one, todo):
        with lock:
            f.write(json.dumps(rec) + "\n"); f.flush(); n += 1; tot["in"] += tin; tot["out"] += tout
            usd = tot["in"] * PIN + tot["out"] * POUT
            if n % 50 == 0: print(f"[{datetime.datetime.now():%H:%M:%S}] {n}/{len(todo)} est ${usd:.2f} (in {tot['in']} out {tot['out']})", flush=True)
            if prev + usd > a.budget: print("BUDGET STOP", flush=True); os._exit(3)
usd = tot["in"] * PIN + tot["out"] * POUT
with open(spend_log, "a") as g:
    g.write(json.dumps({"at": datetime.datetime.now().isoformat(timespec="seconds"), "file": a.out, "items": n, "k": a.k,
                        "tokens_in": tot["in"], "tokens_out": tot["out"], "usd": round(usd, 4), "price": "Baseten $1.25/$4.25 per 1M (no cache credit assumed)"}) + "\n")
print(f"finished {n} in {time.time()-t_start:.0f}s; est ${usd:.3f}; cumulative ${prev+usd:.2f}", flush=True)
