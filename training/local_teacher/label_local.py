"""Resumable local labeling with Glimmer. Appends one JSON line per item (flush+fsync), skips ids already in --out.
--mode qc: input is eval gold items (teacher quality check ONLY; output never used for training).
--mode train: input must be dedupe'd scenarios; re-checks each row against current eval files before labeling."""
import argparse, json, os, sys, time, datetime
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import glimmer_teacher as G, dedupe as D
from pg_train import prompts

ap = argparse.ArgumentParser()
ap.add_argument("--input", required=True); ap.add_argument("--out", required=True)
ap.add_argument("--mode", choices=["qc", "train"], required=True)
ap.add_argument("--limit", type=int, default=0); ap.add_argument("--deadline", default="", help="ISO local time to stop")
ap.add_argument("--url", default="http://127.0.0.1:8091")
a = ap.parse_args()
rows = [json.loads(l) for l in open(a.input) if l.strip()]
if a.limit: rows = rows[: a.limit]
if a.mode == "train":
    rows, dropped = D.check(rows, D.eval_items())
    print(f"re-dedupe vs current eval: dropped {len(dropped)} more", flush=True)
done = set()
if os.path.exists(a.out):
    for l in open(a.out):
        try: done.add(json.loads(l)["id"])
        except Exception: pass
todo = [r for r in rows if r["id"] not in done]
print(f"{len(done)} already done, {len(todo)} to go", flush=True)
dl = datetime.datetime.fromisoformat(a.deadline) if a.deadline else None
T = G.GlimmerLocalTeacher(a.url)
t_start = time.time(); n = 0
with open(a.out, "a") as f:
    for r in todo:
        if dl and datetime.datetime.now() >= dl:
            print("deadline reached", flush=True); break
        s = prompts.get_set(r["type"], r.get("candidates"))
        for attempt in range(3):
            try: lab = G.GlimmerLocalTeacher.label(T, s, r["context"]); break
            except Exception as e:
                print("error", r["id"], e, flush=True); time.sleep(10); lab = None
        if lab is None: continue
        ids = [o["id"] for o in s["options"]]
        rec = {**r, "mode": a.mode, "option_ids": ids, "teacher_option": ids[prompts.LETTERS.index(lab["letter"])] if lab["letter"] else None,
               "label": lab, "labeled_at": datetime.datetime.now().isoformat(timespec="seconds")}
        f.write(json.dumps(rec) + "\n"); f.flush(); os.fsync(f.fileno()); n += 1
        if n % 25 == 0:
            el = time.time() - t_start
            print(f"[{datetime.datetime.now():%H:%M:%S}] {len(done)+n} done; {n/el*3600:.0f} items/h; last {lab['latency_ms']:.0f} ms, prompt_n={lab['tokens_in']}", flush=True)
el = time.time() - t_start
print(f"finished: {n} new in {el:.0f}s ({(n/el*3600 if el else 0):.0f} items/h); total {len(done)+n}", flush=True)
