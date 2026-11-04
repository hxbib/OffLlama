"""Shared logic for the Spark phone-expansion pipeline (Baseten Spark Open).

Owns prompt rendering, batch parsing, and deterministic contract checks for
training/round3/spark_phone_* only. No network or spend happens on import.

Rules encoded here:
- Teacher targets come only from meta-models/muse-spark-open-1026 votes.
  Agent prose and Meta Model API output are never training targets.
- Batched outputs must map exactly to input IDs. Malformed, partial, or
  duplicate IDs are rejected as a whole batch, never silently repaired.
- Vote frequencies are empirical sample frequencies from a fixed number of
  draws. They are not teacher log-probabilities, and no soft target is ever
  built from a single draw.
"""
import hashlib
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "training"))
from pg_train import prompts as _prompts  # noqa: E402

MODEL = "meta-models/muse-spark-open-1026"
ENDPOINT = "https://inference.baseten.co/v1/chat/completions"
TEACHER = "muse-spark-open-1026@baseten"
PIN, POUT = 1.25e-6, 4.25e-6  # USD/token; conservative until live-confirmed
LETTERS = "ABCDEFGH"
TEXT_LIMIT = 2000

DISPOSITIONS = [
    "unsupported", "clarify_missing", "clarify_invalid", "resolve_ambiguity",
    "permission_unavailable", "await_confirmation", "cancel", "execute_once",
    "observed_result", "failed", "unknown_no_replay",
]


def sha256_text(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sha256_file(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load_jsonl(path):
    return [json.loads(l) for l in Path(path).read_text().splitlines() if l.strip()]


# --- contracts (source of truth: docs/ACTION_CONTRACTS.json) ---

def load_contracts(path=None):
    p = Path(path) if path else ROOT / "docs" / "ACTION_CONTRACTS.json"
    raw = json.loads(p.read_text())
    return {e["capability"]["id"]: e for e in raw}


def availability(entry):
    a = entry["capability"]["availability"]
    return next(iter(a.keys())) if isinstance(a, dict) else str(a)


def confirmation(entry):
    c = entry["capability"]["confirmation"]
    return next(iter(c.keys())) if isinstance(c, dict) else str(c)


# --- Reflex option sets (pg_train.prompts + skillPick extension) ---

def extended_get_set(kind, candidates=None):
    if kind == "skillPick":
        c = list(candidates or [])[:7]
        return {"type": "skillPick",
                "question": "Which phone action does the user want?",
                "fallback": "ask",
                "options": [{"id": f"s{i}", "label": x} for i, x in enumerate(c)]
                + [{"id": "ask", "label": "None of these: ask the user"}]}
    return _prompts.get_set(kind, candidates)


def letters_for(option_set):
    return list(LETTERS[: len(option_set["options"])])


def option_ids_for(option_set):
    return [o["id"] for o in option_set["options"]]


def set_for_row(row):
    kind = row.get("reflex_type") or row.get("type") or row.get("decision_type")
    return extended_get_set(kind, row.get("candidates"))


def item_body(option_set, context):
    """Single-item body, byte-identical shape to prompts.body."""
    out = f"Context:\n{context.strip()}\n\nQuestion: {option_set['question']}\n"
    for i, o in enumerate(option_set["options"]):
        out += f"{LETTERS[i]}. {o['label']}\n"
    return out + "Answer with one letter."


# --- batched labeling prompts ---

LABEL_SYSTEM = (
    "You are Reflex, the fast decision module of an offline personal assistant. "
    "You will be given several independent multiple-choice items. For each item, "
    "choose exactly one letter. Reply with ONLY a JSON array, one object per item, "
    'each exactly {"id": "<item id>", "letter": "<letter>"}. No other text.'
)


def label_batch_messages(rows):
    """One chat request covering len(rows) independent decision contexts."""
    blocks = []
    for row in rows:
        oset = set_for_row(row)
        blocks.append(f"Item id: {row['id']}\n" + item_body(oset, row["context"]))
    user = ("\n\n---\n\n".join(blocks)
            + "\n\nReply with ONLY the JSON array described in the system message.")
    return [{"role": "system", "content": LABEL_SYSTEM},
            {"role": "user", "content": user}]


def parse_label_batch(content, rows):
    """Return {id: letter} or raise ValueError. Exact ID-set match required."""
    text = (content or "").strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    try:
        data = json.loads(text)
    except Exception:
        m = re.search(r"\[.*\]", text, re.S)
        if not m:
            raise ValueError("no_json_array")
        data = json.loads(m.group(0))
    if not isinstance(data, list):
        raise ValueError("not_a_list")
    want = {r["id"]: set_for_row(r) for r in rows}
    got = {}
    for obj in data:
        if not isinstance(obj, dict) or set(obj.keys()) != {"id", "letter"}:
            raise ValueError(f"bad_object_keys:{obj!r:.80}")
        iid, letter = obj["id"], obj["letter"]
        if iid not in want:
            raise ValueError(f"unknown_id:{iid}")
        if iid in got:
            raise ValueError(f"duplicate_id:{iid}")
        if letter not in letters_for(want[iid]):
            raise ValueError(f"bad_letter:{iid}:{letter}")
        got[iid] = letter
    missing = set(want) - set(got)
    if missing:
        raise ValueError(f"missing_ids:{sorted(missing)}")
    return got


# --- generation prompts ---

GEN_SYSTEM = (
    "You write short, natural iPhone assistant requests for a training corpus. "
    "You invent varied people, places, times and phrasings; you never copy the "
    "examples verbatim. Reply with ONLY a JSON array of objects, each exactly "
    '{"utterance": "<request>", "arguments": {<typed arguments>}}. No other text.'
)

FAMILY_GUIDANCE = {
    "valid_complete": "Complete, actionable requests with every required argument present and valid.",
    "missing_required": "Requests that omit one required argument (e.g. no body, no time, no destination). Keep the omission natural; put only the arguments actually expressed in the arguments object.",
    "invalid_field": "Requests whose expressed value is invalid for its field (bad handle characters, malformed URL, impossible duration, ambiguous timezone abbreviation like EST without AM/PM). Put the invalid value in arguments.",
    "contact_ambiguous": "Requests naming a person by first name only where two contacts could match. Express the first name in arguments.",
    "time_difficult": "Requests with relative or tricky times: tomorrow, in 20 minutes, tonight, next Friday, bare hours without AM/PM, or explicit IANA timezones. Keep the time expression inside the utterance and in the datetime argument verbatim.",
    "permission": "Requests that need a permission the user has not granted (contacts, calendar, photos, location). The utterance itself stays a normal request.",
    "cancellation": "Requests where the user cancels or changes their mind mid-request (never mind, cancel that, stop).",
    "privacy_difficult": "Requests involving health, money, passwords, or private details where cloud handling would be sensitive. Keep them realistic, not graphic.",
    "hard_negative": "Requests that sound like a phone action but should not execute directly: questions about the action, hypotheticals, or asking someone else to do it.",
    "recovery_failed": "Follow-ups after a failed attempt (it failed, try again differently, that did not work).",
    "confirmation_risky": "Requests with irreversible or other-person effects (sending money-adjacent messages, deleting, posting) that must be confirmed first.",
    "unsupported_extra": "Requests asking for an option the action does not support (recurrence, arrival triggers, attachments, cc/bcc, event end times or invitees). Express the unsupported ask in the utterance.",
}


def generation_batch_messages(contract_id, entry, family, count, seed_hint):
    cap = entry["capability"]
    args_desc = "; ".join(
        f"{a['name']} ({a['kind']}, {'required' if a['required'] else 'optional'})"
        for a in cap["arguments"]) or "no arguments"
    user = (
        f"Action: {cap['title']} (id: {contract_id}). Arguments: {args_desc}.\n"
        f"Style: {FAMILY_GUIDANCE[family]}\n"
        f"Write {count} distinct requests (seed {seed_hint}). Vary names, places, "
        "times, wording and sentence length. Each arguments object must contain "
        "exactly the arguments expressed in its utterance, using the argument "
        "names above. Datetime values keep the user's own words (e.g. "
        '"tomorrow at 7:30 AM America/New_York"). No numbering, no explanations.'
    )
    return [{"role": "system", "content": GEN_SYSTEM},
            {"role": "user", "content": user}]


def parse_generation_batch(content, count):
    text = (content or "").strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    try:
        data = json.loads(text)
    except Exception:
        m = re.search(r"\[.*\]", text, re.S)
        if not m:
            raise ValueError("no_json_array")
        data = json.loads(m.group(0))
    if not isinstance(data, list) or not data:
        raise ValueError("not_a_nonempty_list")
    out = []
    for obj in data:
        if not isinstance(obj, dict) or "utterance" not in obj:
            raise ValueError(f"bad_object:{obj!r:.80}")
        utt = str(obj.get("utterance") or "").strip()
        args = obj.get("arguments") or {}
        if not utt or not isinstance(args, dict):
            raise ValueError("empty_utterance_or_args")
        out.append({"utterance": utt,
                    "arguments": {str(k): str(v) for k, v in args.items()}})
    return out


# --- deterministic contract validation (cross-checks, never teacher prose) ---

_HANDLE_X = re.compile(r"^[A-Za-z0-9_]{1,15}$")
_HANDLE_IG = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.]{0,29}$")
_DURATION_RE = re.compile(r"([0-9]+(?:\.[0-9]+)?)\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?)", re.I)
_NUMBER_RE = re.compile(r"^[0-9]+$")


def duration_seconds(text):
    text = (text or "").strip()
    matches = list(_DURATION_RE.finditer(text))
    if not matches:
        return None
    rest = re.sub(r"\band\b", "", _DURATION_RE.sub("", text), flags=re.I).strip()
    if rest:
        return None
    total = 0.0
    for m in matches:
        n, unit = float(m.group(1)), m.group(2).lower()
        total += n * (3600 if unit.startswith("h") else 60 if unit.startswith("m") else 1)
    return total


def is_web_url(text):
    t = (text or "").strip()
    if not t or any(c.isspace() for c in t) or "://" not in t:
        return False
    scheme, rest = t.split("://", 1)
    if scheme.lower() not in ("http", "https"):
        return False
    host = rest.split("/")[0].split("?")[0].split("#")[0]
    return bool(host) and "@" not in host and "{" not in host and "}" not in host


def arg_issue(spec, value, capability_id):
    name, kind = spec["name"], spec["kind"]
    value = value if value is not None else ""
    if not value.strip():
        return (name, "missing") if spec["required"] else None
    if len(value) > TEXT_LIMIT or any(
            (ord(c) < 32 and c not in "\t\n\r") or ord(c) == 127 for c in value):
        return (name, "invalid")
    if kind == "handle":
        pat = _HANDLE_X if capability_id == "x_dm" else _HANDLE_IG
        if not pat.match(value.strip()):
            return (name, "invalid")
    elif kind == "url" and not is_web_url(value):
        return (name, "invalid")
    elif kind == "duration":
        secs = duration_seconds(value)
        if secs is None or not (0 < secs <= 86400):
            return (name, "invalid")
    elif kind == "number":
        if not _NUMBER_RE.match(value.strip()) or not (1 <= int(value.strip()) <= 100):
            return (name, "invalid")
    if capability_id == "alarm_create" and "|" in value:
        return (name, "invalid")
    return None


def contract_issues(entry, args):
    cap = entry["capability"]
    allowed = {a["name"] for a in cap["arguments"]}
    out = [(k, "unsupported") for k in sorted((args or {}).keys()) if k not in allowed]
    for spec in cap["arguments"]:
        iss = arg_issue(spec, (args or {}).get(spec["name"]), cap["id"])
        if iss:
            out.append(iss)
    return out


_RECURRENCE = re.compile(r"\b(every|each|daily|weekly|monthly|yearly|recurring|repeat)\b", re.I)
_TRIGGER = re.compile(r"\b(all[ -]day|when I (?:arrive|leave|get)|when (?:arriving|leaving))\b", re.I)
_EVENTOPTS = re.compile(r"(\bfor\s+\d+\s*(?:hours?|minutes?)|\buntil\b|\bending\b|\bends? at\b|\binvite\b|\battendees?\b)", re.I)
_MSGOPTS = re.compile(r"\b(?:attach|attachment|cc|bcc)\b", re.I)
_TOGGLE_WORD = re.compile(r"\btoggle\b", re.I)


def request_issue(capability_id, utterance):
    u = utterance or ""
    if capability_id in ("flashlight_toggle", "focus_toggle", "low_power_toggle"):
        if not _TOGGLE_WORD.search(u):
            return ("state", "unsupported")
    if capability_id in ("reminder_create", "calendar_create", "alarm_create"):
        if _RECURRENCE.search(u):
            return ("recurrence", "unsupported")
        if _TRIGGER.search(u):
            return ("trigger", "unsupported")
    if capability_id == "calendar_create" and _EVENTOPTS.search(u):
        return ("event_options", "unsupported")
    if capability_id in ("imessage_send", "email_compose", "whatsapp_send", "instagram_dm", "x_dm"):
        prefix = re.split(r'["\u201c:]', u, maxsplit=1)[0].split(" saying ")[0]
        if _MSGOPTS.search(prefix):
            return ("message_options", "unsupported")
    return None


_AMPM = re.compile(r"\b(am|pm|a\.m\.|p\.m\.)\b", re.I)
_H24 = re.compile(r"\b([01]?\d|2[0-3]):[0-5]\d\b")
_BARE_HOUR = re.compile(r"\bat\s+\d{1,2}(\s|$)", re.I)
_BAD_TZ = re.compile(r"\b(EST|EDT|PST|PDT|CST|CDT|MST|MDT)\b")
_GOOD_TZ = ("America/", "UTC", "GMT", "Europe/", "Asia/", "Australia/")


def datetime_disposition(when_text):
    t = when_text or ""
    if not t.strip():
        return "clarify_missing"
    if _BAD_TZ.search(t) and not any(g in t for g in _GOOD_TZ):
        return "clarify_invalid"
    if _AMPM.search(t) or _H24.search(t):
        return None
    return "clarify_invalid"


def disposition_for(entry, args, utterance, flags=None):
    """Deterministic disposition where the contract decides it, else None.

    Mirrors the compiled-contract semantics used by the phone tranche:
    availability, fixture flags, request guards, field issues, the exact-time
    gate, ambiguity, then confirmation policy.
    """
    flags = flags or {}
    cap = entry["capability"]
    if availability(entry) == "notWired":
        return ("unsupported", "contract_availability_notWired")
    if flags.get("cancel"):
        return ("cancel", "fixture_cancel_phrase")
    if flags.get("interrupted_unknown"):
        return ("unknown_no_replay", "fixture_interrupted_attempt")
    if flags.get("permission_denied"):
        return ("permission_unavailable", "fixture_permission_denied")
    ri = request_issue(cap["id"], utterance)
    if ri is not None:
        return ("clarify_invalid", f"request_guard_{ri[0]}")
    for field, code in contract_issues(entry, args or {}):
        if code == "missing":
            return ("clarify_missing", f"required_field_missing_{field}")
        if code == "invalid":
            return ("clarify_invalid", f"field_invalid_{field}")
        return ("clarify_invalid", f"unsupported_field_{field}")
    for spec in cap["arguments"]:
        if spec["kind"] == "datetime":
            d = datetime_disposition((args or {}).get(spec["name"], ""))
            if d:
                return (d, f"datetime_{d}_{spec['name']}")
    if flags.get("ambiguous_contact"):
        return ("resolve_ambiguity", "fixture_ambiguous_contact")
    if flags.get("failed_outcome"):
        return ("failed", "fixture_executor_failed")
    if confirmation(entry) == "always":
        return ("await_confirmation", "contract_confirmation_always")
    return ("execute_once", "contract_ready_deterministic_args")


FAMILY_FLAGS = {
    "contact_ambiguous": {"ambiguous_contact": True},
    "hard_negative": {"ambiguous_contact": True},
    "permission": {"permission_denied": True},
    "cancellation": {"cancel": True},
    "recovery_failed": {"failed_outcome": True},
}


# --- dedupe / held-out exclusion ---

def norm(text):
    t = (text or "").lower()
    t = re.sub(r"\d", "0", t)
    t = re.sub(r"[^a-z0 ]+", " ", t)
    return re.sub(r"\s+", " ", t).strip()


def core_key(context):
    lines = [l for l in (context or "").splitlines()
             if not re.match(r"^(Now:|User location:|Network:)\s", l.strip())]
    return "g" + sha256_text(norm("\n".join(lines).strip()))[:15]


def prompt_token_worst(messages):
    return sum(len(m.get("content") or "") for m in messages) + 16 * len(messages) + 8


def reserve_usd(prompt_worst, max_tokens):
    return prompt_worst * PIN + max_tokens * POUT
