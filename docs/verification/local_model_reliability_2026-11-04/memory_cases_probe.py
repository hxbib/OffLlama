import json, math, sys, urllib.request
root = sys.argv[1]; sys.path.insert(0, root + "/training")
from pg_train import prompts
URL = sys.argv[3] if len(sys.argv) > 3 else "http://127.0.0.1:8299/completion"
cal = json.load(open(root + "/app/PocketGlimmer/Resources/Models/calibration.json"))
def raw_letters(prompt, L):
    body = json.dumps({"prompt": prompt, "n_predict": 1, "n_probs": 40, "temperature": 0, "post_sampling_probs": False, "cache_prompt": True}).encode()
    r = json.load(urllib.request.urlopen(urllib.request.Request(URL, body, {"Content-Type": "application/json"})))
    out = {}
    for t in r["completion_probabilities"][0]["top_logprobs"]:
        k = t["token"].strip()
        if k in L:
            lp = t["logprob"]
            if k in out: m = max(out[k], lp); out[k] = m + math.log(math.exp(out[k]-m) + math.exp(lp-m))
            else: out[k] = lp
    return out
def decide(kind, ctx, cands=None):
    s = prompts.get_set(kind, cands)
    L = prompts.letters(s)
    raw = raw_letters(prompts.llama3(s, ctx, cal["promptStyle"]), L)
    floor = min(raw.values()) - 2
    lg = [raw.get(l, floor) for l in L]
    key = f"{kind}#{len(L)}" if kind in ("contactPick", "eventPick", "skillPick") else kind
    pr = cal["prior"].get(key)
    if pr and len(pr) == len(lg): lg = [a - b for a, b in zip(lg, pr)]
    m = max(lg); e = [math.exp(x - m) for x in lg]; z = sum(e); p = [x / z for x in e]
    ids = [o["id"] for o in s["options"]]
    b = max(range(len(p)), key=lambda i: p[i])
    return {"argmax": ids[b], "label": s["options"][b]["label"], "conf": round(p[b], 3), "local": p[b] >= 0.9, "raw_letter_logprobs": raw}
cases = [
  ("text my brother", "route", None, "Known about the user:\n- Sam Ortiz is the user's brother\n", "User: text my brother I'm on my way", "tool"),
  ("text my brother", "toolChoice", None, "Known about the user:\n- Sam Ortiz is the user's brother\n", "User: text my brother I'm on my way", "send_message"),
  ("same first name, memory names brother", "contactPick", ["Sam Lee", "Sam Ortiz"], "Known about the user:\n- Sam Ortiz is the user's brother\n", "User: What's my brother Sam's number?", "c1"),
  ("same first name, no hint in utterance", "contactPick", ["Sam Lee", "Sam Ortiz"], "Known about the user:\n- Sam Ortiz is the user's brother\n", "User: What's Sam's number?", "ask"),
  ("event via memory", "route", None, "Known about the user:\n- The user's dentist is Dr. Park\n", "User: When is my dentist appointment?", "tool"),
  ("event via memory", "toolChoice", None, "Known about the user:\n- The user's dentist is Dr. Park\n", "User: When is my dentist appointment?", "find_event"),
  ("event via memory", "eventPick", ["Checkup with Dr. Park (Tue 3pm)", "Team sync (Mon 9am)"], "Known about the user:\n- The user's dentist is Dr. Park\n", "User: When is my dentist appointment?", "e0"),
  ("memory Q&A", "route", None, "Known about the user:\n- Linda is the user's mom\n", "User: What's my mom's name?", "tool"),
  ("memory Q&A", "toolChoice", None, "Known about the user:\n- Linda is the user's mom\n", "User: What's my mom's name?", "search_memory"),
  ("memory Q&A", "answerability", None, "Known about the user:\n- Linda is the user's mom\n", "User: What's my mom's name?", "yes"),
]
rows = []
for name, kind, cands, mem, user, gold in cases:
    net = "" if kind in ("answerability",) else "Network: offline\n"
    bare = decide(kind, net + user, cands); withm = decide(kind, mem + net + user, cands)
    rows.append({"case": name, "decision": kind, "candidates": cands, "gold": gold, "bare": bare, "with_memory": withm})
    print(f"{name[:36]:36} {kind:13} gold={gold:14} bare={bare['argmax']}:{bare['conf']:.3f}{'*' if bare['local'] else ' '}  mem={withm['argmax']}:{withm['conf']:.3f}{'*' if withm['local'] else ' '}")
json.dump(rows, open(sys.argv[2], "w"), indent=1)
