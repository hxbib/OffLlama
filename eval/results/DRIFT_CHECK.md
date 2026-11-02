# Drift check: does the ep1 floor LoRA hurt the 1B outside routing? (2026-11-02)

**Verdict: no meaningful drift.**

## Method
- Models: Llama 3.2 1B Instruct base (`/workspace/pg-lora-venv/llama32-1b-instruct`, HF bf16) vs base + **ep1 SHIPPING adapter** (`training/local_teacher/out/lora-llama1b-glimmer`, r16). Same weights in one process; base = `peft.disable_adapter()`. HF/PyTorch on box CPU, **not** the Q4_K_M GGUF, so quantization effects are not measured here. (The shipping GGUF on the box, `lora-llama1b-glimmer-merged/...Q4_K_M.gguf`, has sha256 a5c60a88…82c2, which matches the LFS pointer.)
- Prompts: 40 hand-written general prompts in `eval/drift/prompts.jsonl`: 10 math word problems, 10 facts, 7 rewrite/summarize/translate, 6 casual chat, 7 instruction following. 23 have checkable answers. None of them are about routing.
- Chat template: the tokenizer's default template, with a single user turn and no system prompt. Same template for both models.
- (a) KL: mean per-token KL(base || tuned), teacher-forced over the base model's own greedy continuation (first ≤64 tokens).
- (b) Greedy outputs from both models, 96 new tokens max.
- Quality: case-insensitive "contains" match against the answer list (whole number for digits).
- Collapse: regex for JSON/routing/label text (`{`/`[` at line start, `"key":`, `request_type|route|label|intent|category:`, ALL-CAPS lone token) + eyeball of all 10 differing outputs.
- No cloud, no trust_remote_code. Script: `eval/drift/run_drift.py`. Raw: `eval/drift/outputs.jsonl`. Runtime: 143 s generation+KL (8 CPU threads).

## Numbers
| metric | value |
|---|---|
| mean per-token KL(base‖tuned), avg over 40 prompts | **0.0096 nats** |
| median / max per-prompt mean KL | 0.0036 / 0.0474 |
| max single-token KL | 0.361 |
| greedy outputs byte-identical | 30 / 40 |
| checkable answers correct: base vs tuned | **23/23 vs 23/23** |
| collapse into routing/JSON/label text: base vs tuned | **0 vs 0** (regex and eyeball) |

## Side-by-side (all differences are in wording)
1. *Rewrite in passive: 'The cat chased the mouse.'* (KL 0.011). Base: `'Mice were chased by the cat.'`. Tuned: `'Mouse was chased by the cat.'`. Both are wrong in the same way (the correct answer is "The mouse was chased by the cat."). This is the only difference that touches quality, and it is a toss-up.
2. *Who wrote Romeo and Juliet?* (KL 0.018). Base: "...written by the renowned English playwright William Shakespeare." Tuned: "...written by William Shakespeare. It is one of his most famous tragedies..." Both correct.
3. *Formal rewrite of 'hey, can u send me the report asap?'* (KL 0.008). Both give "Could you please send me the report as soon as possible?" and the preamble differs by one phrase.
4. *One sentence describing a sunset* (KL 0.014). The tuned output is the same sentence in the past tense ("unfolded/transformed/dipped").
5. *Good friend?* (KL 0.003). One word differs ("empathetic" vs "reliable").

## Caveats
40 prompts is a smoke test, not a benchmark. Measured in bf16 HF, not in the Q4_K_M GGUF that runs on the phone. The KL is computed on base-greedy text only.
