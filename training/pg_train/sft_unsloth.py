"""System 1 distillation: LoRA rank-16 SFT with loss ONLY on the answer-letter token.

  # Llama 3.2 1B Instruct (fits a 12 GB RTX 3080 Ti in 4-bit QLoRA)
  python -m pg_train.sft_unsloth --base unsloth/Llama-3.2-1B-Instruct --train out/train.jsonl --out out/lora-llama1b --load-4bit
  # MobileMoE-L-SFT (A100 80GB, bf16; custom arch -> --no-unsloth uses transformers+peft with trust_remote_code)
  python -m pg_train.sft_unsloth --base facebook/MobileMoE-L-SFT --train out/train.jsonl --out out/lora-mmoe-l --no-unsloth --bf16

Requires: pip install -r requirements-gpu.txt (unsloth, transformers, peft, datasets, torch). Not runnable on the Linux box (no GPU)."""
import argparse, json
from pathlib import Path


def build_examples(rows, tok):
    """prompt ends with 'Answer:'; target is ' X' (single token for Llama-3 tokenizer). labels = -100 except that token."""
    from . import prompts
    ex = []
    for r in rows:
        s = prompts.get_set(r["type"], r.get("candidates"))
        p_ids = tok(prompts.llama3(s, r["context"], "zeroShot"), add_special_tokens=False)["input_ids"]
        a_ids = tok(" " + r["target"], add_special_tokens=False)["input_ids"]
        assert len(a_ids) == 1, f"answer letter must be one token, got {a_ids}"
        ids = p_ids + a_ids
        ex.append({"input_ids": ids, "attention_mask": [1] * len(ids), "labels": [-100] * len(p_ids) + a_ids})
    return ex


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True); ap.add_argument("--train", default="out/train.jsonl"); ap.add_argument("--out", required=True)
    ap.add_argument("--epochs", type=float, default=2); ap.add_argument("--lr", type=float, default=2e-4); ap.add_argument("--bsz", type=int, default=16)
    ap.add_argument("--grad-accum", type=int, default=1); ap.add_argument("--max-len", type=int, default=768)
    ap.add_argument("--load-4bit", action="store_true"); ap.add_argument("--bf16", action="store_true"); ap.add_argument("--no-unsloth", action="store_true")
    ap.add_argument("--include-escalate", action="store_true", default=True, help="keep disagreement rows (target=fallback) so the student learns to be unsure")
    a = ap.parse_args()

    import torch
    from transformers import Trainer, TrainingArguments, DataCollatorForSeq2Seq
    from datasets import Dataset

    targets = ["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"]
    if a.no_unsloth:
        from transformers import AutoModelForCausalLM, AutoTokenizer
        from peft import LoraConfig, get_peft_model
        tok = AutoTokenizer.from_pretrained(a.base, trust_remote_code=True)
        model = AutoModelForCausalLM.from_pretrained(a.base, trust_remote_code=True, torch_dtype=torch.bfloat16 if a.bf16 else torch.float16, device_map="auto")
        # MoE expert weights may use different names; LoRA on attention + shared MLP is the safe default.
        names = {n.split(".")[-1] for n, _ in model.named_modules()}
        model = get_peft_model(model, LoraConfig(r=16, lora_alpha=16, lora_dropout=0.0, target_modules=[t for t in targets if t in names], task_type="CAUSAL_LM"))
    else:
        from unsloth import FastLanguageModel
        model, tok = FastLanguageModel.from_pretrained(a.base, max_seq_length=a.max_len, load_in_4bit=a.load_4bit, dtype=None)
        model = FastLanguageModel.get_peft_model(model, r=16, lora_alpha=16, lora_dropout=0.0, target_modules=targets,
                                                 use_gradient_checkpointing="unsloth", random_state=0)
    if tok.pad_token is None: tok.pad_token = tok.eos_token
    rows = [json.loads(l) for l in Path(a.train).read_text().splitlines() if l.strip()]
    if not a.include_escalate: rows = [r for r in rows if not r["escalate"]]
    if any(r.get("dry_run") for r in rows): print("WARNING: training on DRY-RUN labels (local stand-in teacher)")
    ds = Dataset.from_list([e for e in build_examples(rows, tok) if len(e["input_ids"]) <= a.max_len])
    args = TrainingArguments(output_dir=a.out, per_device_train_batch_size=a.bsz, gradient_accumulation_steps=a.grad_accum,
                             num_train_epochs=a.epochs, learning_rate=a.lr, lr_scheduler_type="cosine", warmup_ratio=0.03,
                             logging_steps=10, save_strategy="epoch", bf16=a.bf16, fp16=not a.bf16 and torch.cuda.is_available(),
                             report_to=[], seed=0)
    Trainer(model=model, args=args, train_dataset=ds, data_collator=DataCollatorForSeq2Seq(tok, padding=True, label_pad_token_id=-100)).train()
    model.save_pretrained(a.out); tok.save_pretrained(a.out)
    print(f"saved LoRA adapter -> {a.out}. Next: bash export_gguf.sh {a.base} {a.out}")


if __name__ == "__main__":
    main()
