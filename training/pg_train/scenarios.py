"""Seeded synthetic personal-assistant scenarios, one per decision type. No gold labels are trusted from here:
labels come from teachers. `hint` is the generator's intended answer, used only for sanity stats."""
import argparse, json, random

NAMES = ["Maya", "Sam", "Priya", "Diego", "Aisha", "Tom", "Lena", "Kenji", "Fatima", "Noah", "Zoe", "Omar"]
REL = ["brother", "sister", "coworker", "dentist", "landlord", "mom", "dad", "manager", "roommate", "coach"]
PLACES = ["Trader Joe's", "the office", "the gym", "Whole Foods", "home", "CVS pharmacy", "the airport", "Mom's house"]
ITEMS = ["oat milk", "eggs", "batteries", "dish soap", "coffee beans", "ibuprofen", "printer paper"]
TIMES = ["at 8pm", "tomorrow at 9am", "in 20 minutes", "on Friday at noon", "next Monday", "tonight"]
TASKS = ["take my vitamins", "call the plumber", "pay rent", "submit the expense report", "water the plants", "book the vet"]
HARD = ["Compare index funds vs. paying down my 6% student loan and recommend a plan",
        "Draft a 400-word cover letter for a product design role at a fintech startup",
        "Explain how mRNA vaccines train the immune system, with an analogy",
        "Plan a 5-day Lisbon itinerary for two on a mid budget with one rest day",
        "What are the trade-offs between Postgres and SQLite for a mobile-first app?",
        "Help me negotiate a 15% raise: give me a script and likely objections"]
SIMPLE = ["Thanks!", "Good morning", "What's 15% of 80?", "Rephrase this nicer: 'send it now'", "Say hi to me in Spanish", "How do you spell necessary?"]
VAGUE = ["Move it", "Do the thing from before", "Change that one", "Send it", "Make it later"]
FACTS = ["I'm allergic to shellfish.", "I moved to Austin last month.", "My partner's name is Jordan.", "I'm vegetarian now.",
         "Lena's birthday is March 4th.", "I work at Northwind as a nurse.", "I'm out of coffee beans."]
NONFACTS = ["What time is it?", "Ok sounds good", "lol", "Can you repeat that?", "What's the weather like?"]
NOTIFS = [("Mom", "Call me when you can, it's about Grandpa", "interrupt"), ("Bank", "Unusual sign-in attempt on your account", "interrupt"),
          ("ShopMart", "20% off sneakers this weekend!", "ignore"), ("Slack", "3 new messages in #random", "digest"),
          ("Airline", "Your flight UA 512 gate changed to B22", "interrupt"), ("Newsletter", "This week in design", "ignore"),
          ("Calendar", "Team lunch moved to 1pm tomorrow", "digest")]


def _route(r):
    k = r.choice(["tool", "tool", "answer_local", "escalate_cloud", "clarify"])
    if k == "tool":
        u = r.choice([f"Remind me to {r.choice(TASKS)} {r.choice(TIMES)}", f"Text {r.choice(NAMES)} that I'm running late",
                      f"What's on my calendar {r.choice(['tomorrow', 'Friday', 'this afternoon'])}?", f"What's {r.choice(NAMES)}'s number?"])
    elif k == "answer_local": u = r.choice(SIMPLE)
    elif k == "escalate_cloud": u = r.choice(HARD)
    else: u = r.choice(VAGUE)
    return {"type": "route", "context": f"Network: {r.choice(['online', 'offline'])}\nUser: {u}", "hint": k}


def _tool(r):
    k = r.choice(["create_reminder", "create_event", "find_event", "send_message", "lookup_contact", "search_memory"])
    n = r.choice(NAMES)
    u = {"create_reminder": f"Remind me to {r.choice(TASKS)} {r.choice(TIMES)}",
         "create_event": f"Schedule lunch with {n} {r.choice(TIMES)}",
         "find_event": f"When is my next meeting with {n}?",
         "send_message": f"Tell {n} I'll be there in {r.randint(5, 30)} minutes",
         "lookup_contact": f"What's {n}'s email address?",
         "search_memory": f"What did I say {n}'s favorite restaurant was?"}[k]
    return {"type": "toolChoice", "context": f"User: {u}", "hint": k}


def _contact(r):
    first = r.choice(NAMES)
    rels = r.sample(REL, 3)
    cands = [f"{first} {ln} ({rel})" for ln, rel in zip(r.sample(["Lee", "Ortiz", "Khan", "Novak", "Park"], 3), rels)]
    pick = r.randrange(3)
    ctx = f"User: Message my {rels[pick]} {first}: see you soon" if r.random() < 0.8 else f"User: Message {first}: see you soon"
    return {"type": "contactPick", "candidates": cands, "context": ctx, "hint": f"c{pick}" if "my " in ctx else "ask"}


def _event(r):
    evs = r.sample(["Dentist (Tue 3pm)", "1:1 with Priya (Wed 10am)", "Standup (daily 9:30am)", "Flight to SFO (Fri 7am)", "Yoga (Thu 6pm)"], 3)
    pick = r.randrange(3)
    key = evs[pick].split(" (")[0]
    return {"type": "eventPick", "candidates": evs, "context": f"User: Move my {key.lower()} to next week", "hint": f"e{pick}"}


def _remember(r):
    if r.random() < 0.55: return {"type": "rememberOrNot", "context": f"User: {r.choice(FACTS)}", "hint": "remember_fact"}
    if r.random() < 0.4: return {"type": "rememberOrNot", "context": f"User: I'm at {r.choice(PLACES)} until 5, then heading home", "hint": "remember_temporary"}
    return {"type": "rememberOrNot", "context": f"User: {r.choice(NONFACTS)}", "hint": "no"}


def _conflict(r):
    c = r.choice([("User lives in Boston", "I just moved to Denver", "update"), ("User likes jazz", "I also love techno", "keep_both"),
                  ("User works at Northwind", "lol I'd quit Northwind if I won the lottery", "ignore_new"),
                  ("User is vegetarian", "I started eating fish again, so pescatarian now", "update"),
                  ("Maya's birthday is March 4", "Maya's birthday is March 4th right?", "ignore_new")])
    return {"type": "memoryConflict", "context": f"Existing memory: {c[0]}\nNew statement: {c[1]}", "hint": c[2]}


def _notif(r):
    s, t, k = r.choice(NOTIFS)
    return {"type": "notificationTriage", "context": f"Notification from {s}: '{t}'", "hint": k}


def _confirm(r):
    a = r.choice([("create a reminder 'water plants' tomorrow 9am", "act"), ("send message to Sam: 'I quit'", "confirm"),
                  ("delete all events next week", "confirm"), ("add 'eggs' to the shopping list", "act"),
                  ("text the whole family group 'I'm pregnant'", "confirm"), ("create calendar event 'Gym' Thu 6pm", "act")])
    return {"type": "confirmBeforeAct", "context": f"Planned action: {a[0]}", "hint": a[1]}


def _nudge(r):
    p, item = r.choice(PLACES), r.choice(ITEMS)
    rel = "nudge" if any(w in p for w in ["Joe", "Whole", "CVS"]) else "skip"
    return {"type": "nudgeNow", "context": f"Trigger: arrive, place: {p}\nMemory: User needs to buy {item}", "hint": rel}


def _timing(r):
    c = r.choice([(f"Remind me to {r.choice(TASKS)} now", "now"), (f"Remind me to {r.choice(TASKS)} {r.choice(TIMES[:4])}", "at_time"),
                  (f"When I get to {r.choice(PLACES)} remind me to {r.choice(TASKS)}", "on_arrival"),
                  (f"Every {r.choice(['Monday', 'weekday', 'month'])} remind me to {r.choice(TASKS)}", "recurring")])
    return {"type": "timing", "context": f"User: {c[0]}", "hint": c[1]}


def _sens(r):
    c = r.choice([("Plan a weekend trip to the coast", "ok"), ("Summarize my therapy notes from Tuesday", "sensitive"),
                  ("What's my bank PIN again?", "sensitive"), ("Write a toast for [PERSON_1]'s wedding", "ok"),
                  ("Interpret my blood test: LDL 190, A1C 7.1", "sensitive"), ("Explain how compound interest works", "ok")])
    return {"type": "sensitivity", "context": f"User: {c[0]}", "hint": c[1]}


def _answerable(r):
    if r.random() < 0.5: return {"type": "answerability", "context": f"User: {r.choice(SIMPLE)}", "hint": "yes"}
    return {"type": "answerability", "context": f"User: {r.choice(HARD)}", "hint": "no"}


GENS = {"route": _route, "toolChoice": _tool, "contactPick": _contact, "eventPick": _event, "rememberOrNot": _remember,
        "memoryConflict": _conflict, "notificationTriage": _notif, "confirmBeforeAct": _confirm, "nudgeNow": _nudge,
        "timing": _timing, "sensitivity": _sens, "answerability": _answerable}


DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
WHERE = ["home", "work", "commuting", "the gym", "a cafe", "unknown"]


def _envelope(r, s):
    """Situational header (time, place, battery) so identical requests appear in different situations."""
    if r.random() < 0.15: return s
    hdr = f"Now: {r.choice(DAYS)} {r.randint(6, 23)}:{r.choice(['00', '05', '15', '30', '42', '55'])}\nUser location: {r.choice(WHERE)}\n"
    return {**s, "context": hdr + s["context"]}


def generate(n: int, seed: int = 0) -> list[dict]:
    r = random.Random(seed)
    types = list(GENS)
    out, seen = [], set()
    tries = 0
    while len(out) < n and tries < n * 50:
        tries += 1
        s = _envelope(r, GENS[types[tries % len(types)]](r))
        key = (s["type"], s["context"], tuple(s.get("candidates", [])))
        if key in seen: continue
        seen.add(key)
        s["id"] = f"s{seed}-{len(out):05d}"
        out.append(s)
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=2000); ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--out", default="out/scenarios.jsonl")
    a = ap.parse_args()
    from pathlib import Path
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    rows = generate(a.n, a.seed)
    Path(a.out).write_text("".join(json.dumps(x) + "\n" for x in rows))
    print(f"wrote {len(rows)} scenarios -> {a.out}")
