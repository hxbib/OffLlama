"""Frozen-test-split guard: drop generated training scenarios that duplicate ANY eval item (all eval/**/*.jsonl rows
with a `context`). Exact: normalized full context or normalized user utterance equal. Near: char-5-gram Jaccard
>= THRESH on the normalized context, or >= THRESH on the user utterance. Writes kept rows + a report."""
import argparse, glob, json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
THRESH = 0.8


def norm(t):
    t = t.lower(); t = re.sub(r"\d", "0", t); t = re.sub(r"[^a-z0 ]+", " ", t)
    return re.sub(r"\s+", " ", t).strip()


def utter(ctx):
    m = re.findall(r"User:(.*)", ctx)
    return norm(m[-1]) if m else norm(ctx)


def grams(t, n=5):
    return {t[i:i + n] for i in range(max(1, len(t) - n + 1))}


def jac(a, b):
    return len(a & b) / len(a | b) if a and b else 0.0


def eval_items():
    out = []
    for f in sorted(glob.glob(str(ROOT / "eval/**/*.jsonl"), recursive=True)):
        for l in open(f):
            try: r = json.loads(l)
            except Exception: continue
            if isinstance(r, dict) and r.get("context"):
                out.append({**r, "_file": str(Path(f).relative_to(ROOT))})
    return out


def check(rows, evs):
    E = [(e, norm(e["context"]), utter(e["context"])) for e in evs]
    Eg = [(e, n, u, grams(n), grams(u)) for e, n, u in E]
    exact_c = {n for _, n, _ in E}; exact_u = {u for _, _, u in E}
    kept, dropped = [], []
    for r in rows:
        n, u = norm(r["context"]), utter(r["context"])
        why = None
        if n in exact_c: why = "exact_context"
        elif u in exact_u: why = "exact_utterance"
        else:
            gn, gu = grams(n), grams(u)
            for e, en, eu, egn, egu in Eg:
                jc, ju = jac(gn, egn), jac(gu, egu)
                if jc >= THRESH or (ju >= THRESH and len(u) > 12):
                    why = f"near:{e['_file']}:{e['id']}:ctx={jc:.2f}:utt={ju:.2f}"; break
        (dropped if why else kept).append({**r, "_dedupe": why} if why else r)
    return kept, dropped


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--scenarios", default=str(ROOT / "training/out/scenarios.jsonl"))
    ap.add_argument("--out", default=str(ROOT / "training/local_teacher/out")); a = ap.parse_args()
    rows = [json.loads(l) for l in open(a.scenarios) if l.strip()]
    evs = eval_items()
    kept, dropped = check(rows, evs)
    o = Path(a.out); o.mkdir(parents=True, exist_ok=True)
    (o / "scenarios_dedup.jsonl").write_text("".join(json.dumps(r) + "\n" for r in kept))
    rep = {"scenarios": a.scenarios, "n_in": len(rows), "eval_files": sorted({e["_file"] for e in evs}), "n_eval_items": len(evs),
           "method": f"normalized exact (context, user utterance) + char-5gram Jaccard>={THRESH} (context or utterance)",
           "n_dropped": len(dropped), "n_kept": len(kept), "dropped": [{"id": d["id"], "why": d["_dedupe"], "context": d["context"]} for d in dropped]}
    (o / "dedupe_report.json").write_text(json.dumps(rep, indent=1))
    print(json.dumps({k: v for k, v in rep.items() if k != "dropped"}, indent=1))
    # also: near-misses distribution for the record
    return rep


if __name__ == "__main__":
    main()
