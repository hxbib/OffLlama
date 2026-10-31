# Pocket Glimmer

**A fully offline personal assistant for iPhone, powered by Meta models.** A small Meta model on the phone makes
every everyday decision in milliseconds and shows how sure it is. When it isn't sure, or the question is hard, it
escalates to a bigger Meta brain (Muse Spark, Muse Glimmer) if you're online. Then that brain teaches the small one.

- **System 1 · Reflex**: Llama 3.2 1B Instruct (Q4_K_M, llama.cpp + Metal) on-device. Each decision is a typed
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
    U[User / Shortcuts trigger] --> R{{"Reflex (System 1)<br/>Llama 3.2 1B Q4 · llama.cpp<br/>1 forward pass → letter logits → p, τ"}}
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
| `app/` | SwiftUI iOS app + XcodeGen `project.yml` | written, needs Xcode on a Mac (see `app/README.md`) |
| `training/` | stdlib-Python distillation pipeline + Unsloth SFT | 6 tests pass; free dry run with local 1B as stand-in teacher |
| `eval/` | 36 hand-labeled gold decisions + scorer; System 2 Q&A runner | baseline measured (below) |
| `docs/DEMO.md` | 3-minute demo script | draft |

```bash
cd core && swift build && swift test                 # 30 tests
swift run pg-cli e2e --url http://127.0.0.1:8088     # 18 real decisions against llama-server
cd ../training && python3 -m unittest discover -s tests
```

## Measured so far (real runs, 2026-10-31, Linux x86 CPU, not a phone)

Untrained **Llama-3.2-1B-Instruct-Q4_K_M** via llama-server (2 threads, CPU shared with another job):

| Suite | argmax accuracy | handled at τ=0.8 | accuracy on handled | median ms (HTTP, CPU) |
|---|---|---|---|---|
| `pg-cli e2e` (18 cases) | 9/18 | 3/18 | 3/3 | 501 |
| `eval/gold_decisions` (36) | 0.53 | 0.11 | 0.75 | 550 |

That is the "before" picture: the base model is poorly calibrated and biased toward one letter on `route`, so it
mostly (correctly) escalates. Distillation from Muse teachers is how coverage goes up. Phone latency will differ
(Metal, KV-prefix reuse); measure on device, don't extrapolate from these numbers.

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
