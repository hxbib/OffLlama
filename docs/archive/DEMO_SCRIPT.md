> Historical Pocket Glimmer draft. Use the current [OffLlama three-minute recording plan](../demo/OFFLLAMA_THREE_MINUTE_DEMO.md) for the final video. The older claims and shots below require rechecking.

# Pocket Glimmer: 3:00 demo video script

> **Edit-ready cut: [docs/demo/STORYBOARD.md](STORYBOARD.md)** (beat-by-beat timing, verbatim voiceover, fallbacks, 25 s no-iPhone variant, iMovie checklist). Finished slides: `docs/img/slide_01.png` … `slide_11.png` (1920×1080, from `docs/demo/slides.html`; re-render with `bash docs/demo/render_slides.sh`).

Frame: **A 1B Meta model on my iPhone that knows when it doesn't know.** Memory is stored on the phone. Text
escalations mask known names and common identifiers. Optional voice and photo features send media to the cloud;
do not describe those features as fully local or anonymized.
Rules: no title card, no auth or settings screens, no BYOK. `[PHONE_*]` cells are read off the phone while recording
(see ios/MAC_DAY_RUNBOOK.md). Never say a number that isn't measured. Don't show health questions (AI medical advice is
on the event's overdone list); the privacy beat uses money.

**Threshold in the app: τ = 0.90** (the shipping operating point; shipped as `defaultTau` in the bundled
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

## Timeline and voiceover

Use [demo/STORYBOARD.md](STORYBOARD.md) as the single 3:00 cut. The former competing timeline has been removed. Optional beats replace a shot in that timeline; they do not extend it. The storyboard also owns the clearly labeled no-phone variant.

An edited demo shows examples, not a measured real-world success rate. Keep clarifications and handoffs honest: asking “Which Sam?” is not a cloud call, opening Messages is not delivery, and opening Shortcuts is not confirmed playback.

## Pre-shoot checklist
- **Threshold check:** open any decision card; the footer must read τ = 0.90. If it reads 0.80, the bundled
  `calibration.json` didn't load (ios/MAC_DAY_RUNBOOK.md).
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
- Fallback if there's no iPhone build: use the no-phone variant in demo/STORYBOARD.md; label a terminal run by its actual host.

## Placeholders to fill (only from real measurements)
- `[PHONE_CONF]` in each live card: read off the phone while recording; don't type them into other docs.
- `[PHONE_TOK_S]`, `[PHONE_TTFT_MS]`, `[PHONE_RAM_GB]`: iPhone, Release build, airplane mode (ios/MAC_DAY_RUNBOOK.md).
  If not measured, drop the second line of proof slide 1 and the matching voiceover sentence.

## UI elements to verify on the current device build
- [ ] **Decision-object card**: `type → choice`, confidence %, latency ms, expandable distribution, τ footer.
- [ ] **Confidence bar**: turns **orange below τ**.
- [ ] **Tool-call view**: the tool-call JSON inside the toolChoice card. *Caveat: the tool is picked by a Reflex
  decision; the arguments are filled by on-device heuristics and memory, not grammar-constrained decoding. Say
  "structured tool call", not "grammar-constrained".*
- [ ] **Confirm button** on message sends; after Confirm, the Messages compose sheet (added Nov 4; the Nov 2 tree has no
  compose sheet, so the beat ends at Confirm).
- [ ] **Escalation badge**: "Meta Model API · Muse Spark 1.3 (Standard mode)", with an info view showing the masked prompt.
- [ ] **"Kept on device · nothing sent" badge** when `sensitivity` keeps a turn on the phone.
- [ ] **Sensitivity in airplane mode**: done in code (Nov 4): the `sensitivity` decision now runs offline too and shows its card and the badge. It still **must clear τ on the real phone** in rehearsal before it goes in the video.
- [ ] **Offline pill**: "Offline · fully on device" / "Online".
- [ ] **Telemetry chart**: on-device share per distillation round, from logged rows only.
- [ ] (n/a in app) Lower-third name caption is added in editing.
