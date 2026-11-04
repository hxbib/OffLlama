"""Build the phone-action tranche inputs (no teacher labels here).

Inputs are source-grouped examples derived from the 38 compiled contracts
in docs/ACTION_CONTRACTS.json. Each row carries contract/version, the user
utterance, the Reflex decision type with its option mapping, typed
arguments and the deterministic expected disposition where the contract
decides it, plus provenance. Teacher letters are added later by the
authorized Glimmer teacher only. Deterministic dispositions are contract
semantics for evaluation, never LLM prose.

Grouping: rows sharing (contract, family, instance) are paraphrases of one
scenario instance and share group_id. Splits assign whole groups, never
rows. Run: python3 training/round3/phone_build.py
Outputs stay under training/round3/phone_* plus manifest/coverage JSON.
"""
import hashlib
import json
import random
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "training"))
sys.path.insert(0, str(ROOT / "training" / "local_teacher"))
import phone_contracts as PC

SEED = 20261104
LETTERS = "ABCDEFGH"

FIRST = ["Maya", "Leo", "Sam", "Priya", "Noah", "Zoe", "Ben", "Lena",
         "Omar", "Ines", "Karl", "Nina", "Theo", "Rosa", "Jae", "Mila"]
LAST = ["Patel", "Chen", "Ortiz", "Sharma", "Khan", "Novak", "Cole",
        "Fischer", "Haddad", "Garcia", "Weber", "Kim", "Larsen", "Reyes",
        "Park", "Novak"]
ROLES = ["coworker", "friend", "sister", "manager", "coach", "roommate",
         "landlord", "dentist", "neighbor", "professor"]
BODIES = ["I'm running late", "Can you bring the charger", "Dinner is at 8", "The train is delayed", "Please bring the documents", "I need a ride home", "Meeting confirmed for tomorrow", "Can we move to Friday", "I sent the file", "Call me when you land", "Happy anniversary", "The package arrived", "I booked the tickets", "Running errands, back soon", "Doctor said all clear", "Rent is due Friday",
          "See you at 7", "The meeting moved to 3",
          "Happy birthday", "I landed safely",
          "Please call when free", "Thanks for your help",
          "Running 10 minutes behind", "Did you get the file"]
PLACES = ["JFK Airport", "Hunter College", "the pharmacy on 5th",
          "Central Library", "Riverside Park", "the dentist office",
          "Union Square", "the train station"]
EVENT_TITLES = ["Dentist appointment", "Team standup", "Lunch with Leo",
                "Project review", "Yoga class", "1:1 with Priya"]
REMINDER_TITLES = ["buy milk", "call the vet", "take vitamins",
                   "water the plants", "submit the form", "pick up laundry"]
QUERIES = ["best ramen nearby", "how tall is the Empire State Building",
           "weather tomorrow", "train times to Boston"]
SHOWS = ["Severance", "Ted Lasso", "Silo", "Slow Horses"]
APPS = ["Spotify", "Camera", "Maps", "Notes", "Settings"]
NOWS = ["Fri 09:00", "Sat 14:30", "Mon 08:15", "Wed 19:40", "Thu 07:05"]

# Developer-template examples for option labels (Skills.swift + contracts).
# Provenance stays developer_template, never human gold.
EXAMPLES = {
    "imessage_send": "text Sam I'm running late",
    "email_compose": "email Dana the slides are ready",
    "instagram_dm": "dm sam on instagram saying congrats",
    "x_dm": "dm sam on x saying gg",
    "whatsapp_send": "whatsapp Leo that I landed",
    "call": "call Mom",
    "facetime": "facetime Leo",
    "uber_ride": "get me an uber to JFK",
    "instagram_autoreply": "reply to every reel with haha nice",
    "reminder_create": "remind me to buy milk tomorrow",
    "calendar_create": "put lunch with Leo on my calendar Friday at 1pm",
    "maps_directions": "directions to Hunter College",
    "web_search": "search the web for best ramen",
    "open_url": "open https://hunter.cuny.edu",
    "open_app": "open Spotify",
    "run_shortcut": "run my shortcut Morning Routine",
    "create_shortcut": "create a shortcut",
    "music_play": "play some music",
    "spotify_play": "play lofi on spotify",
    "appletv_play": "play Ted Lasso on apple tv",
    "alarm_create": "wake me at 6",
    "timer_start": "set a timer for 10 minutes",
    "notes_create": "make a note: wifi code is on the fridge",
    "photos_open": "show my photos",
    "flashlight_toggle": "turn on the flashlight",
    "focus_toggle": "turn on do not disturb",
    "low_power_toggle": "turn on low power mode",
    "weather": "what's the weather",
    "email_digest": "summarize my last 5 emails",
    "analyze_document": "analyze this document",
    "html_viz": "make a chart of these numbers",
    "translate": "translate good morning to Spanish",
    "summarize_text": "summarize what I just shared",
    "device_status": "how much battery do I have",
    "calendar_find": "when is my dentist appointment",
    "memory_recall": "what did I say my locker code was",
    "lookup_contact": "what's Tom's number",
    "alarmkit_schedule": "schedule an app alarm",
}


def h(s):
    return hashlib.sha256(s.encode()).hexdigest()


def group_id_for(contract_id, family, instance):
    return "pg-" + h(f"{contract_id}|{family}|{instance}")[:14]


def pick(rng, seq):
    return seq[rng.randrange(len(seq))]


def person(rng):
    return f"{pick(rng, FIRST)} {pick(rng, LAST)}"


def valid_args(contract_id, rng):
    """Deterministically plausible complete args for a contract."""
    p = person(rng)
    b = pick(rng, BODIES)
    table = {
        "imessage_send": {"contact": p, "body": b},
        "email_compose": {"contact": p, "subject": "Update", "body": b},
        "instagram_dm": {"contact": "sam_lee", "body": b},
        "x_dm": {"contact": "samlee", "body": b},
        "whatsapp_send": {"contact": p, "body": b},
        "call": {"contact": p},
        "facetime": {"contact": p},
        "uber_ride": {"place": pick(rng, PLACES)},
        "instagram_autoreply": {"trigger": "reel", "reply": "haha nice"},
        "reminder_create": {"title": pick(rng, REMINDER_TITLES),
                            "when": "tomorrow at 7:30 AM America/New_York"},
        "calendar_create": {"title": pick(rng, EVENT_TITLES),
                            "when": "Friday at 1:00 PM America/New_York"},
        "maps_directions": {"place": pick(rng, PLACES)},
        "web_search": {"query": pick(rng, QUERIES)},
        "open_url": {"url": "https://hunter.cuny.edu"},
        "open_app": {"app": pick(rng, APPS)},
        "run_shortcut": {"name": "Morning Routine", "text": ""},
        "create_shortcut": {},
        "music_play": {"query": "lofi beats"},
        "spotify_play": {"query": "lofi beats"},
        "appletv_play": {"show": pick(rng, SHOWS)},
        "alarm_create": {"time": "tomorrow at 6:30 AM America/New_York", "label": "Wake up"},
        "timer_start": {"duration": "10 minutes"},
        "notes_create": {"text": "Wifi code is on the fridge"},
        "photos_open": {},
        "flashlight_toggle": {},
        "focus_toggle": {},
        "low_power_toggle": {},
        "weather": {"place": "New York"},
        "email_digest": {"n": "5"},
        "analyze_document": {"document": "lease.pdf"},
        "html_viz": {"data": "rent 1200, food 400, transit 130"},
        "translate": {"text": "good morning", "target_language": "Spanish"},
        "summarize_text": {"text": "Long shared article about transit."},
        "device_status": {},
        "calendar_find": {"query": "dentist"},
        "memory_recall": {"query": "locker code"},
        "lookup_contact": {"contact": p},
        "alarmkit_schedule": {},
    }
    return dict(table.get(contract_id, {}))


UTTER = {
    "imessage_send": ["Text {contact} {body}", "Message {contact} saying {body}",
                      "Tell {contact} {body} by text"],
    "email_compose": ["Email {contact} {body}", "Send an email to {contact} saying {body}",
                      "Mail {contact}: {body}"],
    "instagram_dm": ["DM {contact} on Instagram saying {body}",
                     "Message {contact} on insta: {body}",
                     "Instagram DM {contact} {body}"],
    "x_dm": ["DM {contact} on X saying {body}", "Message {contact} on Twitter: {body}"],
    "whatsapp_send": ["WhatsApp {contact} {body}", "Send a WhatsApp to {contact}: {body}"],
    "call": ["Call {contact}", "Phone {contact}", "Ring {contact}"],
    "facetime": ["FaceTime {contact}", "Video call {contact}"],
    "uber_ride": ["Get me an Uber to {place}", "Request a ride to {place}"],
    "instagram_autoreply": ["Reply to every reel with {reply}",
                            "Whenever someone sends a reel say {reply}"],
    "reminder_create": ["Remind me to {title} {when}", "Create a reminder: {title}, {when}"],
    "calendar_create": ["Put {title} on my calendar {when}",
                        "Add a calendar event: {title}, {when}",
                        "Schedule {title} {when}"],
    "maps_directions": ["Directions to {place}", "Navigate to {place}",
                        "How do I get to {place}"],
    "web_search": ["Search the web for {query}", "Google {query}", "Look up online: {query}"],
    "open_url": ["Open {url}", "Go to {url}", "Open link {url}"],
    "open_app": ["Open {app}", "Launch {app}"],
    "run_shortcut": ["Run my Shortcut {name}", "Run shortcut {name}"],
    "create_shortcut": ["Create a shortcut for my morning routine", "Make a new Shortcut to text Maya when I leave", "Create a shortcut that opens Maps to work"],
    "music_play": ["Play some music", "Play {query}"],
    "spotify_play": ["Play {query} on Spotify", "Open Spotify and play {query}"],
    "appletv_play": ["Play {show} on Apple TV", "Put on {show}"],
    "alarm_create": ["Wake me at 6:30 AM", "Set an alarm for 7:30 AM"],
    "timer_start": ["Set a timer for {duration}", "Start a timer: {duration}"],
    "notes_create": ["Make a note: {text}", "Jot down: {text}"],
    "photos_open": ["Show my photos", "Open the camera roll"],
    "flashlight_toggle": ["Toggle the flashlight", "Toggle flashlight"],
    "focus_toggle": ["Toggle Do Not Disturb", "Toggle focus mode"],
    "low_power_toggle": ["Toggle Low Power Mode", "Toggle battery saver"],
    "weather": ["What's the weather in {place}", "Will it rain tomorrow in {place}"],
    "email_digest": ["Summarize my last {n} emails", "Summarize my recent emails"],
    "analyze_document": ["Analyze this document", "Summarize this PDF"],
    "html_viz": ["Make a chart of these numbers: {data}", "Visualize this data: {data}"],
    "translate": ["Translate {text} to {target_language}", "How do you say {text} in {target_language}"],
    "summarize_text": ["Summarize what I just shared", "TLDR this"],
    "device_status": ["How much battery do I have left on this phone", "How much storage is left on this phone", "Check this phone battery and storage"],
    "calendar_find": ["When is my {query} appointment", "What's on my calendar"],
    "memory_recall": ["What did I say my {query} was", "Recall my {query}"],
    "lookup_contact": ["What's {contact}'s number", "Look up {contact}"],
    "alarmkit_schedule": ["Schedule an app alarm for 6 AM", "Set an in-app alarm"],
}


def fill(template, args):
    out = template
    for k, v in args.items():
        out = out.replace("{" + k + "}", str(v))
    return re.sub(r"\{[^}]+\}", "", out).strip()


def ctx_for(utterance, rng, extra=None):
    parts = [f"Now: {pick(rng, NOWS)}", "User location: home",
             f"Network: {pick(rng, ['online', 'online', 'offline'])}"]
    if extra:
        parts.extend(extra)
    parts.append(f"User: {utterance}")
    return "\n".join(parts)


def skill_candidates(target_id, contracts, rng):
    titles = {}
    for cid, entry in contracts.items():
        titles[cid] = PC.option_label(entry["capability"]["title"],
                                      EXAMPLES.get(cid, ""))
    pool = [c for c in contracts
            if c != target_id and PC.availability(contracts[c]) != "notWired"]
    rng2 = random.Random(h(f"cand|{target_id}|{rng.random()}")[:12])
    distract = rng2.sample(pool, 6)
    labels = [titles[target_id]] + [titles[d] for d in distract]
    rng2.shuffle(labels)
    return labels


def make_row(idx, contract_id, family, reflex_type, utterance, context,
             candidates, args, flags, contracts, instance):
    entry = contracts[contract_id]
    oset = PC.extended_get_set(reflex_type, candidates)
    disp, basis = PC.disposition_for(entry, args, utterance, flags)
    return {
        "id": f"phone-{idx:05d}",
        "group_id": group_id_for(contract_id, family, instance),
        "contract_id": contract_id,
        "contract_version": entry["capability"]["version"],
        "contract_availability": PC.availability(entry),
        "family": family,
        "reflex_type": reflex_type,
        "utterance": utterance,
        "context": context,
        "candidates": candidates,
        "option_ids": PC.option_ids_for(oset),
        "fallback_id": oset["fallback"],
        "typed_arguments": args,
        "expected_disposition": disp,
        "deterministic_basis": basis,
        "provenance": {
            "source": "phone_contract_template_v1",
            "template_family": family,
            "generation_origin": "developer_contract_template",
            "note": "Developer contract template. Not human gold, not iPhone traces.",
        },
        "label_status": "needs_teacher",
    }


def build():
    contracts = PC.load_contracts()
    rng = random.Random(SEED)
    rows = []
    idx = 0

    def add(*a, **kw):
        nonlocal idx
        idx += 1
        rows.append(make_row(idx, *a, **kw))

    ready = [c for c in contracts if PC.availability(contracts[c]) != "notWired"]
    # --- skillPick: valid / missing / invalid per ready contract ---
    for cid in ready:
        entry = contracts[cid]
        req = [a for a in entry["capability"]["arguments"] if a["required"]]
        for inst in range(30):
            base = valid_args(cid, rng)
            utts = UTTER.get(cid, [f"Use {cid}"])
            for v, t in enumerate(utts[:3]):
                u = fill(t, base)
                add(cid, "valid_complete", "skillPick", u,
                    ctx_for(u, rng), skill_candidates(cid, contracts, rng),
                    base, {}, contracts, f"valid-{inst}")
        for inst in range(14):
            base = valid_args(cid, rng)
            if not req:
                continue
            miss = dict(base)
            miss.pop(req[0]["name"], None)
            utts = UTTER.get(cid, [""])
            u = fill(utts[0], {**base, req[0]["name"]: ""}).strip()
            if not u or u == fill(utts[0], base):
                u = f"Use {entry['capability']['title']}"
            # Keep utterance natural: drop the value text is approximated by
            # the template without that slot; disposition carries the truth.
            add(cid, "missing_required", "skillPick", u,
                ctx_for(u, rng), skill_candidates(cid, contracts, rng),
                miss, {}, contracts, f"miss-{inst}")
            add(cid, "missing_required", "skillPick", u,
                ctx_for(u, rng), skill_candidates(cid, contracts, rng),
                miss, {}, contracts, f"miss-{inst}")
        for inst in range(14):
            base = valid_args(cid, rng)
            bad = dict(base)
            changed = False
            for spec in entry["capability"]["arguments"]:
                n, k = spec["name"], spec["kind"]
                if k == "handle":
                    bad[n] = "not a handle!"; changed = True; break
                if k == "url":
                    bad[n] = "htp:/bad url"; changed = True; break
                if k == "duration":
                    bad[n] = "25 hours"; changed = True; break
                if k == "number":
                    bad[n] = "500"; changed = True; break
                if k == "datetime":
                    bad[n] = "tomorrow at 7 EST"; changed = True; break
            if not changed:
                continue
            utts = UTTER.get(cid, [""])
            u = fill(utts[0], bad)
            add(cid, "invalid_field", "skillPick", u,
                ctx_for(u, rng), skill_candidates(cid, contracts, rng),
                bad, {}, contracts, f"inv-{inst}")
            add(cid, "invalid_field", "skillPick", u,
                ctx_for(u, rng), skill_candidates(cid, contracts, rng),
                bad, {}, contracts, f"inv-{inst}")

    # Unavailable contract: ask is the only honest skillPick answer.
    for inst in range(6):
        u = pick(rng, UTTER["alarmkit_schedule"])
        add("alarmkit_schedule", "unavailable", "skillPick", u,
            ctx_for(u, rng),
            skill_candidates("reminder_create", contracts, rng),
            {}, {}, contracts, f"unavail-{inst}")
        add("alarmkit_schedule", "unavailable", "skillPick", u,
            ctx_for(u, rng),
            skill_candidates("alarm_create", contracts, rng),
            {}, {}, contracts, f"unavail-{inst}")

    # --- toggle vs set-state (guard: only "toggle" phrasing is supported) ---
    for cid in ("flashlight_toggle", "focus_toggle", "low_power_toggle"):
        names = {"flashlight_toggle": "flashlight",
                 "focus_toggle": "Do Not Disturb",
                 "low_power_toggle": "Low Power Mode"}
        for inst in range(10):
            u = f"Turn on the {names[cid]}"
            add(cid, "toggle_vs_setstate", "skillPick", u,
                ctx_for(u, rng), skill_candidates(cid, contracts, rng),
                {}, {}, contracts, f"toggle-{inst}")
            u2 = f"Turn off the {names[cid]}"
            add(cid, "toggle_vs_setstate", "skillPick", u2,
                ctx_for(u2, rng), skill_candidates(cid, contracts, rng),
                {}, {}, contracts, f"toggle-{inst}")

    # --- recurrence / unsupported options on timed contracts ---
    for cid in ("reminder_create", "calendar_create", "alarm_create"):
        for inst in range(10):
            base = valid_args(cid, rng)
            u = f"Remind me to {base.get('title', 'call')} every Monday" if cid == "reminder_create" \
                else f"Schedule {base.get('title', 'meeting')} every Monday" if cid == "calendar_create" \
                else "Set an alarm every Monday at 7 AM"
            add(cid, "recurrence_unsupported", "timing", u,
                ctx_for(u, rng), None, base, {}, contracts, f"recur-{inst}")
            add(cid, "recurrence_unsupported", "timing", u,
                ctx_for(u, rng), None, base, {}, contracts, f"recur-{inst}")
    for inst in range(14):
        u = "Remind me when I arrive at the office"
        add("reminder_create", "trigger_unsupported", "timing", u,
            ctx_for(u, rng), None, {"title": "call", "when": "when I arrive"},
            {}, contracts, f"trig-{inst}")
        u2 = "Add an all-day event: Company holiday"
        add("calendar_create", "trigger_unsupported", "timing", u2,
            ctx_for(u2, rng), None, {"title": "Company holiday", "when": "all-day"},
            {}, contracts, f"trig-{inst}")

    # --- AM/PM and timezone timing rows ---
    for inst in range(54):
        u = pick(rng, ["Remind me tomorrow at 7", "Remind me Friday at 8",
                       "Call me tomorrow at 6"])
        cid = "reminder_create" if "Remind" in u else "call"
        add(cid, "ampm_timezone", "timing", u, ctx_for(u, rng), None,
            {"title": "x", "when": "tomorrow at 7"}, {}, contracts, f"ampm-{inst}")
        u2 = pick(rng, ["Remind me tomorrow at 7 EST",
                        "Meeting tomorrow at 3 PST"])
        add("reminder_create", "ampm_timezone", "timing", u2, ctx_for(u2, rng),
            None, {"title": "x", "when": "tomorrow at 7 EST"}, {},
            contracts, f"ampm-{inst}")

    # --- contactPick: exact / ambiguous / method ---
    contact_contracts = ["imessage_send", "email_compose", "whatsapp_send",
                         "call", "facetime", "lookup_contact"]
    for inst in range(120):
        first = pick(rng, FIRST)
        role = pick(rng, ROLES)
        others = [f"{first} {pick(rng, LAST)} ({pick(rng, ROLES)})" for _ in range(2)]
        target = f"{first} {pick(rng, LAST)} ({role})"
        cands = others + [target]
        rng.shuffle(cands)
        verb = pick(rng, ["Text", "Message", "Call", "Email"])
        u = f"{verb} my {role} {first}: {pick(rng, BODIES)}"
        add(contact_contracts[inst % len(contact_contracts)],
            "contact_exact", "contactPick", u, ctx_for(u, rng), cands,
            {"contact": target}, {}, contracts, f"cexact-{inst}")
    for inst in range(96):
        first = pick(rng, FIRST)
        cands = [f"{first} {pick(rng, LAST)} ({pick(rng, ROLES)})",
                 f"{first} {pick(rng, LAST)} ({pick(rng, ROLES)})"]
        rng.shuffle(cands)
        u = f"Text {first}: {pick(rng, BODIES)}"
        add(contact_contracts[inst % len(contact_contracts)],
            "contact_ambiguous", "contactPick", u, ctx_for(u, rng), cands,
            {"contact": first}, {"ambiguous_contact": True},
            contracts, f"camb-{inst}")
    for inst in range(96):
        name = person(rng)
        cands = [f"{name} (mobile +1 212-555-0147)",
                 f"{name} (email {name.split()[0].lower()}@example.com)",
                 f"{name} (home +1 212-555-0199)"]
        rng.shuffle(cands)
        method = pick(rng, ["mobile", "email"])
        u = (f"Text {name} on her mobile: {pick(rng, BODIES)}" if method == "mobile"
             else f"Email {name}: {pick(rng, BODIES)}")
        add("imessage_send" if method == "mobile" else "email_compose",
            "contact_method", "contactPick", u, ctx_for(u, rng), cands,
            {"contact": name}, {}, contracts, f"cmeth-{inst}")

    # --- eventPick ---
    for inst in range(96):
        t = pick(rng, EVENT_TITLES)
        cands = [pick(rng, EVENT_TITLES), pick(rng, EVENT_TITLES),
                 f"{t} (Wed 10am)"]
        rng.shuffle(cands)
        u = f"Move my {t.lower()} to next week"
        add("calendar_create", "event_pick", "eventPick", u,
            ctx_for(u, rng), cands, {}, {}, contracts, f"event-{inst}")
        u2 = "Move that meeting"
        add("calendar_create", "event_pick", "eventPick", u2,
            ctx_for(u2, rng), cands, {}, {"ambiguous_contact": True},
            contracts, f"event-{inst}")

    # --- confirmBeforeAct with phone planned actions ---
    safe = ["create calendar event 'Gym' Thu 6pm",
            "create reminder 'buy milk' tomorrow",
            "look up contact Maya Patel"]
    risky = ["send text to Maya Patel", "delete all events next week",
             "request Uber to JFK Airport", "email professor with attachment"]
    for inst in range(60):
        a = pick(rng, safe)
        u = f"Planned action: {a}"
        add("reminder_create", "confirm_safe", "confirmBeforeAct", a,
            f"Now: {pick(rng, NOWS)}\nPlanned action: {a}", None, {},
            {}, contracts, f"conf-{inst}")
        a2 = pick(rng, risky)
        add("imessage_send", "confirm_risky", "confirmBeforeAct", a2,
            f"Now: {pick(rng, NOWS)}\nPlanned action: {a2}", None, {},
            {}, contracts, f"conf-{inst}")

    # --- permissions / cancellation / interrupted / request-bound / handoff ---
    for inst in range(42):
        u = f"Text {person(rng)} {pick(rng, BODIES)}"
        add("imessage_send", "permission", "skillPick", u,
            ctx_for(u, rng, ["Contacts access: denied"]),
            skill_candidates("imessage_send", contracts, rng),
            valid_args("imessage_send", rng),
            {"permission_denied": True}, contracts, f"perm-{inst}")
        u2 = f"Add {pick(rng, EVENT_TITLES)} Friday at 1 PM"
        add("calendar_create", "permission", "skillPick", u2,
            ctx_for(u2, rng, ["Calendar access: denied"]),
            skill_candidates("calendar_create", contracts, rng),
            valid_args("calendar_create", rng),
            {"permission_denied": True}, contracts, f"perm-{inst}")
    for inst in range(54):
        u = pick(rng, ["Never mind, don't send that", "Cancel, forget it",
                       "Stop, don't do that"])
        add("imessage_send", "cancellation", "skillPick", u,
            ctx_for(u, rng), skill_candidates("imessage_send", contracts, rng),
            {}, {"cancel": True}, contracts, f"cancel-{inst}")
        u2 = "Actually cancel that reminder"
        add("reminder_create", "cancellation", "skillPick", u2,
            ctx_for(u2, rng), skill_candidates("reminder_create", contracts, rng),
            {}, {"cancel": True}, contracts, f"cancel-{inst}")
    for inst in range(54):
        u = f"Text {person(rng)} {pick(rng, BODIES)}"
        ctx = ctx_for(u, rng, ["Previous attempt: interrupted, outcome unknown"])
        add("imessage_send", "interrupted", "skillPick", u, ctx,
            skill_candidates("imessage_send", contracts, rng),
            valid_args("imessage_send", rng),
            {"interrupted_unknown": True}, contracts, f"intr-{inst}")
        u2 = f"Remind me to {pick(rng, REMINDER_TITLES)} tomorrow at 8 AM"
        ctx2 = ctx_for(u2, rng, ["Previous attempt: interrupted, outcome unknown"])
        add("reminder_create", "interrupted", "skillPick", u2, ctx2,
            skill_candidates("reminder_create", contracts, rng),
            valid_args("reminder_create", rng),
            {"interrupted_unknown": True}, contracts, f"intr-{inst}")
    for inst in range(54):
        u = pick(rng, ["Analyze this document", "Summarize what I just shared"])
        cid = "analyze_document" if "Analyze" in u else "summarize_text"
        add(cid, "request_bound", "skillPick", u,
            ctx_for(u, rng, ["Shared document: none for this request"]),
            skill_candidates(cid, contracts, rng), {},
            {}, contracts, f"reqb-{inst}")
        u2 = "Summarize the document from my other request"
        add("analyze_document", "request_bound", "skillPick", u2,
            ctx_for(u2, rng, ["Shared document: bound to a different request"]),
            skill_candidates("analyze_document", contracts, rng), {},
            {}, contracts, f"reqb-{inst}")
    for inst in range(42):
        u = f"Play {pick(rng, SHOWS)} on Apple TV"
        add("appletv_play", "handoff", "skillPick", u,
            ctx_for(u, rng, ["Network: offline"]),
            skill_candidates("appletv_play", contracts, rng),
            valid_args("appletv_play", rng),
            {"handoff_offline": True}, contracts, f"hand-{inst}")
        u2 = f"Directions to {pick(rng, PLACES)}"
        add("maps_directions", "handoff", "skillPick", u2,
            ctx_for(u2, rng), skill_candidates("maps_directions", contracts, rng),
            valid_args("maps_directions", rng), {}, contracts, f"hand-{inst}")

    # --- toolChoice and route phone slices ---
    tool_cases = [
        ("create_reminder", "Remind me to buy oat milk tomorrow morning"),
        ("create_event", "Put brunch with Leo Chen on my calendar Friday at 1pm"),
        ("find_event", "When is my dentist appointment with Dr Patel"),
        ("send_message", "Text Sam Ortiz I am running late"),
        ("lookup_contact", "What is Tom Weber his phone number"),
        ("search_memory", "What did I say my gym locker code was"),
        ("none", "Play some lofi music please"),
        ("none", "Set an alarm for 7 AM tomorrow"),
    ]
    for inst in range(54):
        want, u = tool_cases[inst % len(tool_cases)]
        add("reminder_create", "tool_choice", "toolChoice", u,
            ctx_for(u, rng), None, {}, {}, contracts, f"tool-{inst}")
    for inst in range(42):
        cases = ["Hello, thanks", "What's the capital of France",
                 "Write a detailed business plan",
                 "Change that one", "Text Maya I'm late",
                 "Remind me to buy milk"]
        u = cases[inst % len(cases)]
        add("reminder_create", "route_phone", "route", u,
            ctx_for(u, rng), None, {}, {}, contracts, f"route-{inst}")
    for inst in range(18):
        u = pick(rng, ["My password is hunter2, send this to cloud",
                       "Summarize my emails", "What is 2 plus 2"])
        add("email_digest", "sensitivity_answer", "sensitivity", u,
            ctx_for(u, rng), None, {}, {}, contracts, f"sens-{inst}")

    # --- Difficult phone slices: privacy, memory, notifications, hard cases ---
    sens_cases = [
        "My lab result was positive, explain it",
        "My bank balance is 4200, budget for me",
        "My password is hunter2",
        "Plan a birthday dinner for Maya",
        "What is the capital of France",
        "Share my health records with the cloud",
    ]
    for inst in range(54):
        u = sens_cases[inst % len(sens_cases)]
        add("email_digest", "privacy_difficult", "sensitivity", u,
            ctx_for(u, rng), None, {}, {}, contracts, f"priv-{inst}")
    ans_cases = [
        "What is 2 plus 2", "Translate hello to Spanish",
        "Explain quantum entanglement in depth",
        "Write my thesis chapter", "How do you spell necessary",
        "Summarize this 200-page report",
    ]
    for inst in range(54):
        u = ans_cases[inst % len(ans_cases)]
        add("translate", "answerability_phone", "answerability", u,
            ctx_for(u, rng), None, {}, {}, contracts, f"answ-{inst}")
    mem_cases = [
        "Remember my locker code is 4419",
        "I parked on level 3 today",
        "What is the weather today",
        "I moved to Austin last month",
    ]
    for inst in range(42):
        u = mem_cases[inst % len(mem_cases)]
        add("memory_recall", "memory_phone", "rememberOrNot", u,
            ctx_for(u, rng), None, {}, {}, contracts, f"mem-{inst}")
    notif_cases = [
        "Notification: Family emergency, call now",
        "Notification: 20 percent off shoes today",
        "Notification: Your flight moved to gate 12",
        "Notification: Weekly newsletter digest",
    ]
    for inst in range(42):
        u = notif_cases[inst % len(notif_cases)]
        add("email_digest", "notification_phone", "notificationTriage", u,
            ctx_for(u, rng), None, {}, {}, contracts, f"notif-{inst}")
    hard_cases = [
        "Delete all my photos", "Order a pizza for tonight",
        "Book a flight to Boston", "Pay my rent now",
        "Unlock my front door", "Water my plants while away",
    ]
    for inst in range(54):
        u = hard_cases[inst % len(hard_cases)]
        add("photos_open", "hard_negative", "skillPick", u,
            ctx_for(u, rng),
            skill_candidates("reminder_create", contracts, rng),
            {}, {"ambiguous_contact": True}, contracts, f"hard-{inst}")
    for inst in range(54):
        u = f"Text {person(rng)} {pick(rng, BODIES)}"
        ctx = ctx_for(u, rng, ["Executor result: failed, no effect committed"])
        add("imessage_send", "recovery_failed", "skillPick", u, ctx,
            skill_candidates("imessage_send", contracts, rng),
            valid_args("imessage_send", rng),
            {"failed_outcome": True}, contracts, f"rec-{inst}")
    for inst in range(54):
        u = pick(rng, ["Remind me Feb 30 at 7", "Meeting yesterday at 3",
                       "Timer for 0 minutes", "Timer for 30 hours"])
        cid = "timer_start" if "Timer" in u else "reminder_create"
        args = ({"duration": "0 minutes"} if "0 minutes" in u
                else {"duration": "30 hours"} if "30 hours" in u
                else {"title": "x", "when": "Feb 30 at 7"})
        add(cid, "time_difficult", "timing" if cid == "reminder_create" else "skillPick",
            u, ctx_for(u, rng),
            None if cid == "reminder_create" else skill_candidates(cid, contracts, rng),
            args, {}, contracts, f"tdiff-{inst}")

    return rows, contracts


def assign_splits(rows):
    groups = {}
    for r in rows:
        groups.setdefault(r["group_id"], []).append(r)
    train_g, dev_g, cal_g = set(), set(), set()
    for gid in sorted(groups):
        v = int(h(gid)[:8], 16) % 100
        if v < 70:
            train_g.add(gid)
        elif v < 85:
            dev_g.add(gid)
        else:
            cal_g.add(gid)
    # Guarantee every contract keeps train groups.
    by_contract = defaultdict(set)
    for r in rows:
        by_contract[r["contract_id"]].add(r["group_id"])
    moved = 0
    for cid, gids in by_contract.items():
        if not (gids & train_g):
            cand = sorted(gids & (dev_g | cal_g))[0]
            dev_g.discard(cand); cal_g.discard(cand); train_g.add(cand)
            moved += 1
    for r in rows:
        r["split"] = ("train" if r["group_id"] in train_g
                      else "dev" if r["group_id"] in dev_g else "calfit")
    return {"groups": len(groups), "train_groups": len(train_g),
            "dev_groups": len(dev_g), "calfit_groups": len(cal_g),
            "moved_for_coverage": moved}


def _core_group_key(context):
    lines = [l for l in context.splitlines()
             if not re.match(r"^(Now:|User location:|Network:)\s", l.strip())]
    return "g" + hashlib.sha256(
        __import__("dedupe").norm("\n".join(lines).strip()).encode()
    ).hexdigest()[:15]


def main():
    rows, contracts = build()
    # Decontaminate before freezing: drop held-out group collisions and
    # eval near-duplicates. Counts land in the manifest.
    import dedupe as D
    held = set()
    for split in ("dev", "calfit", "report"):
        for r in [json.loads(l) for l in
                  (HERE / f"data_{split}.jsonl").read_text().splitlines() if l.strip()]:
            held.add(r["group_id"])
    before = len(rows)
    rows = [r for r in rows if _core_group_key(r["context"]) not in held]
    drop_held = before - len(rows)
    kept, dropped_eval = D.check(
        [{"id": r["id"], "context": r["context"]} for r in rows], D.eval_items())
    drop_ids = {d["id"] for d in dropped_eval}
    rows = [r for r in rows if r["id"] not in drop_ids]
    for i, r in enumerate(rows, 1):
        r["id"] = f"phone-{i:05d}"
    stats = assign_splits(rows)
    stats["dropped_heldout_group"] = drop_held
    stats["dropped_eval_dedupe"] = len(drop_ids)
    rows.sort(key=lambda r: r["id"])
    out_all = HERE / "phone_inputs_all.jsonl"
    out_all.write_text("".join(json.dumps(r) + "\n" for r in rows))
    splits = {}
    for split in ("train", "dev", "calfit"):
        part = [r for r in rows if r["split"] == split]
        p = HERE / f"phone_inputs_{split}.jsonl"
        p.write_text("".join(json.dumps(r) + "\n" for r in part))
        splits[split] = {
            "file": p.name, "rows": len(part),
            "groups": len({r["group_id"] for r in part}),
            "sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
            "by_reflex": dict(Counter(r["reflex_type"] for r in part)),
            "by_family": dict(Counter(r["family"] for r in part)),
        }
    cov = {}
    for cid in sorted(contracts):
        cov[cid] = {}
        for split in ("train", "dev", "calfit", "all"):
            part = rows if split == "all" else [r for r in rows if r["split"] == split]
            sub = [r for r in part if r["contract_id"] == cid]
            cov[cid][split] = {"rows": len(sub),
                               "groups": len({r["group_id"] for r in sub})}
        cov[cid]["availability"] = PC.availability(contracts[cid])
        cov[cid]["reflex_types"] = sorted({r["reflex_type"] for r in rows
                                           if r["contract_id"] == cid})
        cov[cid]["dispositions"] = dict(Counter(
            str(r["expected_disposition"]) for r in rows
            if r["contract_id"] == cid))
    manifest = {
        "builder": "training/round3/phone_build.py",
        "seed": SEED,
        "contracts_file": "docs/ACTION_CONTRACTS.json",
        "contracts_sha256": hashlib.sha256(
            (ROOT / "docs" / "ACTION_CONTRACTS.json").read_bytes()).hexdigest(),
        "contracts_count": len(contracts),
        "rows": len(rows),
        "all_sha256": hashlib.sha256(out_all.read_bytes()).hexdigest(),
        "split_stats": stats,
        "splits": splits,
        "by_reflex_all": dict(Counter(r["reflex_type"] for r in rows)),
        "by_family_all": dict(Counter(r["family"] for r in rows)),
        "by_disposition_all": dict(Counter(str(r["expected_disposition"]) for r in rows)),
        "note": "Developer contract templates. Not human gold, not iPhone traces. "
                "Teacher letters come only from Muse Glimmer (bf16) via phone_label.",
    }
    (HERE / "phone_manifest.json").write_text(json.dumps(manifest, indent=2))
    (HERE / "phone_coverage.json").write_text(json.dumps(cov, indent=2))
    print(json.dumps({"rows": len(rows), **stats,
                      "by_reflex": manifest["by_reflex_all"]}, indent=1))


if __name__ == "__main__":
    main()
