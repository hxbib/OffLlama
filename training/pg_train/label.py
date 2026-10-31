"""Label scenarios with one or more teachers -> out/labels.jsonl (letter + probs per teacher), then merge with the
disagreement->escalate rule -> out/train.jsonl / out/heldout.jsonl."""
import argparse, json, random
from pathlib import Path
from . import prompts, teachers as T


def merge(row: dict, labels: list[dict], teacher_tau: float = 0.6) -> dict:
    """Disagreement -> escalate: if teachers disagree, or the agreed answer is weak, the TARGET becomes the set's
    fallback option (the safe action Reflex takes when it escalates) and `escalate=True` is recorded."""
    s = prompts.get_set(row["type"], row.get("candidates"))
    L = prompts.letters(s)
    fallback = L[[o["id"] for o in s["options"]].index(s["fallback"])]
    valid = [l for l in labels if l.get("letter") in L]
    letters = {l["letter"] for l in valid}
    if not valid or len(letters) > 1:
        return {**row, "target": fallback, "escalate": True, "reason": "disagree" if valid else "no_label"}
    agreed = valid[0]["letter"]
    conf = min((l["probs"] or {}).get(agreed, 1.0) for l in valid)
    if conf < teacher_tau:
        return {**row, "target": fallback, "escalate": True, "reason": f"weak:{conf:.2f}"}
    # Soft target = mean teacher distribution (kept for KD experiments; SFT uses the hard letter).
    soft = {k: sum((l["probs"] or {k: float(k == agreed)}).get(k, 0) for l in valid) / len(valid) for k in L}
    return {**row, "target": agreed, "soft": soft, "escalate": False, "reason": "agree"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scenarios", default="out/scenarios.jsonl")
    ap.add_argument("--teachers", default="local,local-shuffled", help="comma list: local, local-shuffled, spark-fireworks, spark-baseten, glimmer-modal, meta")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--heldout", type=float, default=0.2)
    ap.add_argument("--out", default="out")
    ap.add_argument("--dry-run-tag", default="", help="label rows (e.g. DRY_RUN_LOCAL_1B_TEACHER) so nobody mistakes them for real teacher data")
    a = ap.parse_args()
    reg = {"local": lambda: T.LocalLlamaServerTeacher(), "local-shuffled": lambda: T.LocalLlamaServerTeacher(shuffle=True),
           "spark-baseten": T.muse_spark_open_baseten, "spark-fireworks": T.spark_open_fireworks, "glimmer-modal": T.glimmer_modal, "meta": T.meta_model_api}
    ts = [reg[t]() for t in a.teachers.split(",")]
    rows = [json.loads(l) for l in Path(a.scenarios).read_text().splitlines() if l.strip()]
    if a.limit: rows = rows[: a.limit]
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    merged = []
    with open(out / "labels.jsonl", "w") as f:
        for i, r in enumerate(rows):
            s = prompts.get_set(r["type"], r.get("candidates"))
            labs = [t.label(s, r["context"]) for t in ts]
            rec = {**r, "labels": labs, "dry_run": a.dry_run_tag or None}
            f.write(json.dumps(rec) + "\n")
            merged.append({**merge(r, labs), "dry_run": a.dry_run_tag or None})
            if (i + 1) % 20 == 0: print(f"  labeled {i + 1}/{len(rows)}")
    random.Random(1).shuffle(merged)
    k = int(len(merged) * a.heldout)
    (out / "heldout.jsonl").write_text("".join(json.dumps(x) + "\n" for x in merged[:k]))
    (out / "train.jsonl").write_text("".join(json.dumps(x) + "\n" for x in merged[k:]))
    esc = sum(m["escalate"] for m in merged)
    hint_agree = sum(1 for m in merged if not m["escalate"] and prompts.get_set(m["type"], m.get("candidates"))["options"][prompts.LETTERS.index(m["target"])]["id"] == m.get("hint"))
    print(f"labeled {len(merged)}: escalate(disagree/weak)={esc}, agreed={len(merged) - esc}, agreed&matches-generator-hint={hint_agree}")
    print(f"-> {out}/train.jsonl ({len(merged) - k}), {out}/heldout.jsonl ({k})")


if __name__ == "__main__":
    main()
