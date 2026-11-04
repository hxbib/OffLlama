"""Phone-action contract helpers. Pure stdlib + pg_train.prompts import.

Source of truth is docs/ACTION_CONTRACTS.json (38 compiled contracts, v2)
plus core/Sources/PocketCore/ActionValidation.swift semantics. This module
ports the deterministic validators needed to label phone inputs and to
check option mapping. It never invents a native ability: the one
notWired contract (alarmkit_schedule) stays unsupported.

No network, no spend on import.
"""
import hashlib
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
_parents = HERE.parents
ROOT = _parents[1] if len(_parents) > 1 else HERE

DISPOSITIONS = [
    "unsupported", "clarify_missing", "clarify_invalid", "resolve_ambiguity",
    "permission_unavailable", "await_confirmation", "cancel", "execute_once",
    "observed_result", "failed", "unknown_no_replay",
]

TEXT_LIMIT = 2000


def load_contracts(path=None):
    p = Path(path) if path else ROOT / "docs" / "ACTION_CONTRACTS.json"
    raw = json.loads(p.read_text())
    out = {}
    for entry in raw:
        cap = entry["capability"]
        out[cap["id"]] = entry
    return out


def contract_ids(path=None):
    return sorted(load_contracts(path).keys())


def availability(entry):
    avail = entry["capability"]["availability"]
    if isinstance(avail, dict):
        return next(iter(avail.keys()))
    return str(avail)


def confirmation(entry):
    conf = entry["capability"]["confirmation"]
    if isinstance(conf, dict):
        return next(iter(conf.keys()))
    return str(conf)


def executor(entry):
    ex = entry["capability"]["executor"]
    if isinstance(ex, dict):
        return next(iter(ex.keys()))
    return str(ex)


def option_label(title, example):
    return f"{title} (e.g. {example})" if example else title


def extended_get_set(kind, candidates=None):
    """Reflex option set including skillPick. Mirrors Swift OptionSets."""
    import sys
    sys.path.insert(0, str(ROOT / "training"))
    from pg_train import prompts
    if kind == "skillPick":
        c = list(candidates or [])[:7]
        return {
            "type": "skillPick",
            "question": "Which phone action does the user want?",
            "fallback": "ask",
            "options": [{"id": f"s{i}", "label": x} for i, x in enumerate(c)]
            + [{"id": "ask", "label": "None of these: ask the user"}],
        }
    return prompts.get_set(kind, candidates)


def letters_for(option_set):
    return list("ABCDEFGH"[: len(option_set["options"])])


def option_ids_for(option_set):
    return [o["id"] for o in option_set["options"]]


def letter_for_id(option_set, oid):
    ids = option_ids_for(option_set)
    if oid not in ids:
        return None
    return "ABCDEFGH"[ids.index(oid)]


def id_for_letter(option_set, letter):
    ids = option_ids_for(option_set)
    i = "ABCDEFGH".find(letter)
    if i < 0 or i >= len(ids):
        return None
    return ids[i]


# --- Ports of ActionValidation.swift deterministic checks ---

_HANDLE_X = re.compile(r"^[A-Za-z0-9_]{1,15}$")
_HANDLE_IG = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.]{0,29}$")
_DURATION_RE = re.compile(r"([0-9]+(?:\.[0-9]+)?)\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?)", re.I)
_NUMBER_RE = re.compile(r"^[0-9]+$")


def duration_seconds(text):
    text = (text or "").strip()
    matches = list(_DURATION_RE.finditer(text))
    if not matches:
        return None
    remainder = _DURATION_RE.sub("", text)
    remainder = re.sub(r"\band\b", "", remainder, flags=re.I).strip()
    if remainder:
        return None
    total = 0.0
    for m in matches:
        n = float(m.group(1))
        unit = m.group(2).lower()
        total += n * (3600 if unit.startswith("h") else 60 if unit.startswith("m") else 1)
    return total


def is_web_url(text):
    t = (text or "").strip()
    if not t or any(ch.isspace() for ch in t):
        return False
    if "://" not in t:
        return False
    scheme, rest = t.split("://", 1)
    if scheme.lower() not in ("http", "https"):
        return False
    host = rest.split("/")[0].split("?")[0].split("#")[0]
    if "@" in host:
        return False
    if not host or "{" in host or "}" in host:
        return False
    return True


def arg_issue(spec, value, capability_id):
    """Return (field, code) or None. Code in missing/invalid/unsupported."""
    name = spec["name"]
    kind = spec["kind"]
    required = bool(spec["required"])
    value = value if value is not None else ""
    trimmed = value.strip()
    if not trimmed:
        return (name, "missing") if required else None
    if len(value) > TEXT_LIMIT:
        return (name, "invalid")
    for ch in value:
        o = ord(ch)
        if (o < 32 and o not in (9, 10, 13)) or o == 127:
            return (name, "invalid")
    if kind == "handle":
        pat = _HANDLE_X if capability_id == "x_dm" else _HANDLE_IG
        if not pat.match(trimmed):
            return (name, "invalid")
    elif kind == "url":
        if not is_web_url(trimmed):
            return (name, "invalid")
    elif kind == "duration":
        secs = duration_seconds(trimmed)
        if secs is None or not (secs > 0 and secs <= 86400):
            return (name, "invalid")
    elif kind == "number":
        if not _NUMBER_RE.match(trimmed):
            return (name, "invalid")
        if not (1 <= int(trimmed) <= 100):
            return (name, "invalid")
    if capability_id == "alarm_create" and "|" in value:
        return (name, "invalid")
    return None


def contract_issues(entry, args):
    """Unsupported keys first, then per-spec issues. Mirrors issues()."""
    cap = entry["capability"]
    allowed = {a["name"] for a in cap["arguments"]}
    out = []
    for key in sorted(args.keys()):
        if key not in allowed:
            out.append((key, "unsupported"))
    for spec in cap["arguments"]:
        iss = arg_issue(spec, args.get(spec["name"]), cap["id"])
        if iss:
            out.append(iss)
    return out


_RECURRENCE = re.compile(r"\b(every|each|daily|weekly|monthly|yearly|recurring|repeat)\b", re.I)
_TRIGGER = re.compile(r"\b(all[ -]day|when I (?:arrive|leave|get)|when (?:arriving|leaving))\b", re.I)
_EVENTOPTS = re.compile(r"(\bfor\s+\d+\s*(?:hours?|minutes?)|\buntil\b|\bending\b|\bends? at\b|\binvite\b|\battendees?\b|\bfrom\s+\d.*\bto\s+\d)", re.I)
_MSGOPTS = re.compile(r"\b(?:attach|attachment|cc|bcc|schedule|scheduled)\b|\b(?:text|message|email|mail|dm)\s+\w+\s+(?:and|&)\s+\w+", re.I)
_TOGGLE_WORD = re.compile(r"\btoggle\b", re.I)


def request_issue(capability_id, utterance):
    """Narrow guards. Returns (field, code) or None. Mirrors requestIssue()."""
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
        prefix = re.split(r'["\u201c:]', u, maxsplit=1)[0]
        command = prefix.split(" saying ")[0]
        if _MSGOPTS.search(command):
            return ("message_options", "unsupported")
    return None


_AMPM = re.compile(r"\b(am|pm|a\.m\.|p\.m\.)\b", re.I)
_24H = re.compile(r"\b([01]?\d|2[0-3]):[0-5]\d\b")
_BARE_HOUR = re.compile(r"\bat\s+\d{1,2}(\s|$)", re.I)
_BAD_TZ = re.compile(r"\b(EST|EDT|PST|PDT|CST|CDT|MST|MDT)\b")
_GOOD_TZ = ("America/", "UTC", "GMT", "Europe/", "Asia/", "Australia/")


def datetime_disposition(when_text):
    """Heuristic exact-time gate for phone fixtures.

    Returns clarify_invalid when the phrase is ambiguous or unhandled,
    else None (exact enough for the fixture). Fixture-level only; the
    review card stays the runtime authority.
    """
    t = when_text or ""
    if not t.strip():
        return "clarify_missing"
    if _BAD_TZ.search(t) and not any(g in t for g in _GOOD_TZ):
        return "clarify_invalid"
    if _AMPM.search(t) or _24H.search(t):
        return None
    if _BARE_HOUR.search(t):
        return "clarify_invalid"
    return "clarify_invalid"


def disposition_for(entry, args, utterance, context_flags=None):
    """Deterministic expected disposition where the contract decides it.

    Returns (disposition, basis) or (None, None) when a teacher judgment
    is still required for the choice layer. context_flags may carry
    permission/cancel/interrupted/handoff state supplied by the fixture.
    """
    flags = context_flags or {}
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
    issues = contract_issues(entry, args or {})
    for field, code in issues:
        if code == "missing":
            return ("clarify_missing", f"required_field_missing_{field}")
        if code == "invalid":
            return ("clarify_invalid", f"field_invalid_{field}")
        if code == "unsupported":
            return ("clarify_invalid", f"unsupported_field_{field}")
    for spec in cap["arguments"]:
        if spec["kind"] == "datetime":
            v = (args or {}).get(spec["name"], "")
            d = datetime_disposition(v)
            if d:
                return (d, f"datetime_{d}_{spec['name']}")
    if flags.get("ambiguous_contact"):
        return ("resolve_ambiguity", "fixture_ambiguous_contact")
    if flags.get("failed_outcome"):
        return ("failed", "fixture_executor_failed")
    if flags.get("handoff_offline"):
        return ("failed", "fixture_handoff_unavailable")
    if confirmation(entry) == "always":
        return ("await_confirmation", "contract_confirmation_always")
    return ("execute_once", "contract_ready_deterministic_args")


def chunk_job_key(input_sha256, template_sha256, item_ids):
    """Stable identity for one label chunk: inputs + template + items."""
    return hashlib.sha256(
        f"{input_sha256}|{template_sha256}|{','.join(item_ids)}".encode()
    ).hexdigest()[:20]


def plan_chunks(item_hashes, done_hashes, chunk_size):
    """Absolute chunk plan over the full input, resumable by output.

    Returns [(start, [hashes])] for chunks with any hash missing from
    done_hashes. Starts never renumber when earlier chunks complete, so
    a settled call without durable output is replanned, never skipped.
    """
    plan = []
    for start in range(0, len(item_hashes), chunk_size):
        part = item_hashes[start:start + chunk_size]
        if any(h not in done_hashes for h in part):
            plan.append((start, part))
    return plan
