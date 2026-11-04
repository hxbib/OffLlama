"""Validate round-3 manifests. Exit 1 on any failure.

Checks: hash identity vs data_manifest.json, required fields, label
provenance (needs_label must have gold=null; deterministic_gold must
name a basis), group overlap across splits, overlap with prior-train
and eval/stress groups, and duplicate ids.

  python3 training/round3/data_validate.py
  python3 training/round3/data_validate.py --dir /path/to/fixtures
"""
import argparse, hashlib, json, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "training" / "local_teacher"))
import dedupe as D

REQUIRED = ["id", "decision_type", "context", "group_id", "source_id",
            "label_status", "gold", "generation_origin"]
BASES = {"squad_v2_answer_span_v1", "bfcl_irrelevance_v1",
         "pocket_registry_example_v1"}


def load(p):
    return [json.loads(l) for l in Path(p).read_text().splitlines() if l.strip()]


def group_key(context):
    import re
    lines = [l for l in context.splitlines()
             if not re.match(r"^(Now:|User location:|Network:)\s", l.strip())]
    return "g" + hashlib.sha256(D.norm("\n".join(lines).strip()).encode()).hexdigest()[:15]


def validate(directory):
    directory = Path(directory)
    errors = []
    man_path = directory / "data_manifest.json"
    if not man_path.exists():
        return [f"missing {man_path}"]
    man = json.loads(man_path.read_text())
    seen_ids, group_owner = set(), {}
    for split in ("train", "dev", "calfit", "report"):
        info = man.get("splits", {}).get(split)
        if not info:
            errors.append(f"manifest missing split {split}"); continue
        p = directory / info["file"]
        if not p.exists():
            errors.append(f"missing {p}"); continue
        digest = hashlib.sha256(p.read_bytes()).hexdigest()
        if digest != info["sha256"]:
            errors.append(f"{split}: sha256 mismatch (manifest {info['sha256'][:12]}, actual {digest[:12]})")
        rows = load(p)
        if len(rows) != info["rows"]:
            errors.append(f"{split}: row count {len(rows)} != manifest {info['rows']}")
        for r in rows:
            for k in REQUIRED:
                if k not in r:
                    errors.append(f"{split}:{r.get('id','?')}: missing field {k}")
            if r.get("id") in seen_ids:
                errors.append(f"duplicate id {r.get('id')}")
            seen_ids.add(r.get("id"))
            if r.get("label_status") == "needs_label" and r.get("gold") is not None:
                errors.append(f"{r.get('id')}: needs_label row carries gold")
            if r.get("label_status") == "deterministic_gold":
                if r.get("gold") is None or r.get("gold_basis") not in BASES:
                    errors.append(f"{r.get('id')}: deterministic_gold without approved basis")
            if r.get("label_status") not in ("needs_label", "deterministic_gold",
                                             "human_gold", "schema_assertion"):
                errors.append(f"{r.get('id')}: unknown label_status {r.get('label_status')}")
            g = r.get("group_id")
            if group_key(r.get("context", "")) != g:
                errors.append(f"{r.get('id')}: group_id does not match recomputed group")
            if g in group_owner and group_owner[g] != split:
                errors.append(f"group {g} in both {group_owner[g]} and {split}")
            group_owner.setdefault(g, split)
    # Held-out splits must not touch prior-train or eval groups.
    if (ROOT / "training/round2/out/r2c_train.jsonl").exists():
        prior = {group_key(r["context"]) for f in
                 ("training/round2/out/r2c_train.jsonl",
                  "training/round3/target_comparison_inputs.jsonl")
                 for r in load(ROOT / f) if r.get("context")}
        evalg = {group_key(r["context"]) for r in D.eval_items() if r.get("context")}
        for split in ("dev", "calfit", "report"):
            p = directory / f"data_{split}.jsonl"
            if p.exists():
                for r in load(p):
                    if r["group_id"] in prior:
                        errors.append(f"{r['id']}: held-out row reuses a prior-train group")
                    if r["group_id"] in evalg:
                        errors.append(f"{r['id']}: held-out row reuses an eval group")
    return errors


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=str(HERE))
    a = ap.parse_args()
    errs = validate(a.dir)
    if errs:
        print(f"FAIL ({len(errs)}):")
        for e in errs[:50]:
            print(" -", e)
        sys.exit(1)
    print("OK: round-3 manifests valid (hashes, provenance, group separation)")


if __name__ == "__main__":
    main()
