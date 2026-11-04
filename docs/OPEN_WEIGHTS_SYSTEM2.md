# Open-weights System 2: Muse Glimmer 30B on our own GPU (Modal, vLLM, H100)

Added 2026-11-04 08:20–08:45 ET. Verified live at 08:39–08:41 ET.

With this, the whole escalation path can run on **Meta open weights**: Llama 3.2 1B (Llama-Reflex-1B) decides on the
phone; when it is unsure, the scrubbed question goes to **Muse Glimmer 30B** (Apache-2.0) served by us on a Modal H100,
through the app's existing OpenAI-compatible `CloudBrain` client (`CloudPresets.modal`). The default demo escalation
stays **Muse Spark 1.3 via the Meta Model API (Standard mode)**; this endpoint shows the same code path on weights we
host ourselves. This is the project's evidence for an optional open-weights bonus entry; confirm the current event
criteria before selecting that category.

## What was deployed
| | |
|---|---|
| Model | `meta-models/Muse-Glimmer-30B`, bf16 safetensors (~59.6 GB) in Modal Volume `pg-glimmer-weights`; served as `muse-glimmer` |
| Server | vLLM 0.33.0, native `MuseGlimmerForConditionalGeneration` support (≥ 0.28.0). **No `trust_remote_code`.** Flags in `training/serve/modal_glimmer_vllm.py` (reasoning parser `muse_glimmer`, `reasoning_strength: low`, max-model-len 16384) |
| Image | `nvidia/cuda:12.8.1-devel-ubuntu24.04` + Python 3.12. The first deploy on `debian_slim` failed at engine start with *"Could not find nvcc"* (vLLM JIT-compiles a kernel at startup); switching to the CUDA-devel base fixed it (deploy 134 s, cold start to `/health` 200 ≈ 6 min including weight load) |
| GPU / scaling | 1× H100 80 GB; `min_containers=0`, `max_containers=1`, `scaledown_window=300`. GPU compute stops after scale-down, not immediately after the last request; storage and other charges are separate |
| Auth | Every path except `/health` requires `Authorization: Bearer <token>` (`training/serve/pg_auth.py`; token in Modal Secret `pg-glimmer-token`). The URL and token are **not** in the repo |
| Endpoint | `https://<workspace>--pg-glimmer-vllm-serve.<region>.modal.run/v1/` (OpenAI-compatible: `/v1/models`, `/v1/chat/completions`) |

Deploy / redeploy: `source` the Modal token, then `modal run training/serve/modal_glimmer_vllm.py::download` (once) and
`modal deploy training/serve/modal_glimmer_vllm.py`. Full commands in `training/serve/README.md`.

## Recorded smoke checks (08:40 ET; one warm container)
| Test | Result |
|---|---|
| `GET /v1/models` | `["muse-glimmer"]` |
| **Privacy contract**: the exact `Assistant.swift` system prompt + a scrubbed user message containing `[PERSON_1]` | Answer: *"Hi [PERSON_1], I hope you're well. Could you please let me know when the bathroom leak is expected to be fixed?"* → **placeholder survived verbatim**, so `PrivacyScrubber.restore` can put the real name back on the phone. 2.7 s, 122 completion tokens |
| Reasoning item (6% loan vs index fund, 300 tokens) | 6.43 s → **46.7 completion tokens/s** for the whole request, including prefill/network overhead. The saved answer is truncated; this is not an answer-quality score |
| **Through the app's Swift code** (`pg-cli cloud-probe` → `CloudPresets.modal` → `OpenAICompatibleBrain.complete`) | `[Modal · muse-glimmer] 2768 ms` — *"A conformal prediction threshold is a data-driven quantile of conformity scores used to construct prediction sets that guarantee marginal coverage at a specified level."* |

Cold start: the first request after scale-to-zero waits for the container (weights from the Volume + vLLM engine
start); measured ≈ 6 min on the first boot of the fixed image. For a live demo, hit `/health` ten minutes beforehand.

## Pointing the app at it
Settings → "Other / OpenAI-compatible" (BYO endpoint row): base URL `https://<app>.modal.run/v1/`, model `muse-glimmer`,
key = the bearer token. `CloudBrainChain` tries brains in order, so you can keep Muse Spark 1.3 first and Glimmer as the
fallback, or put Glimmer first for an all-open-weights run. Everything else (route → sensitivity → scrub → restore,
the "what left the phone" sheet, telemetry) is unchanged because the brain is just another `CloudBrain`.

## Honest scope
- The phone never runs Glimmer: at IQ2_M it is a 9.85 GB file (README "Why not run the 30B on the phone"). It is the
  teacher of the shipping model and, here, an optional cloud brain.
- Numbers above are from one warm container and a handful of requests; they are not a benchmark. The two completion samples are in `eval/serve/glimmer_modal_smoke.json`; the 2,768 ms Swift probe is in `eval/serve/cloud_probe_swift.txt`. See [the evidence audit](../eval/serve/GLIMMER_MODAL.md) for removed unsupported claims. Present endpoint availability is unverified.
- Licenses: Muse Glimmer 30B Apache-2.0 (weights unchanged, served as-is); Llama 3.2 1B under the Llama 3.2
  Community License ("Built with Llama", NOTICE). Nothing non-Meta runs at inference time.
- Spend must be read from a dated Modal usage report. The two smoke timings do not establish total billed GPU time.
