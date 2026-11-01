# Pocket Glimmer: 3:00 demo video script

Frame: **Active Memory that never leaves your phone.**
Rules: no title card, no auth or settings screens, no BYOK. Every `[AFTER_*]` (trained-model eval) or `[PHONE_*]` (iPhone measurement) tag is a number not measured yet.
On-device model is **locked: Llama 3.2 1B** (Q4_K_M, distilled into Llama-Reflex-1B). The 3B peaked at 5.03 GB RSS on the box CPU, leaving only ~0.47 GB under the ~5.5 GB budget.
Demo tasks stick to the types where the teacher scored 100% on QC (answerability, confirm-before-act, memory conflict; QC sample only 4–5 items per type). Shaky types (contactPick, eventPick, notificationTriage, nudgeNow) appear only as the hand-off to Muse Spark 1.3.
Replace it with the real measured value or cut the line. Never say a number that isn't measured.
Device tags: **[iPhone]** = screen recording on the iPhone 17 Pro. **[Mac]** = Mac needed (Xcode build, QuickTime mirror, or slide/chart render). **[Any]** = can be made on any machine.

| Time | Shot (what's on screen) | Voiceover | Needs |
|---|---|---|---|
| 0:00–0:10 | Cold open, no title. Swipe down, tap Airplane Mode ON (icon visible the whole time). Pill: "Offline · fully on device". Type: *"What did Professor Lee say the CSCI 335 project is due?"* Card: `answerability → answer from memory [PHONE_CONF]%`, answer appears from memory. | "Airplane mode is on. It still knows." | [iPhone] + [Mac] mirror |
| 0:10–0:25 | Same screen, light zoom on the Memory tab. Lower third: "Habib · CS student, Hunter College · Bronx". | "I'm Habib. I'm a CS student at Hunter, and I live in the Bronx. My assistant forgets everything unless I send my life to a server. This is Llama-Reflex-1B, a Meta model distilled from Glimmer and Spark Open, on your phone." | [iPhone] |
| 0:25–0:45 | Task 1, confirm-before-act. Still offline. *"Text Mom I'll be home by 8."* Card: `toolChoice → send_message`, then `confirmBeforeAct → confirm [PHONE_CONF]%`, structured JSON tool call, Confirm button. Tap Confirm. Then *"Remind me to call Mom at 7"*: the reminder appears in Reminders (EventKit). | "Every step is a typed decision with a confidence bar. Anything that speaks for me, like a message, asks first. The reminder is real, in EventKit." | [iPhone] |
| 0:45–1:05 | Task 2, memory conflict. *"I switched my Thursday shift to Fridays."* Card: `memoryConflict → update [PHONE_CONF]%`. Memory tab: old row struck through, new row shown, swipe to see "corrected by you". | "It noticed this conflicts with what it knew and updated the memory. Stored in SQLite, on this phone. My corrections are training data too." | [iPhone] |
| 1:05–1:20 | Task 3, answerability. *"What's my landlord's new Wi-Fi password?"* (never told it). Card: `answerability → can't answer from memory [PHONE_CONF]%`. Reply: "You haven't told me that." | "It knows what it doesn't know. No made-up answer." | [iPhone] |
| 1:20–1:45 | Task 4, hand-off to Muse Spark 1.3. Airplane Mode OFF on camera. *"Text Sam I'm running late."* Two Sams. Card: `contactPick → [PHONE_CONF]%`, bar goes orange below τ → badge "Meta Model API · Muse Spark 1.3 (Standard mode)". Tap info: names shown masked as `[PERSON_1]`. Still asks Confirm before sending. (Backup prompt if needed: *"Should I pay down my 6% loan or invest?"* → `route → escalate`.) | "Two Sams, and the small model isn't sure, so it doesn't guess. Below the threshold it hands off to Muse Spark 1.3. Standard mode, so my data isn't used for training, and personal details are masked before they leave." | [iPhone] (online, API approved) |
| 1:45–2:00 | Proof slide 1: before/after table. Gold set 300 hand-labeled decisions, 12 types; frozen held-out test split N=120. Baseline untrained Llama 3.2 1B Q4_K_M with prompt debiasing (frozen test, N=120): accuracy 74%, handled at τ=0.8 15%, accuracy on handled 89%, ECE 0.101. After distillation (Llama-Reflex-1B, same split): accuracy [AFTER_ACC], handled [AFTER_COVERAGE], accuracy on handled [AFTER_ACC_HANDLED], ECE [AFTER_ECE]. Second line: [PHONE_TOK_S] tok/s, [PHONE_TTFT_MS] ms to first token, [PHONE_RAM_GB] GB peak RAM (iPhone 17 Pro, measured on device). Footer: "Baseline numbers measured on a Linux x86 CPU, not the phone." | "Before training, the base 1B was right 74% of the time on 120 held-out hand-labeled decisions. After distillation: [AFTER_ACC]. On the iPhone it runs at [PHONE_TOK_S] tokens a second." | [Any] slide; phone numbers need [iPhone] |
| 2:00–2:08 | Proof line: "Why a 1B on the phone?" Small text: Llama 3.2 3B Q4_K_M peaks at 5.03 GB RSS (measured on the box CPU, not an iPhone): only ~0.47 GB under our ~5.5 GB budget. Glimmer 30B: dense, IQ2_M 9.85 GB file, 1-bit Q1_0 = gibberish. | "The 3B is smarter, but it leaves almost no memory headroom, and the 30B Glimmer doesn't fit at all; its 1-bit version outputs gibberish. So the 1B runs on the phone and Glimmer teaches." | [Any] |
| 2:08–2:20 | Proof slide 2: reliability diagram (`docs/img/reliability_baseline_test.png` next to [AFTER_RELIABILITY_CHART]) + conformal line: "Target: error among on-device decisions ≤ 5%, assuming new questions are exchangeable with the calibration set. τ = [AFTER_TAU], on-device share [AFTER_COVERAGE]". Inset: telemetry chart, on-device share per distillation round [AFTER_ROUND_SHARES]. | "The threshold isn't a guess. Conformal risk control sets it so errors among decisions it keeps on device stay at or under 5%, as long as new questions look like the calibration set. That's an assumption, not a promise." | [Mac] chart render; telemetry from [iPhone] |
| 2:20–2:45 | Meta stack diagram, header "Built with Llama · Built with Muse Spark Open": Llama-Reflex-1B, from Llama 3.2 1B (open weights, llama.cpp on device) ← distilled from Muse Glimmer (Apache-2.0, also local judge) + Muse Spark Open (open weights) → escalation to Muse Spark 1.3 via Meta Model API. | "Every model here is Meta. The phone runs Llama-Reflex-1B. The phone model and both teachers are open weights. Only the hard questions go to Muse Spark 1.3." | [Any] |
| 2:45–3:00 | Back to phone, Airplane Mode ON again. Memory tab scrolls. End on app screen, no logo slate. | "Active Memory that never leaves your phone. For students, for anyone who can't pay for the cloud, or doesn't want to. It's open, and it's in my pocket." | [iPhone] |

## Pre-shoot checklist
- Memories seeded by talking to the app during rehearsal, never by inserting rows.
- Two "Sam" contacts and a "Mom" contact exist on the demo phone. Never seed a Wi-Fi password memory (Task 3 needs it missing).
- Meta Model API key works in Standard mode before recording 1:20–1:45. If not approved: cut the handoff live and say "with the API, this goes to Muse Spark 1.3" (honest fallback).
- If the telemetry curve isn't rising, say so. Never backfill data.

## Placeholders to fill (all need real measurements)
- [PHONE_CONF] values in each live task (read off the phone)
- [AFTER_ACC], [AFTER_COVERAGE], [AFTER_ACC_HANDLED], [AFTER_ECE], [AFTER_TAU], [AFTER_ROUND_SHARES], [AFTER_RELIABILITY_CHART]: frozen test split N=120 only
- [PHONE_TOK_S], [PHONE_TTFT_MS], [PHONE_RAM_GB]: iPhone 17 Pro, Release build (see ios/MAC_DAY_RUNBOOK.md step 8)

## TODO: UI elements this script assumes (app work should match)
Not verified in the app yet. Build or adjust these before recording, or change the script.
- [x] **Decision-object card**: expandable card per Reflex decision showing `type → choice`, confidence %, latency ms (0:25–1:45).
- [x] **Confidence bar**: horizontal bar per decision; **turns orange below τ** (low-confidence / escalate state) (1:20–1:45).
- [x] **Tool-call view**: the tool-call JSON shown inside the card (0:25–0:45). *Honest caveat: the tool is picked by a Reflex decision, but the args are filled in by on-device heuristics/Memory, not grammar-constrained decoding. Say "structured tool call" in the voiceover, not "grammar-constrained".*
- [x] **"Corrected by you" label** in the Memory tab, with the old row struck through and the new row shown (0:45–1:05).
- [x] **Confirm button** on message sends (1:05–1:20).
- [x] **Escalation badge**: "Meta Model API · Muse Spark 1.3 (Standard mode)", with an info view showing masked `[PERSON_1]` tokens (1:20–1:45).
- [x] **Offline pill**: "Offline · fully on device" / "Online" status (0:00, 2:45).
- [x] **Telemetry chart**: on-device share per distillation round, from logged rows only (2:08–2:20).
- [x] (n/a in app) Lower-third name caption is added in editing, not in the app (0:10–0:25).
