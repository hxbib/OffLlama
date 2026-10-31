# Pocket Glimmer: 3:00 demo video script

Frame: **Active Memory that never leaves your phone.**
Rules: no title card, no auth or settings screens, no BYOK. Every `[TBD: ...]` is a number not measured yet.
Replace it with the real measured value or cut the line. Never say a number that isn't measured.
Device tags: **[iPhone]** = screen recording on the iPhone 17 Pro. **[Mac]** = Mac needed (Xcode build, QuickTime mirror, or slide/chart render). **[Any]** = can be made on any machine.

| Time | Shot (what's on screen) | Voiceover | Needs |
|---|---|---|---|
| 0:00–0:10 | Cold open, no title. Swipe down, tap Airplane Mode ON (icon visible the whole time). Pill: "Offline · fully on device". Type: *"What did Professor Lee say the CSCI 335 project is due?"* Answer appears from memory, with Reflex strip (`route → answer_local [TBD: conf]%`). | "Airplane mode is on. It still knows." | [iPhone] + [Mac] mirror |
| 0:10–0:25 | Same screen, light zoom on the Memory tab. Lower third: "Habib · CS student, Hunter College · Bronx". | "I'm Habib. I'm a CS student at Hunter, and I live in the Bronx. My assistant forgets everything unless I send my life to a server. This is Llama-Reflex-1B, a Meta model distilled from Glimmer and Spark Open, on your phone." | [iPhone] |
| 0:25–0:45 | Task 1, tool call. Still offline. *"Remind me to call Mom at 7."* Decision object card expands: `type: route → tool`, confidence bar `[TBD: conf]%`, then `toolChoice → create_reminder`, structured JSON tool call. Reminders app shows it. | "Every step is a typed decision with a confidence bar. The tool is a typed choice; the call is plain JSON you can inspect. The reminder is real, in EventKit." | [iPhone] |
| 0:45–1:05 | Task 2, memory write + correction. *"I switched my Thursday shift to Fridays."* Card: `memoryConflict → update [TBD: conf]%`. Memory tab: old row struck through, new row shown, swipe to see "corrected by you". | "It noticed this conflicts with what it knew and updated the memory. Stored in SQLite, on this phone. My corrections are training data too." | [iPhone] |
| 1:05–1:20 | Task 3, contact pick + confirm. *"Text Sam I'm running late."* Two Sams. Card: `contactPick → Sam Ortiz [TBD: conf]%`, then a Confirm button (messages always confirm). | "Two Sams. It picks one and shows how sure it is. Sending a message always asks first." | [iPhone] (seeded contacts) |
| 1:20–1:45 | Task 4, low-confidence handoff. Airplane Mode OFF on camera. *"Should I pay down my 6% loan or invest, given my budget?"* Confidence bar goes orange below τ: `route → escalate [TBD: conf]%`. Badge: "Meta Model API · Muse Spark 1.3 (Standard mode)". Tap info: names/numbers shown masked as `[PERSON_1]`. | "This one is hard, and the small model knows it. Below the threshold it hands off to Muse Spark 1.3. Standard mode, so my data isn't used for training, and personal details are masked before they leave." | [iPhone] (online, API approved) |
| 1:45–2:00 | Proof slide 1: before/after table. Gold set N=36 hand-labeled decisions, 12 types. Baseline untrained Llama 3.2 1B Q4_K_M (N=36): accuracy 53%, handled at τ=0.8 11%, ECE 0.101. After distillation (Llama-Reflex-1B, frozen held-out test split only, N=[TBD: frozen test split N]): accuracy [TBD: after-distillation accuracy], handled [TBD: after-distillation on-device share], ECE [TBD: after-distillation ECE]. Second line: [TBD: decode tok/s on A19 Pro], [TBD: median decision latency ms on iPhone]. | "Before training, the base 1B was right 53% of the time on 36 hand-labeled decisions. After distillation: [TBD]. On the A19 Pro it runs at [TBD] tokens a second." | [Any] slide; tok/s needs [iPhone] |
| 2:00–2:08 | Proof line: "Why not run Glimmer 30B on the phone?" Small text: dense 29.6B, IQ2_M = 9.85 GB, 1-bit Q1_0 = gibberish. | "I tried putting the 30B Glimmer on the phone. It's dense, the smallest working file is 9.85 GB, and the 1-bit version outputs gibberish. So Glimmer teaches instead." | [Any] |
| 2:08–2:20 | Proof slide 2: reliability diagram (`docs/img/reliability_baseline.png` next to [TBD: after-distillation reliability chart]) + conformal line: "Error among on-device decisions ≤ 5% (assumes exchangeability), τ = [TBD: conformal τ], on-device share [TBD]". Inset: telemetry chart, on-device share per distillation round [TBD: per-round shares]. | "The threshold isn't a guess. Conformal risk control sets it so errors among decisions it keeps on device stay at or under 5%, as long as new questions look like the calibration set. And each distillation round keeps more on the phone." | [Mac] chart render; telemetry from [iPhone] |
| 2:20–2:45 | Meta stack diagram, header "Built with Llama · Built with Muse Spark Open": Llama-Reflex-1B, from Llama 3.2 1B (open weights, llama.cpp on device) ← distilled from Muse Glimmer (Apache-2.0, also local judge) + Muse Spark Open (open weights) → escalation to Muse Spark 1.3 via Meta Model API. | "Every model here is Meta. The phone runs Llama-Reflex-1B. The phone model and both teachers are open weights. Only the hard questions go to Muse Spark 1.3." | [Any] |
| 2:45–3:00 | Back to phone, Airplane Mode ON again. Memory tab scrolls. End on app screen, no logo slate. | "Active Memory that never leaves your phone. For students, for anyone who can't pay for the cloud, or doesn't want to. It's open, and it's in my pocket." | [iPhone] |

## Pre-shoot checklist
- Memories seeded by talking to the app during rehearsal, never by inserting rows.
- Two "Sam" contacts and a "Mom" contact exist on the demo phone.
- Meta Model API key works in Standard mode before recording 1:20–1:45. If not approved: cut the handoff live and say "with the API, this goes to Muse Spark 1.3" (honest fallback).
- If the telemetry curve isn't rising, say so. Never backfill data.

## Placeholders to fill (all need real measurements)
- [TBD: conf] values in each live task (read off the phone)
- [TBD: after-distillation accuracy], [TBD: after-distillation on-device share], [TBD: after-distillation ECE]
- [TBD: decode tok/s on A19 Pro], [TBD: median decision latency ms on iPhone]
- [TBD: conformal τ], [TBD: per-round shares], [TBD: after-distillation reliability chart]

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
