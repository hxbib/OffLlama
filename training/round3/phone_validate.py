"""Validate phone tranche inputs against contracts and frozen splits.

Checks option mapping, deterministic dispositions, group leakage versus
the frozen round-3 dev/calfit/report groups and every eval context, and
held-out hash preservation. Exit 1 on any failure.
  python3 training/round3/phone_validate.py
"""
import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "training"))
sys.path.insert(0, str(ROOT / "training" / "local_teacher"))
import phone_contracts as PC
import dedupe as D

FAMILY_FLAGS = {
    "contact_ambiguous": {"ambiguous_contact": True},
    "permission": {"permission_denied": True},
    "cancellation": {"cancel": True},
    "interrupted": {"interrupted_unknown": True},
    "hard_negative": {"ambiguous_contact": True},
    "recovery_failed": {"failed_outcome": True},
}


def load(p):
    return [json.loads(l) for l in Path(p).read_text().splitlines() if l.strip()]


def group_key(context):
    import re
    lines = [l for l in context.splitlines()
             if not re.match(r"^(Now:|User location:|Network:)\s", l.strip())]
    return "g" + hashlib.sha256(
        D.norm("\n".join(lines).strip()).encode()).hexdigest()[:15]


def validate():
    errors = []
    man = json.loads((HERE / "phone_manifest.json").read_text())
    contracts = PC.load_contracts()
    if len(contracts) != 38:
        errors.append(f"contracts {len(contracts)} != 38")
    if sum(1 for e in contracts.values()
           if PC.availability(e) == "notWired") != 1:
        errors.append("expected exactly one unavailable contract")
    all_rows = []
    for split in ("train", "dev", "calfit"):
        p = HERE / f"phone_inputs_{split}.jsonl"
        digest = hashlib.sha256(p.read_bytes()).hexdigest()
        if digest != man["splits"][split]["sha256"]:
            errors.append(f"{split}: sha mismatch")
        all_rows.extend(load(p))
    allp = HERE / "phone_inputs_all.jsonl"
    if hashlib.sha256(allp.read_bytes()).hexdigest() != man["all_sha256"]:
        errors.append("all: sha mismatch")
    seen_ids = set()
    owner = {}
    for r in all_rows:
        if r["id"] in seen_ids:
            errors.append(f"duplicate id {r['id']}")
        seen_ids.add(r["id"])
        if r["group_id"] in owner and owner[r["group_id"]] != r["split"]:
            errors.append(f"group {r['group_id']} spans splits")
        owner.setdefault(r["group_id"], r["split"])
        entry = contracts.get(r["contract_id"])
        if entry is None:
            errors.append(f"{r['id']}: unknown contract")
            continue
        if r["contract_version"] != entry["capability"]["version"]:
            errors.append(f"{r['id']}: version mismatch")
        oset = PC.extended_get_set(r["reflex_type"], r["candidates"])
        if PC.option_ids_for(oset) != r["option_ids"]:
            errors.append(f"{r['id']}: option mapping mismatch")
        if oset["fallback"] != r["fallback_id"]:
            errors.append(f"{r['id']}: fallback mismatch")
        if not (1 <= len(oset["options"]) <= 8):
            errors.append(f"{r['id']}: option count out of range")
        flags = FAMILY_FLAGS.get(r["family"], {})
        if r["family"] == "handoff" and r["contract_id"] == "appletv_play":
            flags = {"handoff_offline": True}
        want, _ = PC.disposition_for(entry, r["typed_arguments"],
                                     r["utterance"], flags)
        if want != r["expected_disposition"]:
            errors.append(
                f"{r['id']}: disposition {r['expected_disposition']} != {want}")
        if r["label_status"] != "needs_teacher":
            errors.append(f"{r['id']}: label_status must be needs_teacher")
    # Train must cover every contract.
    cov = json.loads((HERE / "phone_coverage.json").read_text())
    for cid, c in cov.items():
        if c["train"]["rows"] == 0:
            errors.append(f"contract {cid} has no train rows")
    # Leakage vs frozen held-out groups and eval contexts.
    held_groups = set()
    for split in ("dev", "calfit", "report"):
        for r in load(HERE / f"data_{split}.jsonl"):
            held_groups.add(r["group_id"])
    for r in all_rows:
        if group_key(r["context"]) in held_groups:
            errors.append(f"{r['id']}: group collides with frozen held-out")
            break
    kept, dropped = D.check(
        [{"id": r["id"], "context": r["context"]} for r in all_rows],
        D.eval_items())
    if dropped:
        errors.append(f"dedupe dropped {len(dropped)} phone rows vs eval")
    # Held-out hashes preserved.
    dman = json.loads((HERE / "data_manifest.json").read_text())
    for split, info in dman["splits"].items():
        p = HERE / info["file"]
        if hashlib.sha256(p.read_bytes()).hexdigest() != info["sha256"]:
            errors.append(f"held-out {split} hash changed")
    return errors


def main():
    errs = validate()
    if errs:
        print("\n".join(errs[:50]))
        print(f"FAIL {len(errs)} errors")
        raise SystemExit(1)
    print("phone_validate PASS")


if __name__ == "__main__":
    main()
