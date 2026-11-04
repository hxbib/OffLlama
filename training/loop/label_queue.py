#!/usr/bin/env python3
"""Label the phone's exported escalation queue with a Meta teacher.

Input rows (from TelemetryLog.exportDistillationQueue):
  {"id","type","context","option_ids","student_probs","confidence","ts","source"}
Output rows: input + {"label": {teacher, letter, probs, confidence, letter_mass?, votes?}, "teacher_option",
             "student_option", "agreed", "labeled_at", "mode": "train", "candidates"?}
Teachers:
  glimmer  local llama-server serving Muse Glimmer 30B (letter logprobs; training/local_teacher/glimmer_teacher.py)
  spark    Muse Spark Open on Baseten, k-sample vote (training/spark_teacher/label_spark.py semantics; costs credit,
           requires PG_ALLOW_SPEND=1 and BASETEN_API_KEY)
  student  the shipping Reflex itself via llama-server (for selftest only; NEVER use as a real teacher)
--scrub masks names/emails/phones/addresses/cards like the app's PrivacyScrubber before anything leaves the box.
Refuses to label anything whose filename contains "test" (frozen split)."""
import argparse, json, os, re, sys, time, datetime, math, urllib.request, collections
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "training"), str(ROOT / "training/local_teacher")]
from pg_train import prompts

ap = argparse.ArgumentParser()
ap.add_argument("--input", required=True); ap.add_argument("--out", required=True)
ap.add_argument("--teacher", choices=["glimmer", "spark", "student"], required=True)
ap.add_argument("--url", default="http://127.0.0.1:8091"); ap.add_argument("--k", type=int, default=5)
ap.add_argument("--workers", type=int, default=8); ap.add_argument("--limit", type=int, default=0)
ap.add_argument("--scrub", action="store_true"); ap.add_argument("--budget", type=float, default=5.0)
a = ap.parse_args()
if "test" in Path(a.input).name.lower(): sys.exit("refusing: never label a frozen test split")

# --- privacy scrubber (mirror of core/Sources/PocketCore/Scrubber.swift; conservative superset) ---
SCRUB = [("EMAIL", re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")),
         ("CARD", re.compile(r"\b(?:\d[ -]?){13,19}\b")),
         ("PHONE", re.compile(r"\b(?:\+?1[ -.]?)?\(?\d{3}\)?[ -.]?\d{3}[ -.]?\d{4}\b")),
         ("ADDRESS", re.compile(r"\b\d{1,5}\s+(?:[A-Z][a-z]+\s){1,3}(?:St|Street|Ave|Avenue|Rd|Road|Blvd|Dr|Drive|Ln|Lane|Way|Ct|Pl)\b\.?")),
         ("PERSON", re.compile(r"\b(?:(?:text|tell|message|call|email|remind|with|for|to)\s+)([A-Z][a-z]+(?:\s[A-Z][a-z]+)?)\b"))]
def scrub(text):
    counters = collections.Counter(); mapping = {}
    for kind, rx in SCRUB:
        def rep(m):
            raw = m.group(1) if m.lastindex else m.group(0)
            if raw not in mapping:
                counters[kind] += 1; mapping[raw] = f"[{kind}_{counters[kind]}]"
            return m.group(0).replace(raw, mapping[raw])
        text = rx.sub(rep, text)
    return text, mapping

def rows_in(path):
    for l in open(path):
        if l.strip(): yield json.loads(l)
rows = list(rows_in(a.input))
if a.limit: rows = rows[: a.limit]
done = {r["id"] for r in rows_in(a.out)} if os.path.exists(a.out) else set()
todo = [r for r in rows if r["id"] not in done]
print(f"{len(done)} done, {len(todo)} to go, teacher={a.teacher}", flush=True)

def set_for(r):
    ids = r.get("option_ids") or []
    s = prompts.get_set(r["type"], r.get("candidates"))
    sids = [o["id"] for o in s["options"]]
    if ids and ids != sids:
        # dynamic sets (contactPick/eventPick): reconstruct candidates from the option ids the phone used
        if r["type"] in ("contactPick", "eventPick") and r.get("candidates") is None:
            cand = [i for i in ids if i != "ask"]; s = prompts.get_set(r["type"], cand); sids = [o["id"] for o in s["options"]]
        if ids != sids: raise ValueError(f"option ids mismatch for {r['id']}: phone {ids} vs prompts {sids}")
    return s

# --- teachers ---
def teacher_glimmer(s, ctx):
    import glimmer_teacher as G
    T = G.GlimmerLocalTeacher(a.url); return G.GlimmerLocalTeacher.label(T, s, ctx)

def teacher_student(s, ctx):
    # letter logprobs from any llama-server (selftest only: the shipping GGUF as a stand-in teacher). Same readout as
    # training/local_teacher/glimmer_teacher.py: n_probs over the next token, merge " A"/"A" variants, renormalise.
    from pg_train.teachers import _merge_letter_logprobs
    L = prompts.letters(s); prompt = prompts.llama3(s, ctx, "zeroShot")
    body = {"prompt": prompt, "n_predict": 1, "n_probs": 50, "temperature": 0, "cache_prompt": True, "post_sampling_probs": False}
    rq = urllib.request.Request(a.url.rstrip("/") + "/completion", data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    out = json.loads(urllib.request.urlopen(rq, timeout=120).read())
    top = out["completion_probabilities"][0]["top_logprobs"]
    raw = _merge_letter_logprobs([(t["token"], t["logprob"]) for t in top], L)
    if not raw: return None
    mass = sum(math.exp(v) for v in raw.values()); probs = {l: math.exp(raw[l]) / mass if l in raw else 0.0 for l in L}
    letter = max(probs, key=probs.get)
    return {"teacher": "student-standin@llama-server", "letter": letter, "probs": probs, "confidence": probs[letter], "letter_mass": mass, "latency_ms": None}

SPARK_URL = "https://inference.baseten.co/v1/chat/completions"; SPARK_MODEL = os.environ.get("BASETEN_MODEL", "meta-models/muse-spark-open-1026")
spend = collections.Counter()
def spark_call(msgs):
    body = {"model": SPARK_MODEL, "messages": msgs, "max_tokens": 768, "temperature": 1.0, "top_p": 1.0, "reasoning_effort": "low"}
    err = None
    for att in range(6):
        try:
            rq = urllib.request.Request(SPARK_URL, data=json.dumps(body).encode(), headers={"Content-Type": "application/json", "Authorization": "Bearer " + os.environ["BASETEN_API_KEY"]})
            return json.loads(urllib.request.urlopen(rq, timeout=180).read())
        except Exception as e: err = e; time.sleep((20 if "429" in str(e) else 3) * (att + 1))
    raise err
def parse_letter(text, L):
    t = (text or "").strip(); m = re.match(r"^\(?([A-H])\b", t)
    if m and m.group(1) in L: return m.group(1)
    xs = [x for x in re.findall(r"\b([A-H])\b", t) if x in L]; return xs[-1] if xs else None
def teacher_spark(s, ctx):
    if os.environ.get("PG_ALLOW_SPEND") != "1": raise SystemExit("spark teacher spends credit: set PG_ALLOW_SPEND=1")
    L = prompts.letters(s); msgs = prompts.chat_messages(s, ctx); t0 = time.time()
    with ThreadPoolExecutor(a.k) as ex: res = list(ex.map(lambda _: spark_call(msgs), range(a.k)))
    votes = []
    for x in res:
        u = x.get("usage", {}); spend["in"] += u.get("prompt_tokens", 0); spend["out"] += u.get("completion_tokens", 0)
        votes.append(parse_letter(x["choices"][0]["message"].get("content"), L))
    got = [v for v in votes if v]
    if not got: return None
    # Laplace-smoothed vote frequencies so the KL target is never one-hot
    probs = {l: (got.count(l) + 0.5) / (len(got) + 0.5 * len(L)) for l in L}; letter = max(probs, key=probs.get)
    usd = spend["in"] / 1e6 * 1.25 + spend["out"] / 1e6 * 4.25
    if usd > a.budget: raise SystemExit(f"budget {a.budget} USD exceeded ({usd:.2f})")
    return {"teacher": "muse-spark-open-816b-a42b-nvfp4@baseten", "mode": f"sample-k{a.k}-t1.0-effort-low-laplace", "letter": letter,
            "probs": probs, "confidence": max(got.count(l) for l in L) / len(got), "votes": votes, "latency_ms": (time.time() - t0) * 1000}

TEACH = {"glimmer": teacher_glimmer, "spark": teacher_spark, "student": teacher_student}[a.teacher]

def one(r):
    s = set_for(r); ctx = r["context"]; mapping = {}
    if a.scrub: ctx, mapping = scrub(ctx)
    lab = TEACH(s, ctx)
    if not lab: return None
    ids = [o["id"] for o in s["options"]]
    t_opt = ids[prompts.LETTERS.index(lab["letter"])]
    sp = r.get("student_probs") or {}
    s_opt = max(sp, key=sp.get) if sp else None
    return {**r, "mode": "train", "context_sent": ctx if a.scrub else None, "scrub_mapping_size": len(mapping),
            "option_ids": ids, "label": lab, "teacher_option": t_opt, "student_option": s_opt,
            "agreed": (s_opt == t_opt) if s_opt else None, "labeled_at": datetime.datetime.now().isoformat(timespec="seconds")}

n = 0; t0 = time.time()
with open(a.out, "a") as f, ThreadPoolExecutor(a.workers if a.teacher == "spark" else 1) as ex:
    for rec in ex.map(lambda r: (r, one(r)), todo):
        r, out = rec
        if out is None: print("skip", r["id"], flush=True); continue
        f.write(json.dumps(out) + "\n"); f.flush(); n += 1
        if n % 25 == 0: print(f"[{datetime.datetime.now():%H:%M:%S}] {len(done)+n} done, {n/(time.time()-t0)*3600:.0f}/h", flush=True)
agree = [x for x in rows_in(a.out) if x.get("agreed") is not None]
print(f"finished: {n} new; total {len(done)+n}; teacher agreed with student argmax on {sum(1 for x in agree if x['agreed'])}/{len(agree)} escalated rows", flush=True)
if a.teacher == "spark":
    usd = spend["in"] / 1e6 * 1.25 + spend["out"] / 1e6 * 4.25
    with open(ROOT / "training/spark_teacher/spend.jsonl", "a") as sl:
        sl.write(json.dumps({"at": datetime.datetime.now().isoformat(timespec="seconds"), "file": str(Path(a.out)), "items": n, "k": a.k,
                             "tokens_in": spend["in"], "tokens_out": spend["out"], "usd": round(usd, 4), "price": "Baseten $1.25/$4.25 per 1M (no cache credit assumed)"}) + "\n")
    print(f"spend this run: ${usd:.2f}")
