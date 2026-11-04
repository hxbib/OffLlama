"""Persistent reservation ledger v2 for the $100 phone allocation.

Process-safe: every mutation holds an exclusive flock on
<ledger>.lock across read-check-append-fsync, so concurrent local
writers cannot oversubscribe the cap. Attempt IDs are generated under
the same lock and are globally unique; a retry is a new attempt and the
failed attempt keeps its envelope. An envelope closes only on BILLED
(provider-reconciled actual). Function timing writes OUTCOME_OK/FAIL
and never reduces committed spend. Worst case includes GPU, CPU,
memory, a 60s scaledown tail, and a startup/network allowance.

Ledger JSONL kinds: RESERVED, OUTCOME_OK, OUTCOME_FAIL, BILLED.
Legacy RESERVED rows (worst_case_usd) remain committed forever.
Pure stdlib. No spend on import.
"""
import fcntl
import json
import os
import time
import uuid
from pathlib import Path

GPU_RATES = {"B200": 6.25, "H200": 4.54, "H100": 3.95, "A100-80GB": 2.50}
MEM_USD_PER_GIB_HOUR = 0.008
CPU_USD_PER_HOUR = 0.04730
SCALEDOWN_SECONDS = 60
STARTUP_ALLOWANCE_USD = 0.05


def worst_case_usd(gpu, timeout_seconds, mem_gib=32, cpu_cores=4):
    billed_seconds = timeout_seconds + SCALEDOWN_SECONDS
    rate = GPU_RATES[gpu] + mem_gib * MEM_USD_PER_GIB_HOUR + cpu_cores * CPU_USD_PER_HOUR
    return billed_seconds / 3600.0 * rate + STARTUP_ALLOWANCE_USD


def estimate_usd(gpu, measured_seconds, mem_gib=32, cpu_cores=4):
    """Wall estimate for reporting only. Never reduces committed spend."""
    rate = GPU_RATES[gpu] + mem_gib * MEM_USD_PER_GIB_HOUR + cpu_cores * CPU_USD_PER_HOUR
    return (measured_seconds + SCALEDOWN_SECONDS) / 3600.0 * rate


class _Lock:
    def __init__(self, ledger_path):
        self.lock_path = str(ledger_path) + ".lock"
        self.fd = None

    def __enter__(self):
        Path(self.lock_path).parent.mkdir(parents=True, exist_ok=True)
        self.fd = os.open(self.lock_path, os.O_CREAT | os.O_RDWR, 0o644)
        fcntl.flock(self.fd, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        fcntl.flock(self.fd, fcntl.LOCK_UN)
        os.close(self.fd)
        return False


def _read_unlocked(ledger_path):
    p = Path(ledger_path)
    if not p.exists():
        return []
    out = []
    for line in p.read_text().splitlines():
        if line.strip():
            out.append(json.loads(line))
    return out


def _append_unlocked(ledger_path, record):
    p = Path(ledger_path)
    p.parent.mkdir(parents=True, exist_ok=True)
    with open(p, "a") as f:
        f.write(json.dumps(record) + "\n")
        f.flush()
        os.fsync(f.fileno())


def _envelope(rec):
    return float(rec.get("envelope_usd", rec.get("worst_case_usd", 0.0)))


def _totals_from(records):
    reserved = {}
    billed = {}
    estimates = 0.0
    outcomes = []
    for rec in records:
        kind = rec.get("kind")
        aid = rec.get("attempt_id") or rec.get("launch_id")
        if kind == "RESERVED":
            if aid in reserved:
                raise ValueError(f"duplicate attempt in ledger: {aid}")
            reserved[aid] = rec
        elif kind == "BILLED":
            if aid not in reserved:
                raise ValueError(f"BILLED without reservation: {aid}")
            if aid in billed:
                raise ValueError(f"duplicate BILLED: {aid}")
            billed[aid] = float(rec["actual_usd"])
        elif kind in ("OUTCOME_OK", "SETTLED"):
            if aid not in reserved and kind == "OUTCOME_OK":
                raise ValueError(f"OUTCOME without reservation: {aid}")
            estimates += float(rec.get("est_usd", rec.get("actual_usd", 0.0)))
            outcomes.append(rec)
        elif kind in ("OUTCOME_FAIL", "UNKNOWN"):
            outcomes.append(rec)
    open_env = sum(_envelope(r) for aid, r in reserved.items() if aid not in billed)
    settled = sum(billed.values())
    return {
        "settled_billed_usd": settled,
        "unknown_reserved_usd": open_env,
        "committed_usd": settled + open_env,
        "estimated_spend_usd": estimates,
        "open_attempts": sorted(a for a in reserved if a not in billed),
        "billed_attempts": sorted(billed),
        "attempts": [
            {"attempt_id": aid, "job_key": r.get("job_key") or r.get("note", ""),
             "gpu": r.get("gpu"), "envelope_usd": _envelope(r),
             "billed_usd": billed.get(aid)}
            for aid, r in reserved.items()
        ],
        "outcomes": outcomes,
    }


def totals(ledger_path):
    with _Lock(ledger_path):
        return _totals_from(_read_unlocked(ledger_path))


def reserve(ledger_path, cap_usd, job_key, gpu, timeout_seconds,
            mem_gib=32, cpu_cores=4, note=""):
    """Atomically check cap and append a RESERVED envelope.

    Returns the unique attempt_id. Raises RuntimeError when the new
    envelope would push committed spend over the cap.
    """
    env = worst_case_usd(gpu, timeout_seconds, mem_gib, cpu_cores)
    with _Lock(ledger_path):
        records = _read_unlocked(ledger_path)
        t = _totals_from(records)
        if t["committed_usd"] + env > cap_usd + 1e-9:
            raise RuntimeError(
                f"budget stop: committed ${t['committed_usd']:.4f} + envelope "
                f"${env:.4f} > cap ${cap_usd:.2f} for {job_key}")
        attempt_id = f"{job_key}#{uuid.uuid4().hex[:10]}"
        _append_unlocked(ledger_path, {
            "kind": "RESERVED", "attempt_id": attempt_id, "job_key": job_key,
            "gpu": gpu, "timeout_seconds": timeout_seconds,
            "envelope_usd": env, "note": note, "at_epoch": time.time(),
        })
        return attempt_id


def outcome(ledger_path, attempt_id, ok, gpu, measured_seconds=None,
            mem_gib=32, cpu_cores=4, note=""):
    """Record function outcome. Envelope stays committed either way."""
    with _Lock(ledger_path):
        records = _read_unlocked(ledger_path)
        ids = {r.get("attempt_id") or r.get("launch_id") for r in records
               if r.get("kind") == "RESERVED"}
        if attempt_id not in ids:
            raise ValueError(f"outcome without reservation: {attempt_id}")
        est = (estimate_usd(gpu, measured_seconds, mem_gib, cpu_cores)
               if measured_seconds is not None else 0.0)
        _append_unlocked(ledger_path, {
            "kind": "OUTCOME_OK" if ok else "OUTCOME_FAIL",
            "attempt_id": attempt_id, "gpu": gpu,
            "seconds": measured_seconds, "est_usd": est,
            "note": note, "at_epoch": time.time(),
        })


def billed(ledger_path, attempt_id, actual_usd, source):
    """Close an envelope at the provider-reconciled actual."""
    with _Lock(ledger_path):
        records = _read_unlocked(ledger_path)
        t = _totals_from(records)
        if attempt_id in t["billed_attempts"]:
            raise ValueError(f"already billed: {attempt_id}")
        if attempt_id not in t["open_attempts"]:
            raise ValueError(f"billed without open reservation: {attempt_id}")
        _append_unlocked(ledger_path, {
            "kind": "BILLED", "attempt_id": attempt_id,
            "actual_usd": float(actual_usd), "source": source,
            "at_epoch": time.time(),
        })


def can_launch(ledger_path, cap_usd, gpu, timeout_seconds, mem_gib=32, cpu_cores=4):
    t = totals(ledger_path)
    return t["committed_usd"] + worst_case_usd(gpu, timeout_seconds, mem_gib, cpu_cores) <= cap_usd + 1e-9


def write_status(ledger_path, status_path, cap_usd, extra=None):
    t = totals(ledger_path)
    data = {"cap_usd": cap_usd, **t, **(extra or {})}
    p = Path(status_path)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2))
    os.replace(tmp, p)
    return data


def sync_budget_files(ledger_path, budget_path, jobs_path, cap_usd, jobs_meta):
    """Derive budget.json/jobs.json views from the ledger (never truth)."""
    t = totals(ledger_path)
    budget = {"cap_usd": cap_usd, **t,
              "note": "Derived from ledger.jsonl. Committed = billed + open envelopes. "
                      "Estimates never reduce committed spend."}
    Path(budget_path).write_text(json.dumps(budget, indent=2))
    jobs = {"allocation": f"phone-training-v1 ${cap_usd:.0f} Modal total. Zero Baseten.",
            "committed_usd": t["committed_usd"],
            "jobs": jobs_meta}
    Path(jobs_path).write_text(json.dumps(jobs, indent=2))
    return budget
