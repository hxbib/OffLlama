"""Durable spend ledger, throttling, and transport for spark_phone_*.

Money rules (fail closed), shared $54.99 Baseten cap for generation+labeling:
- Every dispatch first inserts a RESERVED row in SQLite (WAL, synchronous
  FULL) priced at worst case: full prompt bound * PIN + max_tokens * POUT.
  No cached-input discount is ever assumed.
- A settled call is charged from the provider's raw usage. Missing usage is
  never assumed zero: the call becomes UNKNOWN and keeps its reserve.
- Timeout, dropped connection, or a crash between response and settlement
  leaves the row UNKNOWN and its worst-case reserve charged forever.
- An explicit HTTP error response settles at $0 only because the provider
  returned no billable usage; every retry is a new reservation and counts
  toward the cap history.
- Committed = settled actuals + RESERVED/UNKNOWN reserves. Admission is
  denied when committed + next reserve would exceed the cap.
- One writer only: an exclusive flock guards the state directory.
- Starts are throttled to 25 RPM (the existing matched worker owns 70 RPM of
  the measured 100 RPM workspace limit; 2M TPM workspace). A rolling token
  budget additionally caps our own estimated tokens per minute.
"""
import contextlib
import hashlib
import json
import os
import re
import sqlite3
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

import spark_phone_common as C

MAX_RPM = 25.0
MAX_INFLIGHT = 4
TOKEN_BUDGET_PER_MIN = 400_000  # our conservative slice of the 2M TPM workspace


class Throttle:
    """Request-start spacing (RPM) + rolling token budget + Retry-After floor."""

    def __init__(self, rpm=MAX_RPM, token_budget=TOKEN_BUDGET_PER_MIN,
                 clock=time.monotonic, sleep=time.sleep):
        self.interval = 60.0 / rpm if rpm and rpm > 0 else 0.0
        self.token_budget = token_budget
        self.clock, self.sleep = clock, sleep
        self.lock = threading.Lock()
        self.next_at = 0.0
        self.token_log = []  # (monotonic_ts, est_tokens)

    def wait(self, est_tokens=0):
        appended = False
        while True:
            with self.lock:
                now = self.clock()
                self.token_log = [x for x in self.token_log if now - x[0] < 60.0]
                used = sum(x[1] for x in self.token_log)
                token_wait = 0.0
                if est_tokens and used + est_tokens > self.token_budget and self.token_log:
                    token_wait = 60.0 - (now - self.token_log[0][0])
                at = max(now, self.next_at)
                if token_wait > 0:
                    at = max(at, now + token_wait)
                self.next_at = at + self.interval
                if est_tokens and not appended:
                    self.token_log.append((at, est_tokens))
                    appended = True
            delay = at - self.clock()
            if delay <= 0:
                return
            self.sleep(min(delay, 5.0))
            if delay <= 5.0:
                return

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
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);
            CREATE TABLE IF NOT EXISTS calls(
              call_key TEXT PRIMARY KEY, kind TEXT, batch_id TEXT, attempt INTEGER,
              state TEXT, reserved_usd REAL, actual_usd REAL, prompt_worst INTEGER,
              max_tokens INTEGER, usage_json TEXT, error TEXT, http_status INTEGER,
              created_at REAL, settled_at REAL);
            CREATE INDEX IF NOT EXISTS idx_calls_batch ON calls(batch_id);
        """)
        row = self.db.execute("SELECT value FROM meta WHERE key='cap_usd'").fetchone()
        if row is None:
            self.db.execute("INSERT INTO meta VALUES('cap_usd',?)", (repr(self.cap),))
        elif abs(float(row[0]) - self.cap) > 1e-12:
            raise SystemExit(f"cap mismatch: state has ${row[0]}, requested ${self.cap}")
        self.db.commit()
        self.recover()

    def recover(self):
        with self.lock:
            cur = self.db.execute(
                "UPDATE calls SET state='UNKNOWN', error='recovered-reserved-at-restart' "
                "WHERE state='RESERVED'")
            self.db.commit()
            return cur.rowcount

    def committed(self):
        with self.lock:
            return float(self.db.execute(
                "SELECT COALESCE(SUM(CASE WHEN state='SETTLED' THEN actual_usd "
                "WHEN state IN ('RESERVED','UNKNOWN') THEN reserved_usd ELSE 0 END),0) "
                "FROM calls").fetchone()[0])

    def totals(self):
        with self.lock:
            out = {}
            for state, n, actual, reserved in self.db.execute(
                    "SELECT state, COUNT(*), COALESCE(SUM(actual_usd),0), "
                    "COALESCE(SUM(reserved_usd),0) FROM calls GROUP BY state"):
                out[state] = {"calls": n, "actual_usd": actual, "reserved_usd": reserved}
            return out

    def attempts(self, batch_id):
        with self.lock:
            return self.db.execute(
                "SELECT attempt, state, error FROM calls WHERE batch_id=? ORDER BY attempt",
                (batch_id,)).fetchall()

    def try_reserve(self, kind, batch_id, attempt, prompt_worst, max_tokens):
        reserve = C.reserve_usd(prompt_worst, max_tokens)
        key = f"{batch_id}#{attempt}"
        with self.lock:
            committed = float(self.db.execute(
                "SELECT COALESCE(SUM(CASE WHEN state='SETTLED' THEN actual_usd "
                "WHEN state IN ('RESERVED','UNKNOWN') THEN reserved_usd ELSE 0 END),0) "
                "FROM calls").fetchone()[0])
            if committed + reserve > self.cap + 1e-12:
                return None
            try:
                self.db.execute(
                    "INSERT INTO calls(call_key,kind,batch_id,attempt,state,reserved_usd,"
                    "prompt_worst,max_tokens,created_at) VALUES(?,?,?,?,'RESERVED',?,?,?,?)",
                    (key, kind, batch_id, attempt, reserve, prompt_worst, max_tokens, time.time()))
            except sqlite3.IntegrityError:
                return "duplicate"
            self.db.commit()
            return key

    def settle(self, key, state, actual_usd=None, usage=None, error=None, http_status=None):
        with self.lock:
            self.db.execute(
                "UPDATE calls SET state=?, actual_usd=?, usage_json=?, error=?, http_status=?, "
                "settled_at=? WHERE call_key=?",
                (state, actual_usd, json.dumps(usage) if usage is not None else None,
                 (error or "")[:500] or None, http_status, time.time(), key))
            self.db.commit()

    def close(self):
        with self.lock:
            self.db.close()


def real_transport(api_key, throttle, timeout=180):
    def transport(messages, max_tokens):
        body = {"model": C.MODEL, "messages": messages, "max_tokens": max_tokens,
                "temperature": 1.0, "top_p": 1.0, "reasoning_effort": "low"}
        throttle.wait(est_tokens=C.prompt_token_worst(messages))
        req = urllib.request.Request(
            C.ENDPOINT, data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json",
                     "Authorization": "Api-Key " + api_key})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                headers = {k.lower(): v for k, v in resp.headers.items()}
                return {"kind": "ok", "http_status": resp.status,
                        "body": json.loads(resp.read()), "headers": headers}
        except urllib.error.HTTPError as e:
            retry_after = None
            try:
                ra = e.headers.get("Retry-After") if e.headers else None
                retry_after = float(ra) if ra else None
            except (TypeError, ValueError):
                retry_after = None
            if retry_after:
                throttle.penalize(retry_after)
            return {"kind": "http_error", "http_status": e.code,
                    "retry_after": retry_after, "error": f"HTTP {e.code}"}
        except Exception as e:
            return {"kind": "unknown", "error": f"{type(e).__name__}: {e}"[:300]}
    return transport


def append_jsonl(state_dir, name, record):
    path = Path(state_dir) / name
    line = json.dumps(record) + "\n"
    with open(path, "a") as f:
        f.write(line)
        f.flush()
        os.fsync(f.fileno())
    return hashlib.sha256(line.encode()).hexdigest()[:12]


def load_done_batches(state_dir, name="batches.jsonl"):
    """batch_id -> last record. A batch is done only with state SETTLED_OK."""
    done = {}
    p = Path(state_dir) / name
    if p.exists():
        for line in p.read_text().splitlines():
            if line.strip():
                rec = json.loads(line)
                done[rec["batch_id"]] = rec
    return done


def run_batch_call(store, transport, kind, batch_id, messages, max_tokens,
                   max_attempts=3, backoff_base=1.0, sleep=time.sleep):
    """Reserve -> dispatch -> settle one batched request. Returns (outcome, body).

    outcome in settled|http_error|unknown|budget_denied. Every attempt is a
    fresh reservation; UNKNOWN keeps its reserve forever.
    """
    worst = C.prompt_token_worst(messages)
    for attempt in range(1, max_attempts + 1):
        prior = store.attempts(batch_id)
        if any(a[1] == "SETTLED" for a in prior):
            return "already_settled", None
        if len(prior) >= attempt:
            if attempt == max_attempts:
                return prior[-1][1].lower(), None
            continue
        key = store.try_reserve(kind, batch_id, attempt, worst, max_tokens)
        if key is None:
            return "budget_denied", None
        if key == "duplicate":
            continue
        result = transport(messages, max_tokens)
        rkind = result.get("kind")
        if rkind == "ok":
            body = result.get("body") or {}
            usage = body.get("usage")
            if not usage or usage.get("prompt_tokens") is None or usage.get("completion_tokens") is None:
                store.settle(key, "UNKNOWN", usage=usage,
                             error="missing-usage-fails-closed",
                             http_status=result.get("http_status"))
                return "unknown", None
            actual = usage["prompt_tokens"] * C.PIN + usage["completion_tokens"] * C.POUT
            store.settle(key, "SETTLED", actual_usd=actual, usage=usage,
                         http_status=result.get("http_status"))
            return "settled", body
        if rkind == "http_error":
            store.settle(key, "HTTP_ERROR", actual_usd=0.0,
                         error=result.get("error"), http_status=result.get("http_status"))
            if attempt < max_attempts:
                sleep(result.get("retry_after") or min(30.0, backoff_base * (2 ** (attempt - 1))))
                continue
            return "http_error", None
        store.settle(key, "UNKNOWN", error=result.get("error"))
        if attempt < max_attempts:
            sleep(min(30.0, backoff_base * (2 ** (attempt - 1))))
            continue
        return "unknown", None
    return "exhausted", None


@contextlib.contextmanager
def single_writer(state_dir):
    path = Path(state_dir) / "writer.lock"
    path.parent.mkdir(parents=True, exist_ok=True)
    import fcntl
    fh = open(path, "w")
    try:
        fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise SystemExit("another spark_phone writer holds this state dir")
    fh.write(str(os.getpid()))
    fh.flush()
    try:
        yield
    finally:
        fcntl.flock(fh, fcntl.LOCK_UN)
        fh.close()


def write_status(store, status_path, phase, extra=None):
    totals = store.totals()
    settled = totals.get("SETTLED", {})
    unknown = totals.get("UNKNOWN", {})
    payload = {
        "phase": phase,
        "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "model": C.MODEL, "endpoint": C.ENDPOINT,
        "teacher_sampling": {"temperature": 1.0, "reasoning_effort": "low", "top_p": 1.0},
        "cap_usd": store.cap,
        "billed_usd": round(settled.get("actual_usd", 0.0), 6),
        "unknown_reserved_usd": round(unknown.get("reserved_usd", 0.0), 6),
        "committed_usd": round(store.committed(), 6),
        "calls": {k: v["calls"] for k, v in totals.items()},
        "limits": {
            "rpm_throttle": f"{MAX_RPM:g} enforced by this worker; existing matched worker owns 70 RPM; workspace limit 100 RPM / 2M TPM measured via live headers",
            "prices_usd_per_1m": {"input": 1.25, "output": 4.25,
                                  "source": "training/config/pricing.json verified 2026-10-31 against Baseten library page; conservative until live doc re-check recorded in status"},
            "inflight_max": MAX_INFLIGHT,
        },
    }
    if extra:
        payload.update(extra)
    status_path = Path(status_path)
    status_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = status_path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(payload, indent=1))
    tmp.replace(status_path)
    return payload
