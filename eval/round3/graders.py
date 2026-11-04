"""Deterministic graders for the round-3 phone benchmark.

Four layers are scored separately and never averaged into one number:
  L1 choice       route / tool / skill selection (letter or skill id)
  L2 slots        argument binding for the chosen action
  L3 feasibility  permission, confirmation, and offline expectations
  L4 outcome      fake-executor effects, refusal no-effect, and recovery

L4 uses an in-memory fake executor. A pass means the planned effect
matches the fixture contract. It is not device success: nothing here
touches EventKit, Contacts, Messages, or a real Shortcut, and reports
must say so. Real contract behaviour stays covered by the existing
PocketCore tests (SkillsTests, AssistantTests); these graders check
benchmark fixtures against the same expectations, they do not replace
those tests and do not mirror app internals beyond the public fixture
schema that the parent contract task will supply.
"""
import json, math, re
from pathlib import Path

# Action families supported today (executor tools + registry skills).
# The parent contract manifest will refine this list; families with no
# fixture coverage must be reported as NOT MEASURED, never dropped.
EXECUTOR_TOOLS = ["send_message", "send_email", "create_reminder",
                  "create_event", "find_event", "lookup_contact", "search_memory"]
HANDOFF_FAMILIES = ["instagram_dm", "x_dm", "whatsapp_send", "alarm_create",
                    "timer_start", "appletv_play", "open_app", "run_shortcut",
                    "create_shortcut", "flashlight_toggle", "focus_toggle",
                    "low_power_toggle", "weather", "notes_create"]
NATIVE_FAMILIES = ["reminder_create", "calendar_create", "calendar_find",
                   "call", "facetime", "maps_directions", "uber_ride",
                   "web_search", "open_url", "music_play", "spotify_play",
                   "photos_open", "analyze_document", "html_viz", "translate",
                   "summarize_text", "device_status", "memory_recall",
                   "email_compose", "email_digest", "imessage_send",
                   "instagram_autoreply"]
ALL_FAMILIES = sorted(set(EXECUTOR_TOOLS + HANDOFF_FAMILIES + NATIVE_FAMILIES))


def norm_text(s):
    return re.sub(r"\s+", " ", str(s).strip().lower())


def grade_choice(pred, gold):
    """L1: exact choice match. pred/gold are option ids or skill ids."""
    if gold is None:
        return None  # unlabeled: caller must exclude, never score as wrong
    return norm_text(pred or "") == norm_text(gold)


def grade_slots(pred_args, gold_args):
    """L2: per-slot exact match after normalization.

    Returns (all_match, per_slot dict). Timezone and contact-method
    slots are ordinary keys here; fixtures name them explicitly
    (e.g. timezone, method) so a wrong zone fails like any slot.
    Missing required slot = mismatch. Extra predicted slots ignored
    only when the fixture marks them optional.
    """
    pred_args = pred_args or {}; gold_args = gold_args or {}
    per = {}
    for k, gv in gold_args.items():
        pv = pred_args.get(k)
        per[k] = pv is not None and norm_text(pv) == norm_text(gv)
    return (all(per.values()) if per else True), per


def grade_feasibility(fixture, decision):
    """L3: deterministic expectations from the fixture contract.

    fixture keys: requires_permission (str|None), permission_granted
    (bool), requires_confirmation (bool), confirmed (bool),
    offline_capable (bool), network (online|offline).
    decision keys: attempted (bool), asked_confirmation (bool),
    proceeded_without_permission (bool).
    """
    checks = {}
    if fixture.get("requires_permission") and not fixture.get("permission_granted", True):
        checks["blocked_without_permission"] = not decision.get("attempted", False)
    if fixture.get("requires_confirmation"):
        checks["confirmation_requested"] = bool(decision.get("asked_confirmation")) or not decision.get("attempted", False)
    if fixture.get("network") == "offline" and not fixture.get("offline_capable", True):
        checks["no_offline_attempt"] = not decision.get("attempted", False)
    return checks


class FakeExecutor:
    """In-memory effect log. Records intended effects only."""

    def __init__(self):
        self.effects = []
        self.state = {}

    def apply(self, action, args, *, permission_granted=True, confirmed=True,
              requires_confirmation=False, fail_first=False):
        if not permission_granted:
            return {"status": "permission_denied", "effect": None}
        if requires_confirmation and not confirmed:
            return {"status": "awaiting_confirmation", "effect": None}
        if fail_first and not self.state.get("_failed_once"):
            self.state["_failed_once"] = True
            return {"status": "transient_failure", "effect": None}
        eff = {"action": action, "args": dict(args or {})}
        self.effects.append(eff)
        return {"status": "committed", "effect": eff}


def grade_outcome(fixture, trace):
    """L4: refusal leaves no effect; commit matches; recovery is explicit.

    fixture: expected_status, expected_effect (dict|None),
             allow_retry (bool)
    trace: list of FakeExecutor result dicts in order.
    """
    checks = {}
    statuses = [t.get("status") for t in trace]
    effects = [t.get("effect") for t in trace if t.get("effect")]
    exp = fixture.get("expected_status")
    if exp in ("permission_denied", "awaiting_confirmation"):
        checks["no_effect_on_refusal"] = len(effects) == 0 and exp in statuses
    if exp == "committed":
        want = fixture.get("expected_effect") or {}
        got = effects[-1] if effects else {}
        checks["effect_matches"] = got.get("action") == want.get("action") and all(
            norm_text(got.get("args", {}).get(k, "")) == norm_text(v)
            for k, v in (want.get("args") or {}).items())
        if fixture.get("allow_retry"):
            checks["recovery_after_failure"] = ("transient_failure" in statuses[:-1]
                                                 and statuses[-1] == "committed")
    return checks


def wilson(errors, n, z=1.959964):
    """Two-sided 95% Wilson interval for an error proportion."""
    if n == 0:
        return (0.0, 1.0)
    p = errors / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))


def group_errors(rows):
    """Collapse duplicated rows to source groups.

    rows: dicts with group_id, error (bool). Returns (groups, errors)
    where a group counts once; a group with mixed outcomes counts as
    an error (conservative, stated in the protocol).
    """
    by = {}
    for r in rows:
        by.setdefault(r["group_id"], []).append(bool(r["error"]))
    errs = sum(1 for v in by.values() if any(v))
    return len(by), errs


def load_jsonl(path):
    return [json.loads(l) for l in Path(path).read_text().splitlines() if l.strip()]


if __name__ == "__main__":
    # Smoke assertions (also covered by data_test_validation.py).
    assert grade_choice("tool", "tool") is True
    assert grade_choice(None, "tool") is False
    assert grade_choice("x", None) is None
    ok, per = grade_slots({"when": "Fri 7pm", "timezone": "America/New_York"},
                          {"when": "fri 7pm", "timezone": "America/New_York"})
    assert ok and all(per.values())
    ok, _ = grade_slots({"when": "Fri 7pm"}, {"when": "Fri 7pm", "timezone": "UTC"})
    assert not ok
    fx = FakeExecutor()
    r = fx.apply("send_message", {"to": "Sam"}, permission_granted=False)
    assert grade_outcome({"expected_status": "permission_denied"},
                         [r])["no_effect_on_refusal"]
    fx2 = FakeExecutor()
    t = [fx2.apply("create_event", {"title": "Lunch"}, fail_first=True),
         fx2.apply("create_event", {"title": "Lunch"})]
    c = grade_outcome({"expected_status": "committed", "allow_retry": True,
                       "expected_effect": {"action": "create_event", "args": {"title": "Lunch"}}}, t)
    assert c["effect_matches"] and c["recovery_after_failure"]
    assert wilson(0, 100)[1] > 0.02  # zero errors in 100 still allows >2%
    print("graders smoke ok")
