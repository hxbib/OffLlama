# Pocket Glimmer: submission packet (skeleton)

> **Note for Habib:** this is a draft. Do the final read and rewrite it in your own words before submitting.
> Two kinds of tags: `[TBD: ...]` = a number not measured yet. `[PLACEHOLDER: ...]` = an open item from the rubric map
> (some are numbers, some are decisions or links). Fill each from a real run or source, or cut the sentence. Don't submit with any left.
> Rubric source: rules summaries at madrobot.blog and reconscribe.com (Oct 2026), and the event page cerebralvalley.ai/e/meta-ai-developer-hackathon.
> Indie lens: "creativity, technical ambition, and whether it works."

**Built with Llama · Built with Muse Spark Open**

**Pocket Glimmer.** An assistant for [PLACEHOLDER: user, e.g. "students like me"] that keeps working with no signal: a Meta Llama model, distilled from Muse Glimmer, runs entirely on iPhone and asks Meta's cloud only when it knows it's unsure.

Social/X hook (alternate): Active Memory that never leaves your phone.

## Rubric map (internal; delete before submitting)

| Category | What judges want (rules wording) | Our evidence | Packet section + video timestamp | Low-score risk → fix |
|---|---|---|---|---|
| **Impact 30%** | "Real-world potential: who benefits, how much it matters, whether it could become something people use, and whether it fits one of the problem statements" (themes: *Build for Your World* / *Push the Frontier*) | Theme: **Build for Your World**. User: me, Habib, CS student at Hunter, living in the Bronx. Moment: [PLACEHOLDER: user + moment, firsthand, e.g. no signal on the subway]. 3–4 daily tasks done offline (reminder, memory recall + correction, contact pick). Privacy, in Meta's own framing: Muse Wonder leads with "Active Memory" (Meta, Oct 12, 2026), and ours never leaves the phone. Proof: [PLACEHOLDER: real-use evidence: tester quote or self-use log]. Offline share: [TBD: after-distillation on-device share] (baseline 11% at τ=0.8) | §Impact (first). Video 0:00–0:25 and 2:45–3:00 | **Risk:** we pitch architecture and judges can't tell who it's for. → **Fix:** first 25 s of video and first paragraph name the user and the moment, no jargon; every demo task is Habib's real request; one piece of real-use evidence; a "what it would take to ship" line |
| **Use of Meta AI Tooling 25%** | "How creatively you use Meta's AI tools, whether you go beyond a basic integration, and whether you surface capabilities people did not expect." (Unofficial repo: genuine Meta use may be a pass/fail gate) | Meta at every layer: Muse Glimmer 30B (Apache-2.0) + Muse Spark Open (Muse Model License) as teachers labeling [PLACEHOLDER: N decision examples] → Llama 3.2 1B distilled into Llama-Reflex-1B (LoRA r16, Q4_K_M GGUF) on device → low-confidence escalation to Muse Spark 1.3 (Meta Model API, Standard mode). Glimmer is also the local LLM-as-judge. Optional SAM 3.1 glimpse: [PLACEHOLDER: SAM 3.1 built yes/no]. The unexpected part: a 1B Meta model that knows when it doesn't know | §Use of Meta AI Tooling (stack table). Video 1:20–1:45 (handoff), 2:20–2:45 (stack diagram) | **Risk:** looks like a generic wrapper, or Meta parts look optional. → **Fix:** BYOK never in the video, footnote only; Meta is the default config; say "open weights" aloud; settle [PLACEHOLDER: license determination] for Spark Open outputs as training data, else Glimmer-only labels (license check: allows distillation with attribution) |
| **Demo 25%** | "Whether there is a working, impressive demo, whether the product holds up live, and the quality of your demo video." Live finals Nov 9 | Real iPhone 17 Pro footage, airplane mode visibly ON [PLACEHOLDER: airplane-mode proof clip]; 4 tasks with decision card + confidence bar + tool call; recall cold open; one handoff to Spark 1.3. Script: `docs/DEMO_SCRIPT.md` | §Demo. Whole video | **Risk:** video unviewable, or live demo breaks. → **Fix:** public upload by Nov 3, tested logged out; check audio; edit out failures; offline build at finals with video as backup; no settings/auth screens; under 3:00 |
| **Technical depth 20%** | "Whether the engineering is sound and thoughtfully refined, and whether the project shows real craft." Indie: "technical ambition" | Baseline measured: untrained 1B, N=36 gold decisions, accuracy 0.53, handled 11%, ECE 0.101 (`docs/img/reliability_baseline.png`). After: [TBD: after-distillation accuracy], [TBD: after-distillation ECE]. Speed: [TBD: decode tok/s on A19 Pro], [TBD: TTFT on iPhone], [TBD: peak RAM on iPhone]. 30B negative result: Q1_0 gibberish (5.9 GB peak); IQ2_M correct but 9.85 GB, over the ~6 GB budget. Conformal threshold, error ≤ 5% under exchangeability | §Technical Depth. Video 1:45–2:20 | **Risk:** unverifiable claims. → **Fix:** every number has N, test set, baseline; reproducible scripts (`eval/score_decisions.py`, `training/reliability.py`); held-out set unseen by teacher prompts; state conformal assumption |

### Impact strengthening checklist (our weak spot)
- [ ] One user, one recurring moment, one sentence, no jargon. [PLACEHOLDER: user + moment]
- [ ] Real-use evidence: [PLACEHOLDER: ≥1 tester quote or N-day self-use log with tasks handled offline vs escalated]
- [ ] Benefit, measured only: [PLACEHOLDER: % of tasks handled fully offline, from eval or usage log]
- [ ] "Could people use it": [PLACEHOLDER: GGUF MB + app MB], $0 per-user server cost offline, works with no signal.
- [x] Theme name "Build for Your World" used verbatim (see Impact).

---

## TL;DR
- For: [PLACEHOLDER: user + moment]. Me first: a Hunter CS student in the Bronx.
- Offline: reminders, calendar, contacts, memory recall and corrections, on the phone in airplane mode.
- Meta models do all of it: Llama-Reflex-1B (from Llama 3.2 1B) on the phone, taught by Muse Glimmer and Muse Spark Open, with Muse Spark 1.3 for the hard questions.

## Impact
Theme: **Build for Your World**.

I'm a CS student at Hunter, and I live in the Bronx. The assistants I can use either forget me or send my life to a server.
I wanted one that remembers me and keeps that memory on my phone. It also has to work in the subway with no signal.
- Who it's for: students and anyone who can't pay for cloud AI, or doesn't want their data there.
- The moment: [PLACEHOLDER: user + moment].
- What it does today: reminders, calendar, contacts, memory recall, all offline.
- How much stays on the phone: [TBD: after-distillation on-device share] (baseline: 11% at τ=0.8).
- Real use: [PLACEHOLDER: real-use evidence].
- What it would take to ship: [PLACEHOLDER: GGUF MB + app MB]. No server cost per user for the offline path.

## Use of Meta AI Tooling
Every model in the system is a Meta model. Four of them carry real load:
1. **Llama 3.2 1B → Llama-Reflex-1B**: the on-device decision model. Every Reflex decision, tool call and route runs on it, offline.
2. **Muse Glimmer (Apache-2.0)**: teacher for the distillation labels, and the local LLM-as-judge for grading answers.
3. **Muse Spark Open**: second teacher. Its license allows distillation with attribution, so it's credited as "Built with Muse Spark Open".
4. **Muse Spark 1.3**: cloud escalation when the Reflex isn't sure. Meta Model API, Standard mode.

| Model | License / access | Role | Why this model |
|---|---|---|---|
| Llama-Reflex-1B (distilled from Llama 3.2 1B Instruct), Q4_K_M | Llama Community License, open weights | On-device Reflex: typed decisions, tool calls, routing (llama.cpp + Metal) | Fits the phone's ~6 GB budget at Q4 |
| Muse Glimmer 30B | Apache-2.0, open weights | Teacher labels + local LLM-as-judge | Meta's on-device agentic model, too big for the phone (see Technical Depth) |
| Muse Spark Open | Muse Model License, open weights via [PLACEHOLDER: host: Fireworks/Baseten/Modal] | Teacher | Second, larger teacher; the license allows distillation with attribution ("Built with Muse Spark Open") |
| Muse Spark 1.3 | Meta Model API, **Standard mode** (not used for training) | Escalation when confidence is low | Strong reasoning and tool calling |
| SAM 3.1 (optional) | Model API | Camera glimpse | [PLACEHOLDER: SAM 3.1 built yes/no] |

- The teachers label the same decision questions. Where they disagree, the label becomes "escalate".
- What you might not expect: a calibrated 1B Meta model that hands off to Meta's cloud only when it's unsure.
- Contributor mode is off. Personal details are masked before anything leaves the phone.

<sub>Footnote: the app can also point at any OpenAI-compatible endpoint. It's off by default and not in the demo.</sub>

## Demo
- Video (3:00): [PLACEHOLDER: public YouTube URL]
- Airplane-mode proof: [PLACEHOLDER: airplane-mode proof clip]
- How to run it: [PLACEHOLDER: install/run path (TestFlight or build steps)]
- Timestamps:
  - 0:00–0:10: airplane mode on, a memory question answered on the phone.
  - 0:10–0:25: who I am, the problem, "a Meta model distilled from Glimmer and Spark Open, on your phone."
  - 0:25–1:45: four real tasks (reminder, memory correction, contact pick), then one low-confidence handoff to Spark 1.3.
  - 1:45–2:20: before/after eval, speed, why 30B didn't fit, the conformal bound + reliability chart.
  - 2:20–2:45: Meta stack, open weights.
  - 2:45–3:00: close.
- Script: `docs/DEMO_SCRIPT.md`.

## Technical Depth
- Architecture: [PLACEHOLDER: architecture diagram image] (Mermaid source in README).
- Each decision is one forward pass. I read the logits of the option letters and turn them into a calibrated probability.
- Below the threshold the Reflex takes the safe path: escalate, ask, or confirm.
- Distillation: teachers → [PLACEHOLDER: N teacher-labeled examples] → LoRA r16 (Unsloth), loss on the answer letter only → temperature scaling → Q4_K_M GGUF → llama.cpp Metal.
- Threshold: conformal risk control. Target: error among on-device decisions ≤ 5%. τ = [TBD: conformal τ].
- Calibration: baseline ECE 0.101 (10 bins, N=36). After: [TBD: after-distillation ECE]. Charts: `docs/img/reliability_baseline.png`, [TBD: after-distillation reliability chart].
- Headline after-distillation accuracy and ECE come **only from the frozen held-out test split** (never the dev or calibration split).
- Before/after (baseline row: original 36-item gold set; after row: [TBD: frozen test split N]):

| Model | Accuracy | Handled on device (τ=0.8) | Accuracy on handled | ECE |
|---|---|---|---|---|
| Llama 3.2 1B Q4_K_M, untrained (measured, Linux CPU) | 0.53 | 0.11 | 0.75 | 0.101 |
| Llama-Reflex-1B (distilled) | [TBD: after-distillation accuracy] | [TBD: after-distillation on-device share] | [TBD: after-distillation accuracy on handled] | [TBD: after-distillation ECE] |

- Why Llama for the Reflex. I tested three small untrained models on the same 36 gold items (`docs/SYSTEMONE.md`):

| Model (untrained) | Accuracy | ECE | Coverage @ τ=0.8 | Accuracy on covered | Median ms |
|---|---|---|---|---|---|
| Llama 3.2 1B Q4_K_M | 0.53 | 0.10 | 0.11 | 0.75 | 550 |
| Laya Q8_0 | 0.69 | 0.21 | 0.25 | 0.78 | 402 |
| Julia-1 Q8_0 | 0.44 | 0.38 | 0.56 | 0.45 | 84 |

  I chose Llama because it's distillable with our LoRA pipeline (Laya is BERT-style). Latency here is the box HTTP round trip, not the phone.
- Speed on the iPhone 17 Pro (A19 Pro, Q4, context [TBD: context length]): [TBD: decode tok/s on A19 Pro], [TBD: TTFT on iPhone], [TBD: median decision latency ms on iPhone], [TBD: peak RAM on iPhone].
- Why not Glimmer 30B on the phone: it's dense (29.6B). The smallest working file (IQ2_M) is 9.85 GB, over the ~6 GB budget. The 1-bit Q1_0 file (5.9 GB peak) gives gibberish. I checked it isn't a llama.cpp bug: a model trained for 1-bit runs fine on the same build. So I switched to distillation.
- Telemetry: every Reflex decision is logged on the phone. On-device share per distillation round: [TBD: per-round shares].

## What I built during the event vs what I used
- New, Oct 26 – Nov 4, 2026: [PLACEHOLDER: dated new-work list from commit history]. Highlights: Swift PocketCore (Reflex, calibration, conformal, SQLite memory, scrubber, telemetry), the SwiftUI app, the distillation pipeline, the 36-item gold set, the gate-1 Glimmer test. No earlier products or templates reused.
- Used: llama.cpp (MIT), Unsloth (Apache-2.0), SQLite (public domain), matplotlib. Model weights keep their own licenses.
- Commit history: [PLACEHOLDER: public repo URL]/commits

## Privacy & data handling
- On the phone by default. Memory is SQLite on the device.
- The cloud is used only on escalation, through Muse Spark 1.3 in Standard mode. Contributor mode is never on. [PLACEHOLDER: confirmation that cloud calls use muse-spark-1.3 Standard mode]
- Names, emails, phones, addresses and card numbers are masked before anything leaves.
- The demo uses my own data or made-up data.

## Limitations & assumptions
- The 5% guarantee assumes exchangeability: new questions have to look like the calibration set. I say "on our eval distribution," not "guaranteed." I recalibrate after each round.
- The gold set is small (36). With zero errors, the bound needs at least 135 calibration rows. The untrained baseline kept 0 rows under the conformal threshold.
- Baseline numbers come from a Linux x86 CPU, not the phone.
- The 5–8 tok/s phone figure for 30B in my notes was an estimate from memory bandwidth. Nothing ran on a phone.
- Anything tagged [TBD] or [PLACEHOLDER] isn't measured or settled yet.

## Team + what's next
- Team: [PLACEHOLDER: team names for submission]
- Next 30 days: more distillation rounds, on-device eval, a bigger calibration set.

## Links
- Repo: [PLACEHOLDER: public repo URL]
- Video: [PLACEHOLDER: public YouTube URL]
- Short clip (optional): [TBD: X clip URL]
