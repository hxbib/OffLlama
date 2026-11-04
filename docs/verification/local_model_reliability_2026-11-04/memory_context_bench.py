"""Route/toolChoice under the shipped runtime contract, bare context vs retrieved-memory context.
Usage: python3 -I memory_context_bench.py <repo root> <out.json> [completion URL]
Mirrors Reflex.decide: training/pg_train/prompts.llama3 (tested byte-equal to DecisionPrompt.llama3), n_probs 40
letter readout, floor = min seen - 2, contextual prior subtraction, softmax T=1, tau from the shipped calibration."""
import json, math, random, sys, urllib.request
root, out_path = sys.argv[1], sys.argv[2]
URL = sys.argv[3] if len(sys.argv) > 3 else "http://127.0.0.1:8299/completion"
sys.path.insert(0, root + "/training")
from pg_train import prompts
cal = json.load(open(root + "/app/PocketGlimmer/Resources/Models/calibration.json"))
TAU = cal["defaultTau"]

def readout(prompt, L):
    body = json.dumps({"prompt": prompt, "n_predict": 1, "n_probs": 40, "temperature": 0,
                       "post_sampling_probs": False, "cache_prompt": True}).encode()
    r = json.load(urllib.request.urlopen(urllib.request.Request(URL, body, {"Content-Type": "application/json"})))
    out = {}
    for t in r["completion_probabilities"][0]["top_logprobs"]:
        k, lp = t["token"].strip(), t["logprob"]
        if k in L:
            if k in out: m = max(out[k], lp); out[k] = m + math.log(math.exp(out[k] - m) + math.exp(lp - m))
            else: out[k] = lp
    return out

def decide(kind, ctx):
    s = prompts.get_set(kind); L = prompts.letters(s)
    raw = readout(prompts.llama3(s, ctx, cal["promptStyle"]), L)
    floor = min(raw.values()) - 2
    lg = [raw.get(l, floor) for l in L]
    pr = cal["prior"].get(kind)
    if pr and len(pr) == len(lg): lg = [a - b for a, b in zip(lg, pr)]
    m = max(lg); e = [math.exp(x - m) for x in lg]; z = sum(e); p = [x / z for x in e]
    b = max(range(len(p)), key=lambda i: p[i])
    return s["options"][b]["id"], p[b]

MEMORY_POOL = ["Linda is the user's mom", "Sam is the user's brother", "The user is allergic to peanuts",
    "The user works at Globex", "The user's dentist is Dr. Park", "The user lives in Austin",
    "The user's birthday is March 3", "The user parked on level 4 today", "The user likes hiking",
    "Mia is the user's sister", "The user is vegetarian", "The user's gym is Crunch on 5th"]

def render(facts):
    return "" if not facts else "Known about the user:\n" + "\n".join("- " + f for f in facts) + "\n"

AUTHORED = [  # (utterance, route gold, toolChoice gold or None). Written for this bench, not frozen, not teacher-labelled.
    ("Remind me to call mom at 5pm", "tool", "create_reminder"), ("Remind me to take my pills tonight", "tool", "create_reminder"),
    ("Set a reminder to pay rent on Friday", "tool", "create_reminder"), ("remind me to buy milk tomorrow morning", "tool", "create_reminder"),
    ("Don't let me forget to water the plants at 8", "tool", "create_reminder"),
    ("Add lunch with Ana tomorrow at noon to my calendar", "tool", "create_event"), ("Schedule a dentist visit next Tuesday at 3pm", "tool", "create_event"),
    ("Put yoga on my calendar Thursday 6pm", "tool", "create_event"), ("Book a meeting with Raj on Monday at 10", "tool", "create_event"),
    ("Text Sam I'm running late", "tool", "send_message"), ("Send a message to Mia saying hii", "tool", "send_message"),
    ("text mia hii", "tool", "send_message"), ("Tell Leo the keys are under the mat", "tool", "send_message"),
    ("Message Ana that dinner is at 7", "tool", "send_message"),
    ("What's Leo's phone number?", "tool", "lookup_contact"), ("Find Ana's email address", "tool", "lookup_contact"),
    ("What's Raj's address?", "tool", "lookup_contact"),
    ("What did I say my locker code was?", "tool", "search_memory"), ("Where did I tell you I parked?", "tool", "search_memory"),
    ("What's on my calendar tomorrow?", "tool", "find_event"),
    ("hii", "answer_local", None), ("hello!", "answer_local", None), ("thanks!", "answer_local", None), ("good morning", "answer_local", None),
    ("What's 12 times 7?", "answer_local", None), ("How do you spell necessary?", "answer_local", None),
    ("Translate 'good night' into Spanish", "answer_local", None), ("Rewrite 'im late sry' politely", "answer_local", None),
    ("lol ok", "answer_local", None), ("How are you?", "answer_local", None),
    ("Write a detailed plan for a week in Japan", "escalate_cloud", None), ("Compare renting vs buying a house in Austin", "escalate_cloud", None),
    ("Explain how mRNA vaccines work in depth", "escalate_cloud", None), ("Draft a 500-word cover letter for a nursing job", "escalate_cloud", None),
    ("Give me advice on negotiating a raise", "escalate_cloud", None), ("Research the best budget laptops this year", "escalate_cloud", None),
    ("Write an essay about climate policy", "escalate_cloud", None), ("Analyze the pros and cons of electric cars", "escalate_cloud", None),
    ("Plan a 3-day workout program for a beginner", "escalate_cloud", None), ("Summarize the causes of World War I", "escalate_cloud", None),
    ("Change that one", "clarify", None), ("Do the thing", "clarify", None), ("Send it to her", "clarify", None),
    ("Move it to later", "clarify", None), ("Cancel that", "clarify", None), ("Fix it", "clarify", None),
    ("Tell him", "clarify", None), ("Same as before", "clarify", None),
]

def rows():
    out = []
    for l in open(root + "/eval/gold/gold_calibration.jsonl"):
        r = json.loads(l)
        if r["type"] in ("route", "toolChoice"):
            out.append({"src": "cal180", "kind": r["type"], "base": r["context"], "gold": r["gold"]})
    for u, rg, tg in AUTHORED:
        out.append({"src": "authored", "kind": "route", "base": f"Network: offline\nUser: {u}", "gold": rg})
        if tg: out.append({"src": "authored", "kind": "toolChoice", "base": f"Network: offline\nUser: {u}", "gold": tg})
    return out

CONDITIONS = [("bare", 0, [0]), ("mem2", 2, [1, 2, 3]), ("mem4", 4, [1, 2, 3])]
results = []
for i, r in enumerate(rows()):
    for cname, k, seeds in CONDITIONS:
        for seed in seeds:
            facts = random.Random(seed * 1000 + i).sample(MEMORY_POOL, k) if k else []
            a, c = decide(r["kind"], render(facts) + r["base"])
            results.append({**r, "row": i, "cond": cname, "seed": seed, "facts": facts, "argmax": a, "conf": round(c, 4)})
    print(i, r["kind"], r["gold"], file=sys.stderr)
json.dump({"tau": TAU, "url": URL, "results": results}, open(out_path, "w"), indent=0)
