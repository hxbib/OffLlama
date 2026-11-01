# Pocket Glimmer

**Built with Llama · Built with Muse Spark Open**

**A fully offline personal assistant for iPhone, powered by Meta models.** A small Meta model on the phone makes
every everyday decision in milliseconds and shows how sure it is. When it isn't sure, or the question is hard, it
escalates to a bigger Meta brain (Muse Spark, Muse Glimmer) if you're online. Then that brain teaches the small one.

- **System 1 · Reflex**: **Llama-Reflex-1B** (distilled from Llama 3.2 1B Instruct; Q4_K_M, llama.cpp + Metal) on-device. Each decision is a typed
  multiple-choice question answered in **one forward pass**: we read the logits of the option-letter tokens,
  apply a calibrated temperature softmax, and compare the top probability to a threshold τ (default 0.8).
  Below τ it takes the safe fallback (escalate / ask / confirm). 12 decision types: route, tool choice,
  contact pick, event pick, remember-or-not, memory conflict, notification triage, confirm-before-act,
  nudge-now, timing, sensitivity, answerability.
- **System 2**: simple answers by the same on-device model; hard reasoning goes to **Muse Spark 1.3 / Muse Wonder
  (Meta Model API)** or **Muse Glimmer 30B / Muse Spark Open** (hosted open weights). A privacy scrubber
  masks names, emails, phones, addresses and card numbers before anything leaves the phone, and restores them in the answer.
- **Memory**: on-device SQLite. Fact extraction, user profile, contradiction handling (Reflex decides
  update / keep both / ignore), expiry, embedding retrieval. Memory drives proactive nudges.
- **Proactive**: iOS Shortcuts automations (time, arrive, email, message, charger) → App Intent → rules
  pick candidate memories → Reflex decides whether to nudge now.
- **Actions**: EventKit reminders + calendar, Contacts, messages via a Shortcuts bridge. It never taps inside other apps.
- **Real telemetry**: every Reflex decision is logged (time, type, confidence, escalated, latency, later
  agreement with a teacher). The "share handled on device" chart is built only from those rows.
- **Distillation**: teachers (Muse Spark Open, Muse Glimmer) label the same questions with probabilities;
  disagreement becomes "escalate"; LoRA r16 SFT with loss on the answer letter only; temperature scaling + τ per decision.

## Architecture

```mermaid
flowchart LR
  subgraph Phone["iPhone 17 Pro · offline"]
    U[User / Shortcuts trigger] --> R{{"Reflex (System 1)<br/>Llama-Reflex-1B Q4 · llama.cpp<br/>1 forward pass → letter logits → p, τ"}}
    R -- tool --> A[EventKit · Contacts · Shortcuts bridge]
    R -- answer_local --> L[Local answer<br/>same 1B model]
    R -- remember / conflict --> M[(SQLite memory<br/>facts · profile · expiry · embeddings)]
    M -- candidates --> P[Proactive rules] --> R
    R -- every decision --> T[(Telemetry<br/>conf · ms · escalated · teacher-agree)]
    R -- "escalate (p < τ or hard)" --> S[Privacy scrubber]
  end
  S -- online only --> C["System 2 cloud brain<br/>Meta Model API: Muse Spark 1.3 / Muse Wonder<br/>Muse Glimmer 30B · Muse Spark Open (hosted)"]
  C --> S
  T -. logged decisions .-> D["Distillation (training/)<br/>teachers label letter + probs → disagreement→escalate<br/>LoRA r16 letter-only SFT → calibrate T, τ → GGUF Q4"]
  D -. new reflex-Q4_K_M.gguf .-> R
```

## Repo

| Path | What | Status |
|---|---|---|
| `core/` | Swift Package **PocketCore**: option sets, Reflex, calibration, SQLite memory, proactive engine, cloud brains, scrubber, telemetry, `pg-cli` | builds + 30 tests pass on Linux (Swift 6.4.2) |
| `app/` | SwiftUI iOS app + XcodeGen `project.yml` | written, never compiled yet; needs Xcode on a Mac (see `ios/MAC_DAY_RUNBOOK.md`) |
| `training/` | stdlib-Python distillation pipeline + Unsloth SFT | 6 tests pass; free dry run with local 1B as stand-in teacher |
| `eval/` | 36 hand-labeled gold decisions + scorer; System 2 Q&A runner | baseline measured (below) |
| `docs/DEMO_SCRIPT.md` | 3-minute demo script | draft |

```bash
cd core && swift build && swift test                 # 30 tests
swift run pg-cli e2e --url http://127.0.0.1:8088     # 18 real decisions against llama-server
cd ../training && python3 -m unittest discover -s tests
```

## On-device model: locked to Llama 3.2 1B

The phone runs **Llama 3.2 1B Instruct Q4_K_M**, distilled into Llama-Reflex-1B. The 3B is more accurate, but its measured
peak of 5.03 GB RSS leaves only ~0.47 GB under our ~5.5 GB memory budget before app and runtime overhead, so the 1B wins on headroom.
Gate-1 lineup (`/workspace/gate1/RESULTS.md`, llama.cpp ddf48f8, llama-server -c 4096 -t 8).
**Every RSS and tok/s figure below was measured on the box's CPU (8 vCPU x86 AVX2), not on an iPhone.**

| Model | Status | Q&A (15) | Grammar tool calls: valid / correct tool (decision) / tool+args (15) | Raw tool calls: valid / tool / tool+args (10) | Peak RSS (box) | Decode tok/s (box) | Prompt tok/s (box) |
|---|---|---|---|---|---|---|---|
| Llama 3.2 1B Instruct Q4_K_M | complete | 5/15 | 15/15 / 11/15 / 7/15 | 6/10 / 4/10 / 2/10 | 1.99 GB | 47.01 | 987.9 |
| Llama 3.2 3B Instruct Q4_K_M | complete | 14/15 | 15/15 / 15/15 / 12/15 | 10/10 / 8/10 / 4/10 | 5.03 GB | 23.84 | 367.4 |
| Llama 3.1 8B Instruct Q4_K_M | complete (finished 19:08 EDT), not shippable on-device | 15/15 | 15/15 / 15/15 / 12/15 | 10/10 / 9/10 / 6/10 | 9.99 GB | 9.78 | 152.3 |
| Llama 3.1 8B Instruct Q2_K | **partial / not shippable on-device**, stopped at 19 of 40 items | 12/15 (partial) | 4/4 / 4/4 / 2/4 (partial, only 4 of 15 ran) | not run (missing) | 6.14 GB (partial run) | 13.14 (partial) | 106.0 (partial) |
| Muse Glimmer 30B IQ2_M [teacher reference] | complete | 11/11 | 15/15 / 14/15 / 14/15 | 10/10 / 9/10 / 9/10 | 9.65 GB | 2.56 | 36.6 |

### Reflex decisions, frozen held-out test split (120 hand-labeled items, 12 types)

| Model | Accuracy | Handled on device (τ=0.8) | Accuracy on handled | ECE |
|---|---|---|---|---|
| Llama 3.2 1B Q4_K_M, untrained + prompt debiasing (box CPU) | 0.74 | 0.15 | 0.89 | 0.150 |
| Llama-Reflex-1B (distilled) | [AFTER_ACC] | [AFTER_COVERAGE] | [AFTER_ACC_HANDLED] | [AFTER_ECE] |

iPhone 17 Pro speed and memory: [PHONE_TOK_S] tok/s decode, [PHONE_TTFT_MS] ms time to first token, [PHONE_RAM_GB] GB peak (not measured yet; see `ios/MAC_DAY_RUNBOOK.md`).
The conformal threshold targets ≤ 5% error among on-device decisions **only under exchangeability**: new requests must look like the calibration set. It's a statistical bound on our eval distribution, not a guarantee.
We haven't found prior art for this exact on-phone combination, which doesn't mean none exists.

## Earlier measurements (real runs, 2026-10-31, Linux x86 CPU, not a phone)

Untrained **Llama-3.2-1B-Instruct-Q4_K_M** via llama-server (2 threads, CPU shared with another job):

| Suite | argmax accuracy | handled at τ=0.8 | accuracy on handled | median ms (HTTP, CPU) |
|---|---|---|---|---|
| `pg-cli e2e` (18 cases) | 9/18 | 3/18 | 3/3 | 501 |
| `eval/gold_decisions` (36) | 0.53 | 0.11 | 0.75 | 550 |

That is the "before" picture: the base model is poorly calibrated and biased toward one letter on `route`, so it
mostly (correctly) escalates. Distillation from Muse teachers is how coverage goes up. Phone latency will differ
(Metal, KV-prefix reuse); measure on device, don't extrapolate from these numbers.

## Meta stack
| Model | Role | License / access |
|---|---|---|
| Llama-Reflex-1B (from Llama 3.2 1B Instruct, Q4_K_M) | On-device Reflex (System 1), distilled from the teachers below | Llama 3.2 Community License ("Built with Llama", see docs/LICENSING.md) |
| Muse Glimmer 30B | Teacher + local LLM-as-judge for evals | Apache-2.0 |
| Muse Spark Open (816B-A42B) | Teacher; open weights served via Fireworks / Baseten / Modal | Muse Model License ("Built with Muse Spark Open") |
| Muse Spark 1.3 | Cloud escalation (System 2) via Meta Model API, Standard mode only, never Contributor mode | Meta Model API terms |
| Muse Wonder | Rare hardest cases only | Meta Model API terms |

## Why not run the 30B on the phone
Measured on this box (/workspace/gate1/RESULTS.md, llama.cpp ddf48f8, CPU):
- Muse Glimmer is **dense, 29.6B active params**: every token reads all weights.
- The smallest coherent quant we tested, **IQ2_M, is a 9.85 GB file** (10.69 GB peak RSS, 2.54 tok/s decode on 8 vCPU).
- **Q1_0 (4.85 GB) is broken**: word salad even greedy, on both AVX2 and generic builds; a model trained for 1-bit (Bonsai 1.7B Q1_0) runs fine on the same build, so the loss comes from post-training 1-bit quantization.
- A phone app has roughly 5.5 GB of RAM to work with (our planning figure, not measured), so Glimmer can't fit. It stays a teacher and judge, and the 1B Reflex runs on device.

## Model choice notes
- MobileMoE-L-SFT is not supported by upstream llama.cpp (no converter/graph as of `ddf48f8`), so the phone runs
  Llama 3.2 1B. The training scripts support MobileMoE (transformers + PEFT) for when a llama.cpp port lands.
  MobileMoE is under the FAIR Noncommercial Research License.
- 1-bit Muse Glimmer (Q1_0) produced gibberish in our gate-1 test, so Glimmer is a cloud brain + teacher only.
- Embeddings: the default `HashingEmbedder` (char trigrams) works with zero download; `Embedder` is a protocol so a
  small embedding GGUF (e.g. EmbeddingGemma, in a supporting role) can be plugged in through llama.cpp embeddings.

## Prior work
Everything here was written during the hackathon window (Oct 26 – Nov 4, 2026). None of Habib's existing products
or starter templates were reused. The System 2 Q&A items in `eval/` come from this week's gate-1 model test.

## License
MIT (see `LICENSE`). SQLite amalgamation is public domain. Model weights keep their own licenses.

---
<sub>Footnote: the cloud brain also accepts any OpenAI-compatible endpoint with your own key (Settings → Other). Off by default.</sub>
