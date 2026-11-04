# Pocket Glimmer: 3:00 demo video script

> **Edit-ready cut: [docs/demo/STORYBOARD.md](demo/STORYBOARD.md)** (beat-by-beat timing, verbatim voiceover, fallbacks, 25 s no-iPhone variant, iMovie checklist). Finished slides: `docs/img/slide_01.png` … `slide_11.png` (1920×1080, from `docs/demo/slides.html`; re-render with `bash docs/demo/render_slides.sh`).

Frame: **A 1B Meta model on my iPhone that knows when it doesn't know.** Memory stays on the phone. The cloud only ever
sees masked text, and only when the model is unsure.
Rules: no title card, no auth or settings screens, no BYOK. `[PHONE_*]` cells are read off the phone while recording
(see docs/FINAL_HOURS.md §A). Never say a number that isn't measured. Don't show health questions (AI medical advice is
on the event's overdone list); the privacy beat uses money.

**Threshold in the app: τ = 0.90** (the certified operating point; shipped as `defaultTau` in the bundled
`calibration.json`; the decision-card footer shows it). Which shots can show a green, on-device bar follows the measured
per-type results at τ=0.90 (eval/results/PER_TYPE_TAU090.md, frozen test N=120, n=10 per type so one item = 10 points):

| Type | Clears τ=0.90 | Correct when it does | Use in the video |
|---|---|---|---|
| contactPick | 8/10 | 7/8 | on-device pick when context names the person; orange + "Which Sam?" when it doesn't |
| eventPick | 8/10 | 8/8 | on-device green-bar shot |
| route | 6/10 | 6/6 | on-device green-bar shot |
| toolChoice | 6/10 | 5/6 | on-device green-bar shot |
| sensitivity | 5/10 | 5/5 | "Kept on device" shot |
| answerability | 3/10 | 3/3 | runs offline when `route` escalates and there is no cloud (commit 822b49c): "no" → "I can't answer that offline" with no generation. Optional beat: *"What's my landlord's new Wi-Fi password?"* in airplane mode; keep only if the card clears τ on the phone |
| confirmBeforeAct | 2/10 | 2/2 | **don't promise a green bar.** Messages confirm by the hard rule "messages always confirm" (`core/Sources/PocketCore/Assistant.swift`, `|| action.tool == "send_message"`), not by confidence. Say "structured confirmation" |
| memoryConflict, nudgeNow | 0/10 | n/a | only as hand-off / safe-fallback examples |

**Rehearse each offline shot on the real phone and keep only those that clear τ.** If a shot escalates in rehearsal,
swap the utterance or cut it.

Device tags: **[iPhone]** = screen recording on the iPhone. **[Mac]** = Mac needed (Xcode build, QuickTime mirror, or
slide/chart render). **[Any]** = can be made on any machine.

| Time | Shot (what's on screen) | Voiceover | Needs |
|---|---|---|---|
| 0:00–0:10 | Cold open, no title. Swipe down, tap Airplane Mode ON (icon visible the whole time). Pill: "Offline · fully on device". Type: *"Remind me to call Mom at 7."* Cards: `route → tool [PHONE_CONF]%`, `toolChoice → create_reminder [PHONE_CONF]%`. If a Confirm button appears, tap it (below τ the confirm card's safe fallback is to ask). Cut to Reminders: the reminder is there (EventKit). | "Airplane mode is on. No signal. It still does what I asked, on the phone." | [iPhone] + [Mac] mirror |
| 0:10–0:25 | Same screen, light zoom on a decision card. Lower third: "Habib · CS student, Hunter College · Bronx". | "I'm Habib. I'm a CS student at Hunter, I live in the Bronx, and my commute is underground with no signal. This is Llama-Reflex-1B: a Meta Llama model, taught by Muse Glimmer, running on my phone." | [iPhone] |
| 0:25–0:45 | Task 1, structured confirmation. Still offline. *"Text Mom I'll be home by 8."* Cards: `toolChoice → send_message [PHONE_CONF]%`, then the confirm card (its bar may be orange; that's fine), the JSON tool call, and a Confirm button. Tap Confirm: the Messages compose sheet opens with the text filled in. | "Every step is a typed decision with a confidence bar. Anything that speaks for me, like a message, always asks first. That's a rule, not a guess." | [iPhone] |
| 0:45–1:05 | Task 2, privacy. Airplane Mode OFF on camera (pill flips to "Online"). *"Help me budget: my salary is $2,100 a month and I owe $3,400 on my credit card."* Card: `sensitivity → sensitive (keep on device) [PHONE_CONF]%`. Answer from the on-device model with the lock badge "Kept on device · nothing sent", while the "Online" pill stays visible (cloud available, deliberately not used). No Muse Spark badge. | "I'm online now, but this is my money, so it keeps this one on the phone. Nothing is sent. The cloud is right there, and it still answers on device." | [iPhone] (online) |
| 1:05–1:20 | Task 3, on-device pick. *"When's my advising meeting?"* with two advising events on the calendar. Card: `eventPick → [event] [PHONE_CONF]%` with a green bar, the answer with date and time (tap Confirm first if the app asks). (If the bar is orange, the app asks "Which one?": keep that take instead and change the line.) | "Two matching events. It picks the right one on the phone, and the bar says how sure it is." | [iPhone] |
| 1:20–1:32 | Task 4, knowing what it doesn't know. *"Text Sam I'm running late."* Two Sams in Contacts, nothing in memory to tell them apart. Card: `contactPick [PHONE_CONF]%`, bar **orange below τ** → reply "Which Sam? Sam Lee, Sam Ortiz". (Rehearse: if contactPick is confident here, use the take where it is not, or cut.) | "Two Sams, and the small model isn't sure. So it doesn't guess. It asks." | [iPhone] |
| 1:32–1:45 | Task 5, hand-off to Muse Spark 1.3. Online, Meta key set. *"Plan my week around Professor Lee's CSCI 335 final and my calc midterm."* Card: `route → escalate_cloud` (or orange below τ) → badge "Meta Model API · Muse Spark 1.3 (Standard mode)". Tap info: the prompt that left the phone, with names shown masked as `[PERSON_1]`. | "Hard planning goes to Muse Spark 1.3, in Standard mode, so my data isn't used for training. And personal details are masked before they leave." | [iPhone] (online, API key) |
| 1:45–2:00 | Proof slide 1: before/after table. "Gold set: 300 hand-labeled decisions, 12 types. Frozen held-out test split, N=120." Untrained Llama 3.2 1B: accuracy 74%, kept on device at τ=0.8 15%, accuracy on kept 89%, ECE 0.150. Llama-Reflex-1B (same split): accuracy 82% (98/120), kept on device 51% at τ=0.8 (61/120), accuracy on kept 92% (56/61), ECE 0.064. Second line, only if measured: [PHONE_TOK_S] tok/s, [PHONE_TTFT_MS] ms to first token, [PHONE_RAM_GB] GB peak (iPhone, Release build, airplane mode). Footer: "Baseline measured on a Linux x86 CPU, not the phone. No temperature scaling." | "Before training, the base 1B was right 74% of the time on 120 held-out hand-labeled decisions. After distillation from Muse Glimmer: 82%, and it keeps three times as many decisions on the phone." (If phone numbers exist: "On the iPhone it runs at [PHONE_TOK_S] tokens a second.") | `docs/img/slide_04.png`; phone numbers need [iPhone] |
| 2:00–2:08 | Proof line: "Why a 1B on the phone?" Small text: Llama 3.2 3B Q4_K_M peaks at 5.03 GB RSS (box CPU, not an iPhone): only ~0.47 GB under our ~5.5 GB budget. Glimmer 30B: dense, IQ2_M is a 9.85 GB file, 1-bit Q1_0 = gibberish. | "The 3B is smarter, but it leaves almost no memory headroom, and the 30B Glimmer doesn't fit at all; its 1-bit version outputs gibberish. So the 1B runs on the phone and Glimmer teaches." | `docs/img/slide_08.png` (top-left and top-middle cards) |
| 2:08–2:20 | Proof slide 2: risk–coverage curve `docs/img/risk_coverage_test120.png` (alternative: reliability diagrams `docs/img/reliability_baseline_test120_v2cc.png` next to `docs/img/reliability_after_floor_test120_v2cc.png`). Caption: "Error among kept decisions vs share kept, frozen test N=120. Area under curve 0.148 → 0.085." Conformal line: "Shipped threshold τ=0.90: error among on-device decisions ≤10.2% (calibration split N=180: 36% kept, 0 errors), assuming new questions look like the calibration set." | "The threshold isn't a guess. At every level of 'how much it keeps', the trained model makes fewer mistakes. And Learn-Then-Test sets the threshold so errors among the decisions it keeps stay at or under about ten percent, as long as new questions look like my calibration set. That's an assumption, not a promise." | `docs/img/slide_05.png` |
| 2:20–2:45 | Meta stack, header "Built with Llama": `docs/img/architecture.png`, plus the lineage line "Muse Spark → Muse Glimmer (Meta's own logit distillation) → Llama-Reflex-1B (ours)". Footnote: "Also tested: Muse Spark Open as teacher. Better labels, worse-calibrated student. Rejected." | "Every model here is Meta. Meta distilled Glimmer from Spark; I distilled Glimmer into a 1B that fits in my pocket. I also tried Spark Open as the teacher: better labels, but an overconfident student, so it didn't ship. Only the hard questions go to Muse Spark 1.3." | `docs/img/slide_07.png` (or `docs/img/architecture.png`) |
| 2:45–3:00 | Back to phone, Airplane Mode ON again. Memory tab scrolls. End on app screen, no logo slate. | "Memory that stays on my phone, and a model that knows when to ask. For students, for anyone underground, for anyone who doesn't want their life on a server. It's open, and it's in my pocket." | [iPhone] |

## Pre-shoot checklist
- **Threshold check:** open any decision card; the footer must read τ = 0.90. If it reads 0.80, the bundled
  `calibration.json` didn't load (docs/FINAL_HOURS.md §B5).
- **Rehearse every offline shot on the real phone and keep only those that clear τ.** At τ=0.90 the reliable green-bar
  types are contactPick, eventPick, route, toolChoice and sensitivity. Don't promise a green bar on the confirmBeforeAct
  card (2/10 clear τ on test): the message beat works because messages always confirm by rule.
- Memories seeded by talking to the app during rehearsal, never by inserting rows (e.g. "Professor Lee teaches my
  CSCI 335 class", "my brother is Sam Ortiz" only if you want a confident contactPick take).
- Contacts on the demo phone: "Mom", "Sam Lee", "Sam Ortiz". Calendar: two events with "advising" in the title in the
  next 30 days.
- Meta Model API key works in Standard mode before recording 1:32–1:45 (a few calls; your call on spend). If not: cut
  the hand-off live and say "with the API key, this goes to Muse Spark 1.3 in Standard mode" over the orange
  contactPick card (honest fallback).
- Privacy shot (0:45–1:05): rehearse until the `sensitivity` card shows `sensitive` and the lock badge appears. It runs
  whether `route` escalates or answers locally (money words trigger the card), online and offline.
- If the telemetry chart isn't rising, say so or leave it out. Never backfill data.
- Fallback if there's no iPhone build: see docs/FINAL_HOURS.md §C-fallback (Mac run, captioned as a Mac run).

## Placeholders to fill (only from real measurements)
- `[PHONE_CONF]` in each live card: read off the phone while recording; don't type them into other docs.
- `[PHONE_TOK_S]`, `[PHONE_TTFT_MS]`, `[PHONE_RAM_GB]`: iPhone, Release build, airplane mode (docs/FINAL_HOURS.md §B6).
  If not measured, drop the second line of proof slide 1 and the matching voiceover sentence.

## UI elements this script assumes (all present in the code; verify on the device build)
- [x] **Decision-object card**: `type → choice`, confidence %, latency ms, expandable distribution, τ footer.
- [x] **Confidence bar**: turns **orange below τ**.
- [x] **Tool-call view**: the tool-call JSON inside the toolChoice card. *Caveat: the tool is picked by a Reflex
  decision; the arguments are filled by on-device heuristics and memory, not grammar-constrained decoding. Say
  "structured tool call", not "grammar-constrained".*
- [x] **Confirm button** on message sends; after Confirm, the Messages compose sheet (added Nov 4; the Nov 2 tree has no
  compose sheet, so the beat ends at Confirm).
- [x] **Escalation badge**: "Meta Model API · Muse Spark 1.3 (Standard mode)", with an info view showing the masked prompt.
- [x] **"Kept on device · nothing sent" badge** when `sensitivity` keeps a turn on the phone.
- [x] **Sensitivity in airplane mode**: done in code (Nov 4): the `sensitivity` decision now runs offline too and shows its card and the badge. It still **must clear τ on the real phone** in rehearsal before it goes in the video.
- [x] **Offline pill**: "Offline · fully on device" / "Online".
- [x] **Telemetry chart**: on-device share per distillation round, from logged rows only.
- [x] (n/a in app) Lower-third name caption is added in editing.
