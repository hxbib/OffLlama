"""CPU LoRA distillation of Llama 3.2 1B Instruct on Glimmer soft labels (zeroShot Reflex prompt, loss only on the
answer-letter position: weighted KL(teacher soft || student over letter tokens) + 0.5*CE(hard)). Also scores the
base model and the LoRA student on the held-out test split with the same letter-logit readout.
  /workspace/pg-lora-venv/bin/python lora_cpu.py --train out/distill_train.jsonl --out out/lora-llama1b-glimmer
GPU equivalent: python -m pg_train.sft_unsloth --base unsloth/Llama-3.2-1B-Instruct --train <train.jsonl with target> --out ... --load-4bit"""
import argparse, glob, json, math, sys, time, random
from pathlib import Path
import torch
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "training"))
from pg_train import prompts

ap = argparse.ArgumentParser()
ap.add_argument("--base", default="/workspace/pg-lora-venv/llama32-1b-instruct"); ap.add_argument("--train", required=True)
ap.add_argument("--out", required=True); ap.add_argument("--epochs", type=float, default=1); ap.add_argument("--lr", type=float, default=2e-4)
ap.add_argument("--bsz", type=int, default=8); ap.add_argument("--max-hours", type=float, default=5.0)
ap.add_argument("--test", default="")
# Low-memory floor options (defaults reproduce the original fp32 / bsz-8 run exactly)
ap.add_argument("--dtype", choices=["float32", "bfloat16"], default="float32")
ap.add_argument("--micro", type=int, default=0, help="micro-batch size for grad accumulation (0 = bsz)")
ap.add_argument("--grad-ckpt", action="store_true"); a = ap.parse_args()
torch.set_num_threads(8); torch.manual_seed(0)
from transformers import AutoModelForCausalLM, AutoTokenizer
from peft import LoraConfig, get_peft_model
tok = AutoTokenizer.from_pretrained(a.base); tok.padding_side = "left"; tok.pad_token = tok.eos_token
LID = [tok(" " + c, add_special_tokens=False)["input_ids"][0] for c in prompts.LETTERS]
model = AutoModelForCausalLM.from_pretrained(a.base, torch_dtype=getattr(torch, a.dtype))

def test_items():
    cands = [f for f in glob.glob(str(ROOT / "eval/**/*test*.jsonl"), recursive=True)]
    f = a.test or (cands[0] if cands else str(ROOT / "eval/gold_decisions_v2.jsonl"))
    return f, [json.loads(l) for l in open(f) if l.strip()]

@torch.no_grad()
def evaluate(m, style):
    m.eval(); f, items = test_items(); ok = 0; per = {}
    for i in range(0, len(items), 8):
        b = items[i:i + 8]; sets = [prompts.get_set(g["type"], g.get("candidates")) for g in b]
        enc = tok([prompts.llama3(s, g["context"], style) for s, g in zip(sets, b)], return_tensors="pt", padding=True, add_special_tokens=False)
        lg = m(**enc).logits[:, -1, :].float()
        for j, (s, g) in enumerate(zip(sets, b)):
            n = len(s["options"]); k = int(torch.argmax(lg[j, LID[:n]])); hit = s["options"][k]["id"] == g["gold"]
            ok += hit; p = per.setdefault(g["type"], [0, 0]); p[0] += hit; p[1] += 1
    return {"file": str(Path(f).resolve().relative_to(ROOT)), "style": style, "n": len(items), "acc": ok / len(items), "per_type": per}

res = {"before_fewShot": evaluate(model, "fewShot"), "before_zeroShot": evaluate(model, "zeroShot")}
print(json.dumps(res), flush=True)
model = get_peft_model(model, LoraConfig(r=16, lora_alpha=16, lora_dropout=0.0, task_type="CAUSAL_LM",
                       target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"]))
rows = [json.loads(l) for l in open(a.train)]; random.Random(0).shuffle(rows)
steps = math.ceil(len(rows) * a.epochs / a.bsz)
opt = torch.optim.AdamW([p for p in model.parameters() if p.requires_grad], lr=a.lr)
sched = torch.optim.lr_scheduler.LambdaLR(opt, lambda s: min(1, (s + 1) / 10) * 0.5 * (1 + math.cos(math.pi * s / steps)))
if a.grad_ckpt:
    model.gradient_checkpointing_enable(); model.enable_input_require_grads(); model.config.use_cache = False
MICRO = a.micro or a.bsz
model.train(); t0 = time.time()
for st in range(steps):
    b = [rows[(st * a.bsz + i) % len(rows)] for i in range(a.bsz)]
    tot = 0.0
    for c in range(0, len(b), MICRO):
        mb = b[c:c + MICRO]; sets = [prompts.get_set(r["type"], r.get("candidates")) for r in mb]
        enc = tok([prompts.llama3(s, r["context"], "zeroShot") for s, r in zip(sets, mb)], return_tensors="pt", padding=True, add_special_tokens=False)
        lg = model(**enc).logits[:, -1, :].float(); loss = 0
        for j, (s, r) in enumerate(zip(sets, mb)):
            n = len(s["options"]); ls = torch.log_softmax(lg[j, LID[:n]], -1)
            q = torch.tensor([r["soft"].get(prompts.LETTERS[i], 0.0) for i in range(n)]); q = q / q.sum()
            kd = -(q * ls).sum(); ce = -ls[prompts.LETTERS.index(r["target"])]
            loss = loss + r["weight"] * (kd + 0.5 * ce)
        loss = loss / len(b); loss.backward(); tot += loss.item()
    loss = torch.tensor(tot); opt.step(); sched.step(); opt.zero_grad()
    el = time.time() - t0
    if st % 5 == 0: print(f"step {st+1}/{steps} loss {loss.item():.4f} {el/(st+1):.1f}s/step eta {(steps-st-1)*el/(st+1)/60:.0f}min", flush=True)
    if st == 4 and steps * el / 5 / 3600 > a.max_hours:
        print(f"ABORT: projected {steps*el/5/3600:.1f} h > {a.max_hours} h budget", flush=True); res["aborted"] = True; break
model.save_pretrained(a.out)
res["after_zeroShot"] = evaluate(model, "zeroShot"); res["train_rows"] = len(rows); res["steps_done"] = st + 1; res["steps"] = steps
res["train_seconds"] = time.time() - t0
Path(a.out).mkdir(parents=True, exist_ok=True); (Path(a.out) / "eval_before_after.json").write_text(json.dumps(res, indent=1))
print(json.dumps(res), flush=True)
