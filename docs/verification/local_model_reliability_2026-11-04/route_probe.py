import json, math, sys, urllib.request
sys.path.insert(0, sys.argv[1] + "/training")
from pg_train import prompts
URL = sys.argv[3] if len(sys.argv) > 3 else "http://127.0.0.1:8299/completion"
cal = json.load(open(sys.argv[1] + "/app/PocketGlimmer/Resources/Models/calibration.json"))
def letters_logits(prompt, L):
    body = json.dumps({"prompt": prompt, "n_predict": 1, "n_probs": 40, "temperature": 0, "post_sampling_probs": False, "cache_prompt": True}).encode()
    r = json.load(urllib.request.urlopen(urllib.request.Request(URL, body, {"Content-Type": "application/json"})))
    out = {}
    for t in r["completion_probabilities"][0]["top_logprobs"]:
        k = t["token"].strip()
        if k in L:
            lp = t["logprob"]
            out[k] = lp if k not in out else max(out[k], lp) + math.log(math.exp(out[k]-max(out[k],lp)) + math.exp(lp-max(out[k],lp)))
    return out
def decide(kind, ctx):
    s = prompts.get_set(kind)
    L = prompts.letters(s)
    raw = letters_logits(prompts.llama3(s, ctx, cal["promptStyle"]), L)
    floor = min(raw.values()) - 2
    lg = [raw.get(l, floor) for l in L]
    pr = cal["prior"].get(kind)
    if pr: lg = [a - b for a, b in zip(lg, pr)]
    m = max(lg); e = [math.exp(x - m) for x in lg]; z = sum(e); p = [x / z for x in e]
    ids = [o["id"] if isinstance(o, dict) else o[0] for o in s["options"]]
    b = max(range(len(p)), key=lambda i: p[i])
    return ids[b], p[b], dict(zip(ids, [round(x, 2) for x in p]))
MEM = "Known about the user:\n- User's sister is Mia\n- User is allergic to peanuts\n- User works at Globex\n"
utts = [("Remind me to call mom at 5pm", "tool"), ("Add lunch with Ana tomorrow at noon to my calendar", "tool"),
        ("Text Sam I'm running late", "tool"), ("Send a message to Mia saying hii", "tool"),
        ("text mia hii", "tool"), ("Message the family group that dinner is at 7", "tool"),
        ("What's Leo's phone number?", "tool"), ("What did I say my locker code was?", "tool"),
        ("hii", "answer_local"), ("thanks!", "answer_local"), ("What's 12 times 7?", "answer_local"),
        ("Write a detailed plan for a week in Japan", "escalate_cloud"), ("Change that one", "clarify")]
kind = sys.argv[2] if len(sys.argv) > 2 else "route"
for net in ["offline"]:
    for label, prefix in [("bare", ""), ("mem", MEM)]:
        ok = hi = 0
        for u, g in utts:
            ctx = f"{prefix}Network: {net}\nUser: {u}"
            a, c, p = decide(kind, ctx)
            ok += a == g; hi += c >= 0.9
            print(f"{label:4} {net:7} {u[:48]:48} gold={g:14} argmax={a:14} conf={c:.3f} {'LOCAL' if c>=0.9 else 'below'}")
        print(f"== {label}: argmax correct {ok}/{len(utts)}, conf>=0.90 {hi}/{len(utts)}\n")
