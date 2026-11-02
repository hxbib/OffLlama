# Reflex vs llama.cpp `/v1/systemone` (PR ggml-org/llama.cpp#29818)

Source read: https://github.com/ggml-org/llama.cpp/pull/29818 (merged 2026-10-02 09:56 UTC = 05:56 ET), files
`tools/server/server-decision.cpp` and `tools/server/README.md`. Our box build (/workspace/gate1/llama.cpp @ ddf48f8) contains it.

## Same semantics
- One forward pass per question; per-option probabilities from a softmax over option scores; argmax is the answer.
- Option-letter scoring for causal decision models (openjev: one single-token letter per option, A–Z a–z) is the same
  idea as our Reflex (letter logits → softmax).
- Temperature scaling before the softmax.

## Differences (we keep ours, noted deliberately)
| | systemone | Reflex |
|---|---|---|
| Temperature | fixed in the GGUF (`{arch}.decision.temperature.<type>[.<bucket>]`, buckets by option count 2 / 3_5 / 6_10 / 11) | fitted on our held-out data per decision type (`CalibrationProfile`) |
| Confidence | `(p_max − 1/n)/(1 − 1/n)`, 0 = uniform (TypeSafe formula) | raw `p_max`; we threshold it with a conformally certified tau (`ConformalRisk`). Upstream formula exposed as `Calibration.systemOneConfidence` for parity. |
| Position debias | lev: 2 variants (options in reversed order), probabilities averaged → 2 passes | none (1 pass) |
| Question types | `choice`, `score` (expected level), `noul` (P(true)) | choice only (yes/no sets are 2-option choices) |
| Escalation | none; README says probabilities "are not guaranteed to be calibrated for your data" | fallback option when conf < tau |
| Runtime | HTTP server | in-process libllama on iOS (server logic can't ship in-app) |

## Decision models in the PR (Hugging Face API, 2026-10-31)
| GGUF repo | license | params (base safetensors) | smallest GGUF |
|---|---|---|---|
| ggml-org/Laya-GGUF (convaiinnovations/laya) | apache-2.0 | 421.3M | Q8_0 449 MB |
| ggml-org/Julia-1-GGUF (SupersonicLabs/Julia-1) | apache-2.0 | 144.3M | Q8_0 168 MB |
| ggml-org/lev-GGUF (interfaze-ai/lev) | apache-2.0 | — (BF16 8.4 GB ≈ 4B) | Q4_K_M 3.0 GB |
| ggml-org/Kev-4B-GGUF (jaredpalmer/kev-4b) | apache-2.0 | ~4B | Q4_K_M 3.0 GB |
| ggml-org/OpenJev-GGUF | **cc-by-nc-4.0** (non-commercial) | BF16 53.8 GB | Q4_K_M 19.4 GB |

Licenses are the `license` field of each HF model card (not the full license files).

## Benchmark on our earlier 36 gold decisions (historical; the current eval set is the 300-item gold set: 180 calibration / 120 frozen test, eval/gold/) (eval/score_systemone.py, tau 0.8, box CPU, 2 threads)
| model | acc | ECE | coverage@0.8 | acc on covered | median ms |
|---|---|---|---|---|---|
| Llama-3.2-1B-Instruct Q4_K_M, untrained (eval/results/llama32-1b-base.json) | 0.53 | 0.10 | 0.11 | 0.75 | 550 |
| Laya Q8_0 (eval/results/laya-q8_0.json) | **0.69** | 0.21 | 0.25 | 0.78 | 402 |
| Julia-1 Q8_0 (eval/results/julia-1-q8_0.json) | 0.44 | 0.38 | 0.56 | 0.45 | 84 |

Caveats: n=36 (one item ≈ 2.8 pts); latencies are HTTP round trips on a shared box with a 30B server and another eval
running, not phone numbers; the Llama run uses our few-shot letter prompt while systemone models get state +
instructions + criteria labels. Laya is zero-shot and beats the untrained 1B on route (4/7 vs 1/7) but loses on
toolChoice (3/6 vs 5/6). Laya is BERT-style (mask/sep head), so it can't be SFT-distilled with our Unsloth causal pipeline as-is.
Conformal tau (alpha 0.05, delta 0.1): none of the three certifies on 36 rows (needs ≥135 accepted rows).
