"""Phone LoRA trainer. Math identical to training/round2/lora_r2.py.

Differences are only plumbing: skillPick dynamic sets via
phone_contracts.extended_get_set, and a --seed flag for multi-seed
experiments. Loss stays weight * (soft cross-entropy + ceWeight * CE)
at the answer-letter position, zeroShot prompts, AdamW warmup+cosine.
"""
import argparse, json, math, sys, time, random
from pathlib import Path
import torch
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "training"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from pg_train import prompts
import phone_contracts as PC

ap = argparse.ArgumentParser()
ap.add_argument("--base", required=True); ap.add_argument("--train", required=True)
ap.add_argument("--out", required=True); ap.add_argument("--epochs", type=float, default=1)
ap.add_argument("--lr", type=float, default=2e-4); ap.add_argument("--bsz", type=int, default=8)
ap.add_argument("--max-hours", type=float, default=0.4); ap.add_argument("--test", required=True)
ap.add_argument("--dtype", choices=["float32", "bfloat16"], default="bfloat16")
ap.add_argument("--micro", type=int, default=0); ap.add_argument("--grad-ckpt", action="store_true")
ap.add_argument("--ce-weight", type=float, default=0.5); ap.add_argument("--rank", type=int, default=16)
ap.add_argument("--label-smooth", type=float, default=0.0); ap.add_argument("--conf-weight", action="store_true")
ap.add_argument("--glimmer-weight", type=float, default=1.0); ap.add_argument("--entropy-bonus", type=float, default=0.0)
ap.add_argument("--skip-before", action="store_true"); ap.add_argument("--threads", type=int, default=8)
ap.add_argument("--max-steps", type=int, default=0); ap.add_argument("--seed", type=int, default=0)
a = ap.parse_args()
torch.set_num_threads(a.threads); torch.manual_seed(a.seed)
DEV = "cuda" if torch.cuda.is_available() else "cpu"
from transformers import AutoModelForCausalLM, AutoTokenizer
from peft import LoraConfig, get_peft_model
tok = AutoTokenizer.from_pretrained(a.base); tok.padding_side = "left"; tok.pad_token = tok.eos_token
LID = [tok(" " + c, add_special_tokens=False)["input_ids"][0] for c in prompts.LETTERS]
model = AutoModelForCausalLM.from_pretrained(a.base, dtype=getattr(torch, a.dtype)).to(DEV)


@torch.no_grad()
def evaluate(m, style):
    m.eval(); f = a.test; items = [json.loads(l) for l in open(f) if l.strip()]; ok = 0; per = {}; confs = []
    for i in range(0, len(items), 8):
        b = items[i:i + 8]; sets = [PC.extended_get_set(g["type"], g.get("candidates")) for g in b]
        enc = tok([prompts.llama3(s, g["context"], style) for s, g in zip(sets, b)], return_tensors="pt", padding=True, add_special_tokens=False).to(DEV)
        lg = m(**enc).logits[:, -1, :].float()
        for j, (s, g) in enumerate(zip(sets, b)):
            n = len(s["options"]); p = torch.softmax(lg[j, LID[:n]], -1); k = int(torch.argmax(p)); hit = s["options"][k]["id"] == g["gold"]
            ok += hit; pp = per.setdefault(g["type"], [0, 0]); pp[0] += hit; pp[1] += 1; confs.append(float(p[k]))
    return {"file": Path(f).name, "style": style, "n": len(items), "acc": ok / len(items), "mean_conf": sum(confs) / len(confs), "per_type": per}


res = {"args": vars(a)}
if not a.skip_before: res["before_zeroShot"] = evaluate(model, "zeroShot"); print(json.dumps(res), flush=True)
model = get_peft_model(model, LoraConfig(r=a.rank, lora_alpha=a.rank, lora_dropout=0.0, task_type="CAUSAL_LM",
                       target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"]))
rows = [json.loads(l) for l in open(a.train)]; random.Random(a.seed).shuffle(rows)
steps = math.ceil(len(rows) * a.epochs / a.bsz)
opt = torch.optim.AdamW([p for p in model.parameters() if p.requires_grad], lr=a.lr)
sched = torch.optim.lr_scheduler.LambdaLR(opt, lambda s: min(1, (s + 1) / 10) * 0.5 * (1 + math.cos(math.pi * s / steps)))
if a.grad_ckpt:
    model.gradient_checkpointing_enable(); model.enable_input_require_grads(); model.config.use_cache = False
MICRO = a.micro or a.bsz


def row_weight(r):
    w = r["weight"]
    if a.conf_weight: w *= r.get("teacher_conf", 1.0)
    if a.glimmer_weight != 1.0 and str(r.get("teacher", "")).startswith("muse-glimmer"): w *= a.glimmer_weight
    return w


model.train(); t0 = time.time()
for st in range(steps):
    b = [rows[(st * a.bsz + i) % len(rows)] for i in range(a.bsz)]
    tot = 0.0
    for c in range(0, len(b), MICRO):
        mb = b[c:c + MICRO]; sets = [PC.extended_get_set(r["type"], r.get("candidates")) for r in mb]
        enc = tok([prompts.llama3(s, r["context"], "zeroShot") for s, r in zip(sets, mb)], return_tensors="pt", padding=True, add_special_tokens=False).to(DEV)
        lg = model(**enc).logits[:, -1, :].float(); loss = 0
        for j, (s, r) in enumerate(zip(sets, mb)):
            n = len(s["options"]); ls = torch.log_softmax(lg[j, LID[:n]], -1)
            q = torch.tensor([r["soft"].get(prompts.LETTERS[i], 0.0) for i in range(n)], device=DEV); q = q / q.sum()
            if a.label_smooth: q = (1 - a.label_smooth) * q + a.label_smooth / n
            kd = -(q * ls).sum(); ce = -ls[prompts.LETTERS.index(r["target"])]
            term = kd + a.ce_weight * ce
            if a.entropy_bonus: term = term + a.entropy_bonus * (ls.exp() * ls).sum()
            loss = loss + row_weight(r) * term
        loss = loss / len(b); loss.backward(); tot += loss.item()
    loss = torch.tensor(tot); opt.step(); sched.step(); opt.zero_grad()
    el = time.time() - t0
    if st % 25 == 0: print(f"step {st+1}/{steps} loss {loss.item():.4f} {el/(st+1):.2f}s/step eta {(steps-st-1)*el/(st+1)/60:.1f}min", flush=True)
    if a.max_steps and st + 1 >= a.max_steps: print(f"BENCH {el/(st+1):.2f}s/step", flush=True); break
    if st == 4 and steps * el / 5 / 3600 > a.max_hours:
        print(f"ABORT: projected {steps*el/5/3600:.2f} h > {a.max_hours} h budget", flush=True); res["aborted"] = True; break
model.save_pretrained(a.out)
res["after_zeroShot"] = evaluate(model, "zeroShot"); res["train_rows"] = len(rows); res["steps_done"] = st + 1; res["steps"] = steps
res["train_seconds"] = time.time() - t0
Path(a.out).mkdir(parents=True, exist_ok=True); (Path(a.out) / "eval_before_after.json").write_text(json.dumps(res, indent=1))
print(json.dumps(res), flush=True)
