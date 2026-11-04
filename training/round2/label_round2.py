"""Round-2 label expansion with Muse Spark Open (Meta, open weights) on Baseten, k-sample voting teacher.
Call/parse logic copied from training/spark_teacher/label_spark.py (same model id, reasoning_effort low, temperature 1.0,
same system+user content via pg_train.prompts.chat_messages). Differences: k=5 by default, one flat call pool with
exponential backoff + jitter on 429, per-type caps with a balanced interleaved order (a partial run stays balanced, weak
types are scheduled slightly earlier), a hard wall-clock stop, and the raw vote counts are stored so the soft target
(+alpha Laplace smoothing) is built later in build_round2.py. Resumable (appends JSONL, skips done ids).
Source pool: training/data_scale/out/pool.jsonl (already deduped vs ALL eval items; re-checked here). Never labels eval."""
import argparse, json, os, sys, time, datetime, threading, re, collections, random
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import urllib.request, urllib.error
HERE = Path(__file__).resolve().parent; ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "training")); sys.path.insert(0, str(ROOT / "training/local_teacher"))
from pg_train import prompts
import dedupe as D
URL = "https://inference.baseten.co/v1/chat/completions"
MODEL = "meta-models/muse-spark-open-1026"
PIN, POUT = 1.25e-6, 4.25e-6
CAPS = {"nudgeNow": 900, "timing": 500, "contactPick": 450, "answerability": 450, "notificationTriage": 370, "rememberOrNot": 295,
        "memoryConflict": 173, "confirmBeforeAct": 247, "sensitivity": 199, "route": 500, "toolChoice": 450, "eventPick": 249}
WEAK = {"nudgeNow": 0.6, "timing": 0.8, "contactPick": 0.8, "answerability": 0.8, "notificationTriage": 0.8, "rememberOrNot": 0.8, "memoryConflict": 0.9}
ap = argparse.ArgumentParser()
ap.add_argument("--input", default=str(ROOT / "training/data_scale/out/pool.jsonl"))
ap.add_argument("--out", default=str(HERE / "out/labels_round2.jsonl"))
ap.add_argument("--k", type=int, default=5); ap.add_argument("--workers", type=int, default=24)
ap.add_argument("--k0", type=int, default=3, help="adaptive: draw k0 first; if unanimous stop, else draw up to k (0 = always k)")
ap.add_argument("--rpm", type=float, default=94.0, help="Baseten hackathon limit is 100 requests/min (X-Ratelimit-Limit-Requests)")
ap.add_argument("--limit", type=int, default=0); ap.add_argument("--budget", type=float, default=71.0, help="cumulative spend.jsonl cap ($11.06 prior + $60)")
ap.add_argument("--priority", default="", help="comma list of types processed first (interleaved), rest round-robin after")
ap.add_argument("--stop-at", default="07:20", help="hard stop, America/New_York HH:MM")
a = ap.parse_args()
if "test" in Path(a.input).name: sys.exit("refusing: never label the frozen test split")
from zoneinfo import ZoneInfo
hh, mm = map(int, a.stop_at.split(":"))
STOP = datetime.datetime.now(ZoneInfo("America/New_York")).replace(hour=hh, minute=mm, second=0, microsecond=0).timestamp()
print(f"hard stop at {a.stop_at} America/New_York, {STOP - time.time():.0f}s from now", flush=True)

rows = [json.loads(l) for l in open(a.input) if l.strip()]
# never touch contexts already labeled for training (Nov 1 Glimmer/Spark rows) or the cal180 items
seen = set()
for f in ["training/local_teacher/out/distill_train.jsonl", "training/local_teacher/out/train_labels.jsonl",
          "training/spark_teacher/out/train_labels_spark.jsonl", "training/spark_teacher/out/extra_labels_spark.jsonl",
          "training/spark_teacher/out/cal_labels_spark.jsonl", "eval/gold/gold_all.jsonl"]:
    p = ROOT / f
    if p.exists(): seen |= {json.loads(l)["context"] for l in open(p) if l.strip()}
rows = [r for r in rows if r["context"] not in seen and r["type"] in CAPS]
by = collections.defaultdict(list)
for r in rows: by[r["type"]].append(r)
order = []
for t, rs in by.items():
    random.Random(0).shuffle(rs); rs = rs[: CAPS[t]]
    order += [((j + 1) / CAPS[t] * WEAK.get(t, 1.0), t, r) for j, r in enumerate(rs)]
PRI = [t for t in a.priority.split(",") if t]
order.sort(key=lambda x: (0 if x[1] in PRI else 1, x[0], x[1])); sel = [r for _, _, r in order]
if a.limit: sel = sel[: a.limit]
sel, dropped = D.check(sel, D.eval_items()); print(f"selected {len(sel)}; re-dedupe vs eval dropped {len(dropped)}", flush=True)
done = {json.loads(l)["id"] for l in open(a.out)} if os.path.exists(a.out) else set()
todo = [r for r in sel if r["id"] not in done]; print(f"{len(done)} done, {len(todo)} to go; per-type todo {dict(collections.Counter(r['type'] for r in todo))}", flush=True)
KEY = os.environ["BASETEN_API_KEY"]; lock = threading.Lock(); tot = collections.Counter()
spend_log = ROOT / "training/spark_teacher/spend.jsonl"
prev = sum(json.loads(l)["usd"] for l in open(spend_log)) if spend_log.exists() else 0.0


_rl = threading.Lock(); _next = [time.time()]


def throttle():
    with _rl:
        t = max(time.time(), _next[0]); _next[0] = t + 60.0 / a.rpm
    d = t - time.time()
    if d > 0: time.sleep(d)


def call(msgs):
    body = {"model": MODEL, "messages": msgs, "max_tokens": 768, "temperature": 1.0, "top_p": 1.0, "reasoning_effort": "low"}
    err = None
    for att in range(10):
        if time.time() > STOP: break
        throttle()
        try:
            rq = urllib.request.Request(URL, data=json.dumps(body).encode(), headers={"Content-Type": "application/json", "Authorization": "Api-Key " + KEY})
            return json.loads(urllib.request.urlopen(rq, timeout=120).read())
        except Exception as e:
            err = e; is429 = "429" in str(e)
            with lock: tot["e429" if is429 else "err"] += 1
            time.sleep(min(30, (2 if is429 else 1.5) * 2 ** att) * (0.5 + random.random()))
    return {"_error": str(err)[:200]}


def parse(text, L):
    t = (text or "").strip(); m = re.match(r"^\(?([A-H])\b", t)
    if m and m.group(1) in L: return m.group(1)
    xs = [x for x in re.findall(r"\b([A-H])\b", t) if x in L]
    return xs[-1] if xs else None


CALLS = ThreadPoolExecutor(a.workers * a.k)


def one(r):
    if time.time() > STOP: return None
    s = prompts.get_set(r["type"], r.get("candidates")); L = prompts.letters(s); msgs = prompts.chat_messages(s, r["context"])
    t0 = time.time(); k0 = a.k0 if a.k0 else a.k
    res = list(CALLS.map(lambda _: call(msgs), range(k0)))
    first = [parse(x["choices"][0]["message"].get("content"), L) if "_error" not in x else None for x in res]
    if not (len(set(first)) == 1 and first[0] is not None) and k0 < a.k and time.time() < STOP:
        res += list(CALLS.map(lambda _: call(msgs), range(a.k - k0)))
    votes, tin, tout = [], 0, 0
    for x in res:
        if "_error" in x: votes.append(None); continue
        u = x.get("usage", {}) or {}; tin += u.get("prompt_tokens", 0); tout += u.get("completion_tokens", 0)
        votes.append(parse(x["choices"][0]["message"].get("content"), L))
    got = [v for v in votes if v]; errs = sum(1 for x in res if "_error" in x)
    counts = {l: got.count(l) for l in L}
    probs = {l: counts[l] / len(got) for l in L} if got else None
    letter = max(L, key=lambda l: counts[l]) if got else None
    ids = [o["id"] for o in s["options"]]
    lab = {"teacher": "muse-spark-open-816b-a42b-nvfp4@baseten", "mode": f"sample-adaptive-k{k0}to{a.k}-t1.0-effort-low", "letter": letter, "probs": probs,
           "counts": counts, "k": len(res), "k_max": a.k, "k0": k0, "n_valid": len(got), "n_call_errors": errs,
           "top_share": (counts[letter] / len(res)) if letter else 0.0, "confidence": probs[letter] if probs else None,
           "letter_mass": len(got) / len(res), "votes": votes, "latency_ms": (time.time() - t0) * 1000, "tokens_in": tin, "tokens_out": tout}
    return {**r, "mode": "train", "option_ids": ids, "teacher_option": ids[L.index(letter)] if letter else None, "label": lab,
            "labeled_at": datetime.datetime.now().isoformat(timespec="seconds")}, tin, tout


import signal
def _term(*_): raise KeyboardInterrupt
signal.signal(signal.SIGTERM, _term)
t_start = time.time(); n = 0; stopped = "complete"
ex = ThreadPoolExecutor(a.workers)
futs = [ex.submit(one, r) for r in todo]
with open(a.out, "a") as f:
    try:
        for fu in as_completed(futs):
            out = fu.result()
            if out is None: stopped = "hard-stop"; continue
            rec, tin, tout = out
            with lock:
                if rec["label"]["n_call_errors"] == rec["label"]["k"]: tot["item_all_failed"] += 1; continue  # nothing came back; retry on resume
                f.write(json.dumps(rec) + "\n"); f.flush(); n += 1; tot["in"] += tin; tot["out"] += tout
                usd = tot["in"] * PIN + tot["out"] * POUT
                if n % 100 == 0:
                    el = time.time() - t_start
                    print(f"[{datetime.datetime.now():%H:%M:%S}] {n}/{len(todo)} {n/el:.2f} it/s est ${usd:.2f} 429s={tot['e429']} errs={tot['err']}", flush=True)
                if prev + usd > a.budget:
                    print("BUDGET STOP", flush=True); stopped = "budget"; break
            if time.time() > STOP: stopped = "hard-stop"; break
    except KeyboardInterrupt:
        stopped = "interrupted"
for fu in futs: fu.cancel()
usd = tot["in"] * PIN + tot["out"] * POUT
with open(spend_log, "a") as g:
    g.write(json.dumps({"at": datetime.datetime.now().isoformat(timespec="seconds"), "file": "training/round2/out/labels_round2.jsonl", "items": n, "k": f"adaptive {a.k0}->{a.k}",
                        "tokens_in": tot["in"], "tokens_out": tot["out"], "usd": round(usd, 4),
                        "price": "Baseten $1.25/$4.25 per 1M (no cache credit assumed)", "stopped": stopped,
                        "note": "round2 label expansion; in-flight calls at a hard stop are not counted (small)"}) + "\n")
print(f"finished {n} in {time.time()-t_start:.0f}s ({stopped}); est ${usd:.3f}; cumulative ${prev+usd:.2f}; 429s={tot['e429']} errs={tot['err']}", flush=True)
os._exit(0)
