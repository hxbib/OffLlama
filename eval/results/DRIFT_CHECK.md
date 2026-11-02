# Drift check: does the ep1 floor LoRA hurt the 1B outside routing? (2026-11-02)

**Verdict, scoped:**
- **The LoRA doesn't degrade the full-precision 1B (bf16): no meaningful drift.**
- **The shipping 4-bit file (Q4_K_M, sha256 a5c60a88…82c2) is clean on this set:** 23/23 checkable answers and 0 routing/JSON collapse. The differences from bf16 are about the same size as what Q4 quantization does to the base model alone.

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

## Shipping GGUF (added 2026-11-02 ~11:10 ET)
- Runtime: llama.cpp `llama-server` (commit ddf48f8, box CPU, 8 threads). Prompts are the exact HF chat-template token ids (sent as a token list, so there is no double BOS). Greedy (temperature 0, top_k 1), n_predict 96. Script: `eval/drift/run_drift_gguf.py`. Raw: `eval/drift/outputs_gguf_{shipping,baseq4}.jsonl`.
- Shipping file: `training/local_teacher/out/lora-llama1b-glimmer-merged/Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf` (sha256 a5c60a88…82c2, not modified).
- Base Q4 control: base HF weights → `convert_hf_to_gguf.py --outtype f16` → `llama-quantize Q4_K_M`, using the same llama.cpp tree as the shipping export (~23 s). Stored on the box at `/workspace/drift-gguf/base-Q4_K_M.gguf` and not committed.
- KL vs bf16 tuned: **not computed**. llama-server only exposes top-n probabilities, not full logits, so an exact KL wasn't cheap.

| | checkable correct | collapse | exact match bf16 tuned | exact match bf16 base |
|---|---|---|---|---|
| bf16 base (above) | 23/23 | 0 | 30/40 | 40/40 |
| bf16 base+ep1 (above) | 23/23 | 0 | 40/40 | 30/40 |
| **shipping Q4_K_M (ep1 merged)** | **23/23** | **0** | **23/40** | 23/40 |
| base Q4_K_M (control) | 22/23 | 0 | 21/40 | 21/40 |

- Shipping Q4 and base Q4 produce identical outputs on 27/40 prompts.
- The base Q4 control's one miss: "What is 81 divided by 9?" → "89". Shipping Q4 answers "9".
- Quantization moves the outputs about as much as the LoRA does. For example, the passive-voice prompt that both bf16 models got slightly wrong gets the correct "The mouse was chased by the cat." from **both** Q4 files. Q4 also tends to give shorter answers (e.g. the Red Planet answer stops after "Mars.").
- So, on this set, the shipping file shows no extra degradation beyond what Q4 does to the base. That is still 40 prompts, not a benchmark.
