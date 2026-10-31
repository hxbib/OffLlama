# Pocket Glimmer: submission packet (skeleton)

> **Note for Habib:** this is a draft skeleton. Do the final read and rewrite it in your own words before submitting.
> Every `[TBD: ...]` is a number that hasn't been measured. Fill it from a real run or delete the sentence.

## What it is
I built a personal assistant for the iPhone 17 Pro that works in airplane mode. A small Meta model on the phone
makes the everyday decisions and shows how sure it is. When it isn't sure, it hands the question to Muse Spark 1.3.
Active Memory that never leaves your phone.

## What's new (built Oct 26 – Nov 4, 2026)
Everything in the repo was written in the hackathon window. I didn't reuse earlier products or templates.
- On-device Reflex: Llama 3.2 1B Q4_K_M in llama.cpp. Typed decision objects with a confidence score.
- Grammar-constrained tool calls to EventKit, Contacts and Shortcuts.
- SQLite memory on the phone, with user corrections.
- Distillation pipeline from Muse Glimmer and Muse Spark Open into the 1B.
- Conformal risk control to set the escalation threshold.
- Gate-1 test of Muse Glimmer 30B for on-device use (it failed; details under Technical Depth).

## Impact
I'm a CS student at Hunter, and I live in the Bronx. The assistants I can use either forget me or send my life to a server.
I wanted one that remembers me and keeps that memory on my phone. It also has to work in the subway with no signal.
- Who it's for: students and anyone who can't pay for cloud AI, or doesn't want their data there.
- What it does today: reminders, calendar, contacts, memory recall, all offline.
- Measured on-device share: [TBD: after-distillation on-device share] (baseline: 11% at τ=0.8).

## Use of Meta AI Tooling
Every model in the system is a Meta model.

| Part | Meta model / tool | Where it runs | License |
|---|---|---|---|
| Reflex (System 1) | Llama 3.2 1B Instruct, Q4_K_M | iPhone, llama.cpp + Metal | Llama Community License |
| Teacher + local judge | Muse Glimmer 30B | Mac / hosted | Apache-2.0 |
| Teacher | Muse Spark Open | hosted open weights | [TBD: confirm license name] |
| Escalation (System 2) | Muse Spark 1.3 | Meta Model API, Standard mode | API terms |

- Standard mode, not Contributor mode, so user data isn't used for training.
- Teachers label the same decision questions. Where they disagree, the label becomes "escalate".
- I use Glimmer as an LLM-as-judge locally to grade answers.

## Demo
- Video (3:00): [TBD: video URL]
- It opens in airplane mode, with a memory question answered on the phone.
- It shows four real tasks: reminder, memory correction, contact pick, and one low-confidence handoff to Spark 1.3.
- Script: `docs/DEMO_SCRIPT.md`.

## Technical Depth
- Each decision is one forward pass. I read the logits of the option letters and turn them into a calibrated probability.
- Below the threshold the Reflex takes the safe path: escalate, ask, or confirm.
- Threshold: conformal risk control. Target: error among on-device decisions ≤ 5%. τ = [TBD: conformal τ].
- Calibration: baseline ECE 0.101 on 36 gold decisions. After distillation: [TBD: after-distillation ECE]. Chart: `docs/img/reliability_baseline.png`.
- Before/after on the gold set (N=36, 12 decision types, hand-labeled):

| Model | Accuracy | Handled on device (τ=0.8) | Accuracy on handled | ECE |
|---|---|---|---|---|
| Llama 3.2 1B Q4_K_M, untrained (measured, Linux CPU) | 0.53 | 0.11 | 0.75 | 0.101 |
| Distilled Reflex | [TBD: after-distillation accuracy] | [TBD: after-distillation on-device share] | [TBD] | [TBD: after-distillation ECE] |

- Speed on the iPhone 17 Pro (A19 Pro): [TBD: decode tok/s on A19 Pro], [TBD: median decision latency ms on iPhone].
- Why not Glimmer 30B on the phone: it's dense (29.6B). The smallest working file (IQ2_M) is 9.85 GB. The 1-bit Q1_0 file gives gibberish. I checked it isn't a llama.cpp bug: a model trained for 1-bit runs fine on the same build.
- Telemetry: every Reflex decision is logged on the phone. The on-device share per distillation round: [TBD: per-round shares].

## Limitations & assumptions
- The 5% guarantee assumes exchangeability: new questions have to look like the calibration set. If my usage shifts, the bound can break, so I recalibrate after each round.
- The gold set is small (36 items). With zero errors the bound needs at least 135 calibration rows. The baseline handled 0 rows under the conformal threshold.
- Baseline numbers come from a Linux x86 CPU, not the phone. Phone speed has to be measured on device.
- The 30B phone speed in my notes (5–8 tok/s) was an estimate from memory bandwidth. Nothing ran on a phone.
- Measured vs estimated: anything marked [TBD] isn't measured yet.

## Links
- Repo: [TBD: public repo URL]
- Video: [TBD: video URL]
- Short clip (optional): [TBD: X clip URL]
