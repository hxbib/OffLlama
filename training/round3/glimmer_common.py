"""Shared logic for the Round-3 Glimmer probability-label pipeline.

Pure and testable. No Modal, vLLM, network, or spend happens on import.
Prompt rendering matches training/local_teacher/glimmer_teacher.py exactly:
the checkpoint chat template renders prompts.chat_messages with
tools=None, add_generation_prompt=True, bos_token="", reasoning_strength="low",
current_date="2026-10-31", then the forced suffix below is appended and the
next token is the answer letter. Tokenization of the rendered string must use
add_special_tokens=False so no hidden BOS is inserted.
"""
import hashlib
import json
import math
import os
import sys
from pathlib import Path

MODEL_ID = "meta-models/Muse-Glimmer-30B"
MODEL_REVISION = "main"
TEMPLATE_SHA256 = "cfc67e5f349f37690dfd31ed1f18bc4442a9dd32fe39a648f993cb4eb3cae678"
SUFFIX = " to=user<|message|>Answer:"
CURRENT_DATE = "2026-10-31"
LETTERS = "ABCDEFGH"

# Every vocab token whose decoded text is whitespace plus one uppercase
# letter. Verified against the checkpoint tokenizer.json on 2026-11-04:
# plain (45-52), space-prefixed (352..477), tab-prefixed (20160..55362).
# There are no newline-prefixed or double-space letter tokens in the vocab.
LETTER_TOKEN_IDS = {
    "A": [45, 352, 55362],
    "B": [46, 410, 41985],
    "C": [47, 354, 20160],
    "D": [48, 401, 30082],
    "E": [49, 427, 53289],
    "F": [50, 433, 30018],
    "G": [51, 477, 31307],
    "H": [52, 465, 31579],
}
ALL_LETTER_TOKEN_IDS = sorted(t for ids in LETTER_TOKEN_IDS.values() for t in ids)

MASS_USABLE_MIN = 0.5
MISSING_BOUND_EPS = 0.002
ANCHOR_USABLE_MIN = 0.95

GPU_RATES_USD_PER_HOUR = {"B200": 6.25, "H200": 4.54, "H100": 3.95, "A100-80GB": 2.50}
MEM_USD_PER_GIB_HOUR = 0.008
CPU_USD_PER_HOUR = 0.04730
CONTAINER_MEM_GIB = 32
CONTAINER_CPU_CORES = 4
CAP_USD = 20.0


def _load_prompts():
    root = Path(__file__).resolve().parents[1]
    if str(root) not in sys.path:
        sys.path.insert(0, str(root))
    from pg_train import prompts
    return prompts


def sha256_text(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sha256_file(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def render_prompt(type_name, context, candidates, template_text):
    """Render one teacher prompt exactly as glimmer_teacher.render does."""
    import datetime
    import jinja2

    prompts = _load_prompts()
    option_set = prompts.get_set(type_name, candidates)
    env = jinja2.Environment()
    env.globals["raise_exception"] = lambda m: (_ for _ in ()).throw(Exception(m))
    env.globals["strftime_now"] = lambda f: datetime.datetime(2026, 10, 31).strftime(f)
    tmpl = env.from_string(template_text)
    rendered = tmpl.render(
        messages=prompts.chat_messages(option_set, context),
        tools=None,
        add_generation_prompt=True,
        bos_token="",
        reasoning_strength="low",
        current_date=CURRENT_DATE,
    )
    return rendered + SUFFIX, option_set


def letters_for(option_set):
    return list(LETTERS[: len(option_set["options"])])


def option_ids_for(option_set):
    return [o["id"] for o in option_set["options"]]


def legal_token_ids(letters):
    return {letter: list(LETTER_TOKEN_IDS[letter]) for letter in letters}


def _is_finite_logprob(value):
    return isinstance(value, (int, float)) and math.isfinite(value) and value <= 1e-6


def aggregate_letter_probs(top_logprobs, probe_logprobs, letters, topk_min_logprob):
    """Aggregate raw next-token logprobs into a per-letter distribution.

    top_logprobs and probe_logprobs map token_id (int) to logprob (float).
    Missing legal tokens are censored, never treated as probability zero.
    Returns a dict with status, raw per-letter probabilities, letter mass,
    the renormalized distribution (only when usable or complete), and the
    censoring bound. Statuses: valid_complete, valid_bounded,
    invalid_censored, invalid_nonfinite.
    """
    observed = {}
    for source in (top_logprobs or {}, probe_logprobs or {}):
        for tid, lp in source.items():
            observed[int(tid)] = float(lp)
    for tid, lp in observed.items():
        if not _is_finite_logprob(lp):
            return {
                "status": "invalid_nonfinite",
                "usable": False,
                "reason": f"nonfinite_or_positive_logprob token {tid}: {lp}",
                "raw_letter_probs": None,
                "distribution": None,
                "letter_mass": None,
                "missing_token_ids": [],
                "missing_mass_upper": None,
            }
    legal = legal_token_ids(letters)
    legal_ids = sorted(t for ids in legal.values() for t in ids)
    missing = [t for t in legal_ids if t not in observed]
    raw = {}
    for letter in letters:
        raw[letter] = sum(math.exp(observed[t]) for t in legal[letter] if t in observed)
    mass_observed = sum(raw.values())
    if not missing:
        if mass_observed <= 0:
            return {
                "status": "invalid_nonfinite",
                "usable": False,
                "reason": "zero_letter_mass",
                "raw_letter_probs": raw,
                "distribution": None,
                "letter_mass": mass_observed,
                "missing_token_ids": [],
                "missing_mass_upper": 0.0,
            }
        dist = {letter: raw[letter] / mass_observed for letter in letters}
        return {
            "status": "valid_complete",
            "usable": mass_observed >= MASS_USABLE_MIN,
            "reason": None if mass_observed >= MASS_USABLE_MIN else "letter_mass_below_0.5",
            "raw_letter_probs": raw,
            "distribution": dist,
            "letter_mass": mass_observed,
            "missing_token_ids": [],
            "missing_mass_upper": 0.0,
        }
    if topk_min_logprob is None or not _is_finite_logprob(topk_min_logprob):
        return {
            "status": "invalid_censored",
            "usable": False,
            "reason": "missing_tokens_without_topk_bound",
            "raw_letter_probs": raw,
            "distribution": None,
            "letter_mass": mass_observed,
            "missing_token_ids": missing,
            "missing_mass_upper": None,
        }
    missing_upper = len(missing) * math.exp(topk_min_logprob)
    bounded_ok = mass_observed >= MASS_USABLE_MIN and missing_upper <= MISSING_BOUND_EPS
    dist = None
    if bounded_ok:
        dist = {letter: raw[letter] / mass_observed for letter in letters}
    return {
        "status": "valid_bounded" if bounded_ok else "invalid_censored",
        "usable": bounded_ok,
        "reason": None if bounded_ok else "censored_mass_bound_too_large_or_mass_low",
        "raw_letter_probs": raw,
        "distribution": dist,
        "letter_mass": mass_observed,
        "missing_token_ids": missing,
        "missing_mass_upper": missing_upper,
    }


def select_balanced(rows, per_type):
    by_type = {}
    for row in rows:
        by_type.setdefault(row["type"], []).append(row)
    picked = []
    for type_name in sorted(by_type):
        picked.extend(by_type[type_name][:per_type])
    picked_ids = {r["id"] for r in picked}
    return [r for r in rows if r["id"] in picked_ids]


def load_done_index(out_path):
    """Map prompt_hash to the latest terminal record. Error rows are retried."""
    index = {}
    path = Path(out_path)
    if not path.exists():
        return index
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        try:
            rec = json.loads(line)
        except Exception:
            continue
        key = rec.get("prompt_hash")
        if not key:
            continue
        if rec.get("status") == "error":
            index.pop(key, None)
        else:
            index[key] = rec
    return index


def append_jsonl(path, records):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a") as f:
        for rec in records:
            f.write(json.dumps(rec) + "\n")
        f.flush()
        os.fsync(f.fileno())


def worst_case_usd(gpu, timeout_seconds):
    rate = GPU_RATES_USD_PER_HOUR[gpu] + CONTAINER_MEM_GIB * MEM_USD_PER_GIB_HOUR + CONTAINER_CPU_CORES * CPU_USD_PER_HOUR
    return timeout_seconds / 3600.0 * rate


class BudgetLedger:
    """Hard $20 total bound. A launch needs settled + worst-case <= cap."""

    def __init__(self, cap_usd=CAP_USD, settled_usd=0.0, calls=None):
        self.cap_usd = float(cap_usd)
        self.settled_usd = float(settled_usd)
        self.calls = list(calls or [])

    def can_launch(self, gpu, timeout_seconds):
        return self.settled_usd + worst_case_usd(gpu, timeout_seconds) <= self.cap_usd + 1e-9

    def settle(self, gpu, measured_seconds, note=""):
        rate = GPU_RATES_USD_PER_HOUR[gpu] + CONTAINER_MEM_GIB * MEM_USD_PER_GIB_HOUR + CONTAINER_CPU_CORES * CPU_USD_PER_HOUR
        usd = measured_seconds / 3600.0 * rate
        self.settled_usd += usd
        entry = {"gpu": gpu, "seconds": measured_seconds, "usd": usd, "note": note}
        self.calls.append(entry)
        return entry

    def to_dict(self):
        return {"cap_usd": self.cap_usd, "settled_usd": self.settled_usd, "calls": self.calls}


def summarize_records(records):
    usable = [r for r in records if r.get("usable")]
    masses = sorted(r["letter_mass"] for r in records if isinstance(r.get("letter_mass"), (int, float)))
    by_status = {}
    for r in records:
        by_status[r.get("status")] = by_status.get(r.get("status"), 0) + 1

    def pct(p):
        if not masses:
            return None
        return masses[min(len(masses) - 1, max(0, int(p * len(masses))))]

    return {
        "rows": len(records),
        "usable": len(usable),
        "usable_rate": (len(usable) / len(records)) if records else None,
        "by_status": by_status,
        "letter_mass_min": masses[0] if masses else None,
        "letter_mass_p05": pct(0.05),
        "letter_mass_median": pct(0.5),
        "letter_mass_max": masses[-1] if masses else None,
    }
