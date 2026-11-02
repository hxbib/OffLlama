"""Data-scale pool (2026-11-02): ~8k synthetic scenarios weighted to weak cal types + HF seed utterances
(MASSIVE en-US train, CLINC150 'plus' train, SNIPS train) wrapped in our envelopes. Plain jsonl/parquet only,
no datasets loader, no trust_remote_code. Dedupe vs ALL eval/** items (dedupe.py exact + char-5-gram Jaccard>=0.8)
plus self-dedupe. Train-only. Also writes the CLINC oos TEST stress set (never trained on)."""
import json, random, sys, collections
from pathlib import Path
import pandas as pd
ROOT = Path(__file__).resolve().parents[2]; sys.path[:0] = [str(ROOT / "training"), str(ROOT / "training/local_teacher")]
from pg_train import scenarios as S
import dedupe as D
H = Path("/workspace/hfdata"); OUT = Path(__file__).parent / "out"; OUT.mkdir(exist_ok=True)
r = random.Random(20261102)
# weights from shipping cal per-type correct (n=15): nudge 7, contact/timing 10, answ/notif 11, rest >=12
W = {"nudgeNow": 1800, "contactPick": 900, "timing": 900, "answerability": 700, "notificationTriage": 700,
     "route": 450, "toolChoice": 450, "eventPick": 450, "confirmBeforeAct": 400, "rememberOrNot": 350, "memoryConflict": 250, "sensitivity": 250}
syn, seen = [], set()
for t, n in W.items():
    got, tries = 0, 0
    while got < n and tries < n * 200:
        tries += 1
        s = S._nudge_v2(r) if (t == "nudgeNow" and r.random() < 0.7) else S.GENS[t](r)
        s = S._envelope(r, s); key = (s["type"], s["context"], tuple(s.get("candidates") or []))
        if key in seen: continue
        seen.add(key); s["id"] = f"ds-{t}-{got:05d}"; s["source"] = "synthetic"; syn.append(s); got += 1
net = lambda: f"Network: {r.choice(['online', 'online', 'offline'])}\n"
hf = []
def add(t, u, src, i, hdr=""):
    hf.append({"type": t, "context": hdr + f"User: {u[0].upper() + u[1:]}", "id": f"hf-{src}-{t}-{i}", "source": src})
m = [json.loads(l) for l in open(H / "1.1/data/en-US.jsonl")]
m = [x for x in m if x["partition"] == "train"]; r.shuffle(m)
TOOLY = ("alarm", "calendar", "email", "lists", "social")
mt = [x for x in m if x["scenario"] in TOOLY]; mo = [x for x in m if x["scenario"] not in TOOLY]
for i, x in enumerate(mt[:450]): add("toolChoice", x["utt"], "massive", i)
for i, x in enumerate(mt[450:750] + mo[:250]): add("route", x["utt"], "massive", i, net())
for i, x in enumerate(mo[250:500]): add("answerability", x["utt"], "massive", i)
c = pd.read_parquet(H / "clinc_train.parquet"); oos = 42  # 'oos' intent id in plus config
co = c[c.intent == oos].sample(frac=1, random_state=1); ci = c[c.intent != oos].sample(frac=1, random_state=1)
for i, u in enumerate(list(co.text[:150]) + list(ci.text[:250])): add("route", u, "clinc", i, net())
for i, u in enumerate(list(co.text[150:250]) + list(ci.text[250:450])): add("answerability", u, "clinc", i)
sn = pd.read_parquet(H / "snips_train.parquet").sample(frac=1, random_state=2)
for i, u in enumerate(sn.text[:300]): add("route", u, "snips", i, net())
rows = syn + hf; raw = collections.Counter(x["source"] for x in rows)
# self-dedupe on normalized context
u, selfdup = [], 0; ks = set()
for x in rows:
    k = (x["type"], D.norm(x["context"]))
    if k in ks: selfdup += 1; continue
    ks.add(k); u.append(x)
kept, dropped = D.check(u, D.eval_items())
rep = {"raw": raw, "self_dupes": selfdup, "eval_dupes_dropped": len(dropped),
       "eval_dupes_by_source": collections.Counter(x["source"] for x in dropped),
       "eval_dupes_by_kind": collections.Counter(x["_dedupe"].split(":")[0] if x["_dedupe"].startswith("near") else x["_dedupe"] for x in dropped),
       "eval_dupes_by_file": collections.Counter(x["_dedupe"].split(":")[1] for x in dropped if x["_dedupe"].startswith("near")),
       "kept": collections.Counter(x["source"] for x in kept), "kept_by_type": collections.Counter(x["type"] for x in kept)}
(OUT / "pool.jsonl").write_text("".join(json.dumps(x) + "\n" for x in kept))
(OUT / "dedupe_report.json").write_text(json.dumps(rep, indent=1)); print(json.dumps(rep, indent=1))
# stress set: CLINC plus TEST oos only (never trained on), route + answerability envelopes
t = pd.read_parquet(H / "clinc_test.parquet"); t = t[t.intent == oos]
st = [{"type": ty, "context": (f"Network: online\n" if ty == "route" else "") + f"User: {x[0].upper() + x[1:]}", "id": f"clincoos-{ty}-{i}"}
      for i, x in enumerate(t.text) for ty in ("route", "answerability")]
(OUT / "clinc_oos_test_stress.jsonl").write_text("".join(json.dumps(x) + "\n" for x in st)); print("stress", len(st))
