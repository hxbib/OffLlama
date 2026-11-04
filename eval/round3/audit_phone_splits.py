"""Audit immutable phone splits without loading models or calling paid services.

Exact decision-input and source-group overlap fail the audit. Wrapper-free
context overlap is a conservative diagnostic: time/network can be meaningful,
so those collisions require adjudication rather than automatic relabeling.
This does not establish semantic independence or correctness of teacher labels.
"""
import argparse
from collections import Counter
import gzip
import hashlib
from itertools import combinations
import json
from pathlib import Path
import re


def canonical_context(row):
    lines = [line for line in row["context"].splitlines()
             if not re.match(r"^(Now:|User location:|Network:)\s", line.strip())]
    return re.sub(r"\s+", " ", "\n".join(lines)).strip().casefold()


def decision_key(row, kind):
    decision_type = row.get("reflex_type") or row.get("type") or row.get("decision_type")
    if not decision_type:
        raise ValueError(f"Missing decision type: {row.get('id')}")
    context = canonical_context(row) if kind == "wrapper_free_context" else row["context"]
    values = [decision_type, context]
    if kind == "exact_decision_input":
        values.extend([row.get("candidates"), row.get("option_ids")])
    return json.dumps(values, ensure_ascii=False, sort_keys=True)


def audit(folder):
    freeze = json.loads((folder / "FREEZE.json").read_text())
    rows_by_split, files = {}, {}
    for split in ("train", "dev", "calfit"):
        name = f"phone_inputs_{split}.jsonl"
        path = folder / name
        raw = path.read_bytes() if path.exists() else gzip.decompress((folder / (name + ".gz")).read_bytes())
        digest = hashlib.sha256(raw).hexdigest()
        rows = [json.loads(line) for line in raw.splitlines() if line.strip()]
        if digest != freeze["files"][name]["sha256"] or len(rows) != freeze["files"][name]["rows"]:
            raise ValueError(f"Freeze hash/count mismatch: {name}")
        if len({row["id"] for row in rows}) != len(rows):
            raise ValueError(f"Duplicate row IDs within {name}")
        rows_by_split[split] = rows
        files[split] = {"sha256": digest, "rows": len(rows),
                        "groups": len({row["group_id"] for row in rows})}
    comparisons, failures = [], []
    for left, right in combinations(rows_by_split, 2):
        left_rows, right_rows = rows_by_split[left], rows_by_split[right]
        common_groups = {r["group_id"] for r in left_rows} & {r["group_id"] for r in right_rows}
        common_ids = {r["id"] for r in left_rows} & {r["id"] for r in right_rows}
        if common_groups or common_ids:
            failures.append(f"{left}/{right}: shared group or row IDs")
        pair = {"left": left, "right": right, "shared_groups": len(common_groups),
                "shared_row_ids": len(common_ids), "overlap": {}}
        for kind in ("exact_decision_input", "exact_context", "wrapper_free_context"):
            left_index = {}
            for row in left_rows:
                left_index.setdefault(decision_key(row, kind), []).append(row["id"])
            affected = [r for r in right_rows if decision_key(r, kind) in left_index]
            distinct = {decision_key(r, kind) for r in affected}
            pair["overlap"][kind] = {
                "shared_keys": len(distinct), "affected_right_rows": len(affected),
                "by_type": dict(Counter(r.get("reflex_type") or r.get("type") or r.get("decision_type") for r in affected)),
                "examples": [{"right_id": r["id"], "left_ids": left_index[decision_key(r, kind)][:3]}
                             for r in affected[:5]],
            }
            if kind == "exact_decision_input" and affected:
                failures.append(f"{left}/{right}: {len(affected)} rows repeat exact decision inputs")
        comparisons.append(pair)
    return {"passes_exact_overlap_gate": not failures, "failures": failures,
            "files": files, "comparisons": comparisons,
            "limitations": ["No teacher correctness or model quality measured.",
                            "Disjoint IDs alone do not establish independent scenarios.",
                            "Wrapper-free collisions require semantic adjudication."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("freeze_directory", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = audit(args.freeze_directory)
    rendered = json.dumps(result, indent=2) + "\n"
    if args.output:
        args.output.write_text(rendered)
    else:
        print(rendered, end="")
    return 0 if result["passes_exact_overlap_gate"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
