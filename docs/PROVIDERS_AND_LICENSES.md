# Providers, model IDs, prices, licenses (checked 2026-10-31)

## Meta Model API — https://dev.meta.ai/docs
- Base URL `https://api.meta.ai/v1` (OpenAI Chat Completions + Responses; Anthropic Messages at `https://api.meta.ai`). Header `Authorization: Bearer $MODEL_API_KEY`. [quickstart, models]
- Model IDs (docs/models, docs/pricing-rate-limits):

| Model | ID | Price | Limits |
|---|---|---|---|
| Muse Spark 1.3 | `muse-spark-1.3` | $1.25 in / $0.15 cached / $4.25 out per 1M | 3,000 RPM, 4M TPM |
| Muse Spark 1.3 Contributor | `muse-spark-1.3-contributor` | $0.10 / $0.002 / $0.20 (content may train Meta models) | 150 RPM, 3M TPM |
| Muse Wonder | `muse-wonder-1.0` | $4.00 / $0.20 / $20.00 | 3,000 RPM |
| SAM 3.1 | `sam-3.1` (Responses API) | $2.50 / 1k images; $0.20 / 1k video frames (min 50) | 3,000 RPM |
| Muse Voice Transcribe | `muse-voice-transcribe-1.0` | $0.18 / hour of audio | 256 concurrent streams |
| Muse Image | `muse-image-1.0` | $0.01 / image | 150 RPM |

- **Muse Glimmer and Muse Spark Open are not hosted on Meta Model API.** Both are open weights: run them yourself or through partners.
- **`logprobs: true` returns HTTP 400 on Muse Spark** (reasoning model; docs/protocols/chat-completions). The teacher therefore samples k=5 votes. `temperature` default 1.0; `reasoning_effort` `"none"` → 400.

## Partners
| Model | Provider | ID / slug | Price | logprobs | Source |
|---|---|---|---|---|---|
| Muse Spark Open (816B-A42B) | Fireworks serverless | `accounts/fireworks/models/muse-spark-open` | $1.25 / $0.15 / $4.25 | yes (top_logprobs ≤ 5) | docs.fireworks.ai/serverless/pricing; api-reference/post-chatcompletions |
| Muse Spark Open | Baseten Model APIs | `meta-models/muse-spark-open`, base `https://inference.baseten.co/v1` | $1.25 / $0.15 / $4.25 | **accepted but ignored** | baseten.co/library/muse-spark-open; docs.baseten.co/inference/model-apis/overview |
| Muse Glimmer 30B | Fireworks | `accounts/fireworks/models/muse-glimmer-30b` | serverless **deprecated 2026-09-25**; on-demand H100 $8/h | yes | fireworks.ai/models/fireworks/muse-glimmer-30b; fireworks.ai/pricing |
| Muse Glimmer 30B | Modal (vLLM, self-deployed / Dedicated Endpoint) | HF `meta-models/Muse-Glimmer-30B`, served as `muse-glimmer` | H100 $0.001097/s ≈ $3.95/h | yes (vLLM, ≤20) | modal.com/pricing; modal.com/library/meta/muse-glimmer-30b-bf16; dev.meta.ai/docs/muse-glimmer/deploy |

Glimmer serving (Meta docs): ~72 GB VRAM (one H100 80GB), image `vllm/vllm-openai:muse-glimmer`, flags
`--tool-call-parser muse_glimmer --reasoning-parser muse_glimmer --generation-config auto` (underscores matter).
Fireworks also offers free Muse Glimmer 30B SFT until 11/30 (fireworks.ai/pricing), which is an option for the cloud-side teacher, not the phone student.
Partner credits (kickoff): Meta $150 Model API, Baseten $100 + 2M TPM, Modal $100, Fireworks TBA.

## Cost estimate (training/pg_train/cost.py; nothing called)
Our assumptions: ~139 input tokens/row, ~300 reasoning+answer output tokens/call, 5 votes where logprobs are missing, +10%.

| Teacher (alternatives) | 5k rows | 20k rows |
|---|---|---|
| Spark Open @ Fireworks (logprobs, 1 call) | $7.97 | $31.90 |
| Glimmer @ Modal H100 (our throughput guess 6k req/h) | $9.12 | $36.50 |
| Glimmer @ Fireworks on-demand H100 | $12.82 | $51.30 |
| Muse Spark 1.3 @ Meta (5 votes) | $39.85 | $159.40 |
| Muse Spark 1.3 Contributor @ Meta (5 votes) | $2.03 | $8.10 |
| Spark Open @ Baseten (5 votes) | $39.85 | $159.40 |

Recommended pair for labels **with probabilities**: Spark Open @ Fireworks + Glimmer @ Modal ≈ $17 for 5k / $68 for 20k,
mostly coverable by partner credits. Output-token count is the dominant uncertainty: measure it on 20 rows first.

## Hackathon rules (cerebralvalley.ai event page, read from the page HTML; kickoff notes)
- No clause restricts model licenses. Relevant text: participants "may also include open source software or hardware,
  provided applicable open source licenses are followed"; you must own or have rights to all code, data, and assets
  (banned-projects rule); organizers get a royalty-free license to the **submission**.
- Stage 1 pass/fail: "use Meta AI products". Rubric: "Use of Meta AI tooling" is 25%.
- **Best Build on Meta Open Weights ($10K) needs Muse Glimmer or Muse Spark Open**, on your own hardware or partner inference,
  verified by the infra partner. Our phone model is Llama 3.2 1B, so for this prize the pitch has to rest on Glimmer and Spark Open as cloud brains and teachers (served via Modal or Fireworks).

## License implications
- **MobileMoE (FAIR Noncommercial Research License v1, 2026-08-21)**: use is limited to "noncommercial research uses ... not primarily
  intended for commercial advantage or monetary compensation". Entering a cash-prize contest and granting organizers a
  perpetual license to the submission is a gray zone, and so is any later product. **Decision: do not ship MobileMoE in the app or the demo.**
  Keep it only as a research comparison in eval/ (it's unsupported by llama.cpp anyway). Not legal advice. Ask in #office-hours if MobileMoE becomes important.
- **Llama 3.2 1B (Llama 3.2 Community License)**: commercial use is OK (unless >700M MAU). Obligations: ship a copy of the license, show
  "Built with Llama" prominently (app About screen + README), follow the Acceptable Use Policy, and **any distilled or fine-tuned model
  we distribute must have a name beginning with "Llama"**, e.g. `Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf`.
- **Muse Glimmer: Apache-2.0** (Fireworks/Modal model cards). **Muse Spark Open: "Muse Model License"** (Baseten card). Read it before redistributing anything derived from it; using its outputs as teacher labels should be checked against that license.
- Muse Spark Contributor mode: Meta may train on what we send, so use it only with synthetic scenarios, never user data.
