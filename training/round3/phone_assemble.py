"""Assemble frozen trainer datasets and the declared recipe matrix.

Inputs are the verified Glimmer label files. Outputs land in the ignored
phone-training-v1/train directory as trainer JSONL plus eval JSONL
(gold = held-out teacher top) and a matrix manifest with SHA-256 for
every file. No training, no spend.

  python3 training/round3/phone_assemble.py
"""
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import phone_convert as CV

OUT = Path("/tmp/pocket-glimmer-training-scale/phone-training-v1/train")
GLIMMER_CTRL_LABELS = "/tmp/pocket-glimmer-training-scale/glimmer-v2/labels.jsonl"
PHONE_LABELS = "/tmp/pocket-glimmer-training-scale/phone-training-v1/glimmer-phone/labels-phone.jsonl"
BROADER_LABELS = "/tmp/pocket-glimmer-training-scale/phone-training-v1/glimmer-phone/labels-broader.jsonl"
BROADER_INPUTS = "/tmp/pocket-glimmer-training-scale/phone-training-v1/broader_inputs.jsonl"


def load(p):
    return [json.loads(l) for l in Path(p).read_text().splitlines() if l.strip()]


def dump(name, rows):
    p = OUT / name
    p.write_text("".join(json.dumps(r) + "\n" for r in rows))
    return {"file": str(p), "rows": len(rows),
            "sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
            "by_type": dict(Counter(r["type"] for r in rows)),
            "by_src": dict(Counter(r.get("src", "eval") for r in rows))}


def eval_rows(trainer_rows):
    return [{"id": r["id"], "type": r["type"], "context": r["context"],
             "candidates": r["candidates"],
             "gold": r["soft"] and max(r["soft"], key=lambda L: r["soft"][L])}
            for r in trainer_rows]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    ctrl_inputs = load(HERE / "target_comparison_inputs.jsonl")
    ctrl_labels = load(GLIMMER_CTRL_LABELS)
    ctrl, cs = CV.convert_glimmer(ctrl_inputs, ctrl_labels, "glimmer_ctrl_bf16")
    phone_all = load(HERE / "phone_v2_inputs_all.jsonl")
    phone_labels = load(PHONE_LABELS)
    # Identical prompts (same type/context/candidates) share one teacher
    # readout by prompt hash; clone it to duplicate input ids.
    labeled_ids = {l["id"] for l in phone_labels}
    by_key = {}
    inp_by_id = {r["id"]: r for r in phone_all}
    def pkey(r):
        return json.dumps([r.get("type") or r.get("reflex_type"), r["context"], r.get("candidates")], sort_keys=True)
    for l in phone_labels:
        src = inp_by_id.get(l["id"])
        if src is not None:
            by_key[pkey(src)] = l
    repaired = 0
    for r in phone_all:
        if r["id"] not in labeled_ids and pkey(r) in by_key:
            phone_labels.append({**by_key[pkey(r)], "id": r["id"], "reused_prompt_hash": True})
            repaired += 1
    phone_conv, ps = CV.convert_glimmer(phone_all, phone_labels, "phone_glimmer_bf16")
    ps["repaired_duplicate_prompts"] = repaired
    by_id = {r["id"]: r for r in phone_all}
    phone_train = [r for r in phone_conv if by_id[r["id"]]["split_v2"] == "train"]
    phone_dev = [r for r in phone_conv if by_id[r["id"]]["split_v2"] == "dev"]
    phone_cal = [r for r in phone_conv if by_id[r["id"]]["split_v2"] == "calfit"]
    broader_inputs = load(BROADER_INPUTS)
    broader_labels = load(BROADER_LABELS)
    broader, bs = CV.convert_glimmer(broader_inputs, broader_labels, "broader_glimmer_bf16")
    # Eval gold must be option ids, not letters.
    import phone_contracts as PC
    def to_eval(rows):
        out = []
        for r in rows:
            oset = PC.extended_get_set(r["type"], r["candidates"])
            out.append({"id": r["id"], "type": r["type"], "context": r["context"],
                        "candidates": r["candidates"],
                        "gold": PC.id_for_letter(oset, r["target"])})
        return out
    files = {
        "ctrl": dump("train_ctrl.jsonl", ctrl),
        "phone_train": dump("train_phone_only.jsonl", phone_train),
        "broader": dump("train_broader_only.jsonl", broader),
        "D_CTRL": dump("D_CTRL.jsonl", ctrl),
        "D_PHONE": dump("D_PHONE.jsonl", ctrl + phone_train),
        "D_FULL": dump("D_FULL.jsonl", ctrl + phone_train + broader),
        "phone_dev_eval": dump("phone_dev_eval.jsonl", to_eval(phone_dev)),
        "phone_calfit_eval": dump("phone_calfit_eval.jsonl", to_eval(phone_cal)),
    }
    matrix = [
        {"name": "PG-C1-CTRL-V4-s0", "train": files["D_CTRL"]["file"],
         "flags": ["--lr", "1e-4", "--conf-weight", "--seed", "0"],
         "isolates": "teacher change only (bf16 Glimmer on 2915)"},
        {"name": "PG-C2-PHONE-V4-s0", "train": files["D_PHONE"]["file"],
         "flags": ["--lr", "1e-4", "--conf-weight", "--seed", "0"],
         "isolates": "phone data volume vs C1, matched recipe"},
        {"name": "PG-C3-FULL-V4-s0", "train": files["D_FULL"]["file"],
         "flags": ["--lr", "1e-4", "--conf-weight", "--seed", "0"],
         "isolates": "broader 3964 addition vs C2, matched recipe"},
        {"name": "PG-C4-PHONE-V4-s1", "train": files["D_PHONE"]["file"],
         "flags": ["--lr", "1e-4", "--conf-weight", "--seed", "1"],
         "isolates": "seed robustness vs C2"},
        {"name": "PG-C5-PHONE-CE0-s0", "train": files["D_PHONE"]["file"],
         "flags": ["--lr", "1e-4", "--conf-weight", "--ce-weight", "0", "--seed", "0"],
         "isolates": "hard-CE contribution vs C2"},
    ]
    manifest = {"datasets": files,
                "convert_stats": {"ctrl": cs, "phone": ps, "broader": bs},
                "phone_usable_by_split": {"train": len(phone_train),
                                          "dev": len(phone_dev),
                                          "calfit": len(phone_cal)},
                "candidates": matrix,
                "cal_for_trainer_readout": files["phone_calfit_eval"]["file"],
                "recipe_common": "Llama-3.2-1B-Instruct (unsloth mirror), LoRA r16/a16 all-linear, zeroShot, bsz8, 1 epoch. No two-epoch repeat.",
                "spark_reserve": "Spark-expansion candidates are additional named rows appended later only after ingest checks; C1-C5 stay frozen baselines."}
    (OUT / "matrix.json").write_text(json.dumps(manifest, indent=2))
    print(json.dumps({"ctrl": cs, "phone": ps, "broader": bs,
                      "phone_splits": manifest["phone_usable_by_split"]}, indent=1))


if __name__ == "__main__":
    main()
