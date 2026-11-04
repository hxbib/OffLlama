"""Spark Open round-3 labeler with durable per-call reservations.

Replacement for the budget handling in training/round2/label_round2.py.
Teacher: meta-models/muse-spark-open-1026 on the existing Baseten endpoint,
reasoning_effort=low, temperature=1.0, top_p=1.0, max_tokens enforced.
Each context gets a FIXED k=5 draws. No early stop, no vote imputation.

Money rules (fail closed):
- Every dispatch first inserts a RESERVED row in SQLite (WAL, fsync) priced at
  worst case: prompt_token_worst * PIN + max_tokens * POUT.
- A settled call is charged from the provider's raw usage (prompt + completion,
  completion includes reasoning tokens). Missing usage is never assumed zero.
- Timeout, dropped connection, missing usage, or a crash between response and
  settlement leaves the row UNKNOWN and its worst-case reserve charged forever.
- Explicit HTTP responses (including 429/5xx) settle at 0 only because the
  provider returned no billable usage; each retry is a new reservation.
- Committed = settled actuals + outstanding/UNKNOWN reserves. Admission is
  denied when committed + next reserve would exceed the cap.

One writer only: an exclusive lock file guards the state directory.
Per-draw records are appended to draws.jsonl with fsync at settlement time.
"""
import argparse, contextlib, hashlib, json, os, re, sqlite3, sys, threading, time, urllib.error, urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "training"))
from pg_train import prompts  # noqa: E402

URL = "https://inference.baseten.co/v1/chat/completions"
MODEL = "meta-models/muse-spark-open-1026"
TEACHER = "muse-spark-open-1026@baseten"
PIN, POUT = 1.25e-6, 4.25e-6
K = 5
CURRENT_RPM = 94.0


def parse_letter(text, letters):
    t = (text or "").strip()
    m = re.match(r"^\(?([A-H])\b", t)
    if m and m.group(1) in letters:
        return m.group(1)
    xs = [x for x in re.findall(r"\b([A-H])\b", t) if x in letters]
    return xs[-1] if xs else None


def prompt_token_worst(messages):
    # Upper bound: one token covers at least one character of ordinary text,
    # plus per-message framing overhead. Assumed bound, not a tokenizer count.
    return sum(len(m.get("content") or "") for m in messages) + 16 * len(messages) + 8


def reserve_usd(prompt_worst, max_tokens):
    return prompt_worst * PIN + max_tokens * POUT


class Throttle:
    """Global request-start spacing plus Retry-After floor. 94 RPM default."""

    def __init__(self, rpm=94.0, clock=time.monotonic, sleep=time.sleep):
        self.interval = 60.0 / rpm if rpm and rpm > 0 else 0.0
        self.clock, self.sleep = clock, sleep
        self.lock = threading.Lock()
        self.next_at = 0.0

    def wait(self):
        with self.lock:
            now = self.clock()
            at = max(now, self.next_at)
            self.next_at = at + self.interval
        delay = at - self.clock()
        if delay > 0:
            self.sleep(delay)

    def penalize(self, seconds):
        with self.lock:
            self.next_at = max(self.next_at, self.clock() + max(0.0, seconds))


class Store:
    def __init__(self, state_dir, cap_usd):
        self.dir = Path(state_dir)
        self.dir.mkdir(parents=True, exist_ok=True)
        self.cap = float(cap_usd)
        self.lock = threading.Lock()
        self.db = sqlite3.connect(str(self.dir / "state.sqlite3"), check_same_thread=False)
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA synchronous=FULL")
        self.db.executescript(
            """
            CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);
            CREATE TABLE IF NOT EXISTS calls(
              call_key TEXT PRIMARY KEY, context_id TEXT, draw_index INTEGER, attempt INTEGER,
              state TEXT, reserved_usd REAL, actual_usd REAL, prompt_worst INTEGER, max_tokens INTEGER,
              usage_json TEXT, raw_content TEXT, parsed_letter TEXT, error TEXT,
              http_status INTEGER, created_at REAL, settled_at REAL);
            CREATE INDEX IF NOT EXISTS idx_calls_ctx ON calls(context_id, draw_index);
            """
        )
        row = self.db.execute("SELECT value FROM meta WHERE key='cap_usd'").fetchone()
        if row is None:
            self.db.execute("INSERT INTO meta VALUES('cap_usd',?)", (repr(self.cap),))
        elif abs(float(row[0]) - self.cap) > 1e-12:
            raise SystemExit(f"cap mismatch: state has ${row[0]}, requested ${self.cap}")
        self.db.commit()
        self.recover()

    def recover(self):
        # A RESERVED row at startup means we crashed after reserving (possibly
        # after the provider responded). The charge is unknowable: fail closed.
        with self.lock:
            cur = self.db.execute("UPDATE calls SET state='UNKNOWN', error='recovered-reserved-at-restart' WHERE state='RESERVED'")
            self.db.commit()
            return cur.rowcount

    def committed(self):
        with self.lock:
            row = self.db.execute(
                "SELECT COALESCE(SUM(CASE WHEN state='SETTLED' THEN actual_usd "
                "WHEN state IN ('RESERVED','UNKNOWN') THEN reserved_usd ELSE 0 END),0) FROM calls"
            ).fetchone()
            return float(row[0])

    def totals(self):
        with self.lock:
            out = {}
            for state, n, actual, reserved in self.db.execute(
                "SELECT state, COUNT(*), COALESCE(SUM(actual_usd),0), COALESCE(SUM(reserved_usd),0) FROM calls GROUP BY state"
            ):
                out[state] = {"calls": n, "actual_usd": actual, "reserved_usd": reserved}
            return out

    def try_reserve(self, context_id, draw_index, attempt, prompt_worst, max_tokens):
        reserve = reserve_usd(prompt_worst, max_tokens)
        key = f"{context_id}#{draw_index}#{attempt}"
        with self.lock:
            committed = float(self.db.execute(
                "SELECT COALESCE(SUM(CASE WHEN state='SETTLED' THEN actual_usd "
                "WHEN state IN ('RESERVED','UNKNOWN') THEN reserved_usd ELSE 0 END),0) FROM calls").fetchone()[0])
            if committed + reserve > self.cap + 1e-12:
                return None
            try:
                self.db.execute(
                    "INSERT INTO calls(call_key,context_id,draw_index,attempt,state,reserved_usd,prompt_worst,max_tokens,created_at) "
                    "VALUES(?,?,?,?, 'RESERVED', ?,?,?,?)",
                    (key, context_id, draw_index, attempt, reserve, prompt_worst, max_tokens, time.time()))
            except sqlite3.IntegrityError:
                return "duplicate"
            self.db.commit()
            return key

    def settle(self, key, state, actual_usd=None, usage=None, raw_content=None, parsed=None, error=None, http_status=None):
        with self.lock:
            self.db.execute(
                "UPDATE calls SET state=?, actual_usd=?, usage_json=?, raw_content=?, parsed_letter=?, error=?, http_status=?, settled_at=? WHERE call_key=?",
                (state, actual_usd, json.dumps(usage) if usage is not None else None, raw_content, parsed,
                 (error or "")[:500] or None, http_status, time.time(), key))
            self.db.commit()

    def attempts(self, context_id, draw_index):
        with self.lock:
            return self.db.execute("SELECT state, parsed_letter, raw_content, usage_json, error FROM calls WHERE context_id=? AND draw_index=? ORDER BY attempt",
                                   (context_id, draw_index)).fetchall()

    def draw_terminal(self, context_id, draw_index, max_attempts):
        rows = self.attempts(context_id, draw_index)
        if any(r[0] == "SETTLED" for r in rows):
            return True
        return len(rows) >= max_attempts and all(r[0] != "RESERVED" for r in rows)

    def close(self):
        with self.lock:
            self.db.close()


def real_transport(key, throttle, timeout=120):
    def transport(messages, max_tokens):
        body = {"model": MODEL, "messages": messages, "max_tokens": max_tokens,
                "temperature": 1.0, "top_p": 1.0, "reasoning_effort": "low"}
        throttle.wait()
        req = urllib.request.Request(URL, data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json", "Authorization": "Api-Key " + key})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return {"kind": "ok", "http_status": resp.status, "body": json.loads(resp.read())}
        except urllib.error.HTTPError as e:
            retry_after = None
            try:
                ra = e.headers.get("Retry-After") if e.headers else None
                retry_after = float(ra) if ra else None
            except (TypeError, ValueError):
                retry_after = None
            if retry_after:
                throttle.penalize(retry_after)
            return {"kind": "http_error", "http_status": e.code, "retry_after": retry_after, "error": f"HTTP {e.code}"}
        except Exception as e:  # timeout / dropped connection: provider may have billed
            return {"kind": "unknown", "error": f"{type(e).__name__}: {e}"[:300]}

    return transport


def run_draw(store, transport, row, draw_index, max_tokens, max_attempts, backoff_base=1.0, sleep=time.sleep):
    s = prompts.get_set(row["type"], row.get("candidates"))
    letters = prompts.letters(s)
    messages = prompts.chat_messages(s, row["context"])
    worst = prompt_token_worst(messages)
    for attempt in range(1, max_attempts + 1):
        existing = store.attempts(row["id"], draw_index)
        if any(r[0] == "SETTLED" for r in existing):
            return "settled"
        if len(existing) >= attempt:
            # This attempt was already recorded by an earlier process.
            if attempt == max_attempts:
                return existing[-1][0].lower()
            continue
        key = store.try_reserve(row["id"], draw_index, attempt, worst, max_tokens)
        if key is None:
            return "budget_denied"
        if key == "duplicate":
            continue
        result = transport(messages, max_tokens)
        kind = result.get("kind")
        if kind == "ok":
            body = result.get("body") or {}
            usage = body.get("usage")
            if not usage or usage.get("prompt_tokens") is None or usage.get("completion_tokens") is None:
                store.settle(key, "UNKNOWN", usage=usage, error="missing-usage-fails-closed", http_status=result.get("http_status"))
                return "unknown"
            content = None
            logprobs = None
            try:
                choice = (body.get("choices") or [{}])[0]
                content = (choice.get("message") or {}).get("content")
                logprobs = choice.get("logprobs")
            except Exception:
                content = None
            parsed = parse_letter(content, letters)
            actual = usage["prompt_tokens"] * PIN + usage["completion_tokens"] * POUT
            store.settle(key, "SETTLED", actual_usd=actual, usage=usage, raw_content=content, parsed=parsed,
                         http_status=result.get("http_status"))
            rec = {"context_id": row["id"], "draw_index": draw_index, "attempt": attempt, "state": "SETTLED",
                   "parsed_letter": parsed, "raw_content": content, "logprobs": logprobs, "usage": usage,
                   "actual_usd": actual, "model": MODEL}
            append_draw(store, rec)
            return "settled"
        if kind == "http_error":
            store.settle(key, "HTTP_ERROR", actual_usd=0.0, error=result.get("error"), http_status=result.get("http_status"))
            if attempt < max_attempts:
                delay = result.get("retry_after") or min(30.0, backoff_base * (2 ** (attempt - 1)))
                sleep(delay)
                continue
            return "http_error"
        store.settle(key, "UNKNOWN", error=result.get("error"))
        if attempt < max_attempts:
            sleep(min(30.0, backoff_base * (2 ** (attempt - 1))))
            continue
        return "unknown"
    return "exhausted"


def append_draw(store, rec):
    path = store.dir / "draws.jsonl"
    with store.lock:
        with open(path, "a") as f:
            f.write(json.dumps(rec) + "\n")
            f.flush()
            os.fsync(f.fileno())


def export_contexts(store, rows, max_attempts):
    out = []
    for row in rows:
        draws = []
        for d in range(K):
            atts = store.attempts(row["id"], d)
            settled = [a for a in atts if a[0] == "SETTLED"]
            chosen = settled[-1] if settled else None
            draws.append({
                "draw_index": d,
                "state": "SETTLED" if chosen else (atts[-1][0] if atts else "PENDING"),
                "attempts": len(atts),
                "parsed_letter": chosen[1] if chosen else None,
                "raw_content": chosen[2] if chosen else None,
                "usage": json.loads(chosen[3]) if chosen and chosen[3] else None,
                "error": atts[-1][4] if atts and not chosen else None,
            })
        s = prompts.get_set(row["type"], row.get("candidates"))
        letters = prompts.letters(s)
        valid = [d["parsed_letter"] for d in draws if d["parsed_letter"]]
        counts = {l: valid.count(l) for l in letters}
        derived = None
        if valid:
            top = max(letters, key=lambda l: counts[l])
            derived = {"letter": top, "vote_counts": counts, "n_valid": len(valid),
                       "vote_fraction": {l: counts[l] / len(valid) for l in letters},
                       "note": "empirical vote fraction from fixed k=5 sampling; not teacher log-probabilities"}
        out.append({**row, "k_fixed": K, "draws": draws, "derived": derived,
                    "n_settled_draws": sum(1 for d in draws if d["state"] == "SETTLED")})
    path = store.dir / "contexts.jsonl"
    tmp = path.with_suffix(".jsonl.tmp")
    with open(tmp, "w") as f:
        for r in out:
            f.write(json.dumps(r) + "\n")
        f.flush()
        os.fsync(f.fileno())
    tmp.replace(path)
    return out


def write_status(store, status_path, phase, rows_total, extra=None):
    totals = store.totals()
    settled = totals.get("SETTLED", {})
    unknown = totals.get("UNKNOWN", {})
    http_err = totals.get("HTTP_ERROR", {})
    billed = settled.get("actual_usd", 0.0)
    unknown_reserved = unknown.get("reserved_usd", 0.0)
    payload = {
        "phase": phase, "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "model": MODEL, "endpoint": URL, "teacher_sampling": {"temperature": 1.0, "reasoning_effort": "low", "top_p": 1.0},
        "cap_usd": store.cap, "billed_usd": round(billed, 6), "unknown_reserved_usd": round(unknown_reserved, 6),
        "committed_usd": round(store.committed(), 6),
        "calls": {k: v["calls"] for k, v in totals.items()},
        "rows_total": rows_total,
        "limits": {"rpm_throttle": f"{CURRENT_RPM:g} enforced; provider limit 100 RPM measured via x-ratelimit-limit-requests",
                   "prices_usd_per_1m": {"input": 1.25, "output": 4.25, "source": "training/config/pricing.json verified 2026-10-31; not re-verified live"},
                   "gpu": "hosted Baseten endpoint; GPU not controllable by caller"},
    }
    if extra:
        payload.update(extra)
    status_path = Path(status_path)
    status_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = status_path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(payload, indent=1))
    tmp.replace(status_path)
    return payload


@contextlib.contextmanager
def single_writer(state_dir):
    path = Path(state_dir) / "writer.lock"
    path.parent.mkdir(parents=True, exist_ok=True)
    import fcntl
    fh = open(path, "w")
    try:
        fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise SystemExit("another spark_label writer holds this state dir")
    fh.write(str(os.getpid()))
    fh.flush()
    try:
        yield
    finally:
        fcntl.flock(fh, fcntl.LOCK_UN)
        fh.close()


def load_rows(input_path, manifest_path=None):
    p = Path(input_path)
    if "test" in p.name.lower():
        raise SystemExit("refusing: never label a test split")
    data = p.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    rows = [json.loads(l) for l in data.decode().splitlines() if l.strip()]
    if manifest_path:
        man = json.loads(Path(manifest_path).read_text())
        entry = man.get("files", {}).get(p.name)
        if entry and entry.get("sha256") != digest:
            raise SystemExit(f"input hash mismatch for {p.name}: {digest} != manifest")
    seen = {}
    for r in rows:
        h = hashlib.sha256((r.get("context") or "").encode()).hexdigest()
        if r["id"] in seen and seen[r["id"]] != h:
            raise SystemExit(f"duplicate id with different context: {r['id']}")
        seen[r["id"]] = h
    return rows, digest


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--manifest", default="")
    ap.add_argument("--state-dir", required=True)
    ap.add_argument("--status", required=True)
    ap.add_argument("--cap-usd", type=float, default=25.0)
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--max-tokens", type=int, default=768)
    ap.add_argument("--max-attempts", type=int, default=3)
    ap.add_argument("--rpm", type=float, default=94.0)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--per-type-limit", type=int, default=0, help="balanced subset: at most N per type, file order")
    a = ap.parse_args(argv)
    global CURRENT_RPM
    CURRENT_RPM = a.rpm
    rows, digest = load_rows(a.input, a.manifest or None)
    if a.per_type_limit:
        counts, picked = {}, []
        for r in rows:
            if counts.get(r["type"], 0) < a.per_type_limit:
                picked.append(r)
                counts[r["type"]] = counts.get(r["type"], 0) + 1
        rows = picked
    if a.limit:
        rows = rows[: a.limit]
    state_dir = Path(a.state_dir)
    with single_writer(state_dir):
        store = Store(state_dir, a.cap_usd)
        write_status(store, a.status, "starting", len(rows), {"input": a.input, "input_sha256": digest})
        key = os.environ.get("BASETEN_API_KEY")
        if not key:
            raise SystemExit("BASETEN_API_KEY missing (source the env file; never pass keys as flags)")
        throttle = Throttle(a.rpm)
        transport = real_transport(key, throttle)
        tasks = [(r, d) for r in rows for d in range(K) if not store.draw_terminal(r["id"], d, a.max_attempts)]
        print(f"{len(rows)} contexts, {len(tasks)} draw tasks pending, committed ${store.committed():.4f} / ${a.cap_usd}", flush=True)
        denied = [0]

        def work(task):
            r, d = task
            res = run_draw(store, transport, r, d, a.max_tokens, a.max_attempts)
            if res == "budget_denied":
                denied[0] += 1
            return res

        # Bounded in-flight: fixed pool size; tasks are fed through the pool
        # queue, never materialized as all-at-once HTTP requests beyond it.
        with ThreadPoolExecutor(max_workers=max(1, a.workers)) as ex:
            for i, _ in enumerate(ex.map(work, tasks)):
                if i % 500 == 0:
                    totals = store.totals()
                    settled_calls = totals.get("SETTLED", {}).get("calls", 0)
                    write_status(store, a.status, "running", len(rows),
                                 {"input_sha256": digest, "settled_draws": settled_calls, "denied": denied[0]})
                    print(f"progress tasks={i}/{len(tasks)} committed=${store.committed():.4f}", flush=True)
        contexts = export_contexts(store, rows, a.max_attempts)
        done = sum(1 for c in contexts if c["n_settled_draws"] == K)
        valid = sum((c["derived"] or {}).get("n_valid", 0) for c in contexts)
        settled_draws = sum(c["n_settled_draws"] for c in contexts)
        write_status(store, a.status, "complete" if done == len(rows) else "partial", len(rows),
                     {"input_sha256": digest, "contexts_complete": done,
                      "parse_rate": (valid / settled_draws) if settled_draws else None, "denied": denied[0]})
        print(f"done: {done}/{len(rows)} contexts complete; committed ${store.committed():.4f}", flush=True)
        store.close()


if __name__ == "__main__":
    main()
