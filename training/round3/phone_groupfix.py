"""Build phone v2 splits with content-true source grouping.

v1 grouped by (contract, family, instance), which split identical
wrapper-free contexts across splits. v2 unions rows transitively when
they share a v1 group OR a canonical content key:
(reflex_type, wrapper-free context, canonical candidates). Wrapper
lines Now/User location/Network never distinguish a group; permission,
interruption, executor, and shared-document lines stay in the core
context and do distinguish it. Candidate order never distinguishes a
group. Splits assign whole v2 groups by hash (no score-driven choice).

  python3 training/round3/phone_groupfix.py
Writes phone_v2_* files; v1 files stay immutable.
"""
import hashlib
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "training" / "local_teacher"))
import dedupe as D

WRAPPER = re.compile(r"^(Now:|User location:|Network:)\s")


def core_context(context):
    lines = [l for l in context.splitlines() if not WRAPPER.match(l.strip())]
    return "\n".join(lines).strip()


def canonical_key(row):
    core = re.sub(r"\s+", " ", core_context(row["context"])).casefold().strip()
    cands = row.get("candidates") or []
    canon_cands = tuple(sorted(re.sub(r"\s+", " ", c).casefold().strip() for c in cands))
    return (row["reflex_type"], core, canon_cands)


def canonical_str(row):
    t, core, cands = canonical_key(row)
    return t + "\n" + core + "\n" + "\n".join(cands)


def v2_group_id(row):
    return "pg2-" + hashlib.sha256(canonical_str(row).encode()).hexdigest()[:14]


class DSU:
    def __init__(self):
        self.p = {}

    def find(self, x):
        p = self.p.setdefault(x, x)
        if p != x:
            self.p[x] = self.find(p)
        return self.p[x]

    def union(self, a, b):
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.p[rb] = ra


def build_v2(rows):
    """Return rows with group_v2 + split. Pure; no file IO."""
    dsu = DSU()
    by_v1, by_canon = {}, {}
    for r in rows:
        dsu.find(r["id"])
    by_ctx = {}
    for r in rows:
        if r["group_id"] in by_v1:
            dsu.union(by_v1[r["group_id"]], r["id"])
        else:
            by_v1[r["group_id"]] = r["id"]
        key = canonical_str(r)
        if key in by_canon:
            dsu.union(by_canon[key], r["id"])
        else:
            by_canon[key] = r["id"]
        # skillPick distractors are sampled, not scenario semantics:
        # the same context with different distractors stays one group.
        if r["reflex_type"] == "skillPick":
            t, core, _ = canonical_key(r)
            ck = t + "\n" + core
            if ck in by_ctx:
                dsu.union(by_ctx[ck], r["id"])
            else:
                by_ctx[ck] = r["id"]
    roots = defaultdict(list)
    for r in rows:
        roots[dsu.find(r["id"])].append(r)
    # Deterministic v2 id per union: hash of sorted member canonical keys.
    gid_of_root = {}
    for root, members in roots.items():
        keys = sorted({canonical_str(m) for m in members})
        gid_of_root[root] = "pg2-" + hashlib.sha256(
            "\n==\n".join(keys).encode()).hexdigest()[:14]
    for r in rows:
        r["group_v2"] = gid_of_root[dsu.find(r["id"])]
    groups = sorted({r["group_v2"] for r in rows})
    train_g, dev_g, cal_g = set(), set(), set()
    for gid in groups:
        v = int(hashlib.sha256(gid.encode()).hexdigest()[:8], 16) % 100
        (train_g if v < 70 else dev_g if v < 85 else cal_g).add(gid)
    by_contract = defaultdict(set)
    for r in rows:
        by_contract[r["contract_id"]].add(r["group_v2"])
    moved = 0
    for cid, gids in sorted(by_contract.items()):
        if not (gids & train_g):
            cand = sorted(gids)[0]
            dev_g.discard(cand); cal_g.discard(cand); train_g.add(cand)
            moved += 1
    for r in rows:
        r["split_v2"] = ("train" if r["group_v2"] in train_g
                         else "dev" if r["group_v2"] in dev_g else "calfit")
    stats = {"v2_groups": len(groups), "train_groups": len(train_g),
             "dev_groups": len(dev_g), "calfit_groups": len(cal_g),
             "moved_for_coverage": moved}
    return rows, stats


def audit(rows):
    """Canonical contexts per split; overlaps must be empty."""
    seen = {}
    overlaps = 0
    for r in rows:
        k = canonical_str(r)
        if k in seen and seen[k] != r["split_v2"]:
            overlaps += 1
        seen.setdefault(k, r["split_v2"])
    canon = Counter(canonical_str(r) for r in rows)
    return {"distinct_canonical": len(canon), "cross_split_canonical": overlaps,
            "rows_in_repeated_canonical": sum(1 for r in rows if canon[canonical_str(r)] > 1)}


def main():
    rows = [json.loads(l) for l in (HERE / "phone_inputs_all.jsonl").read_text().splitlines() if l.strip()]
    rows, stats = build_v2(rows)
    aud = audit(rows)
    if aud["cross_split_canonical"]:
        raise SystemExit(f"v2 audit failed: {aud}")
    rows.sort(key=lambda r: r["id"])
    out_all = HERE / "phone_v2_inputs_all.jsonl"
    out_all.write_text("".join(json.dumps(r) + "\n" for r in rows))
    splits = {}
    contracts = sorted({r["contract_id"] for r in rows})
    for split in ("train", "dev", "calfit"):
        part = [r for r in rows if r["split_v2"] == split]
        p = HERE / f"phone_v2_inputs_{split}.jsonl"
        p.write_text("".join(json.dumps(r) + "\n" for r in part))
        splits[split] = {"file": p.name, "rows": len(part),
                         "groups": len({r["group_v2"] for r in part}),
                         "canonical": len({canonical_str(r) for r in part}),
                         "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
    sparse = {}
    for cid in contracts:
        sparse[cid] = {s: len({r["group_v2"] for r in rows
                               if r["contract_id"] == cid and r["split_v2"] == s})
                       for s in ("train", "dev", "calfit")}
    manifest = {"builder": "training/round3/phone_groupfix.py",
                "source_all": "phone_inputs_all.jsonl",
                "source_all_sha256": hashlib.sha256((HERE / "phone_inputs_all.jsonl").read_bytes()).hexdigest(),
                "rows": len(rows), "audit": aud, "split_stats": stats,
                "splits": splits, "sparse_groups_by_contract": sparse,
                "sparse_note": "Contracts with 0 dev/calfit groups are NOT MEASURED on that split. No score-driven splitting was used.",
                "v1_note": "v1 splits leak identical canonical contexts across train/dev/calfit and must not be evaluated as independent. v1 files are preserved immutable."}
    (HERE / "phone_v2_manifest.json").write_text(json.dumps(manifest, indent=2))
    print(json.dumps({"rows": len(rows), **stats, **aud, "splits": splits}, indent=1))


if __name__ == "__main__":
    main()
