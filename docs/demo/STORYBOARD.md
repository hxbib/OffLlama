# Pocket Glimmer: 3:00 storyboard (edit-ready)

Companion to docs/DEMO_SCRIPT.md (the shot list and τ = 0.90 rules) and docs/FINAL_HOURS.md §C. The slides are
finished: `docs/img/slide_01.png` … `slide_11.png` (1920×1080, rendered from `docs/demo/slides.html`; regenerate with
`bash docs/demo/render_slides.sh`). In iMovie you drop phone clips and PNGs onto the timeline in this order and lay the
voiceover on top.

**Rules carried over from DEMO_SCRIPT.md:**
- The app runs at τ = 0.90; the decision-card footer must read τ = 0.90.
- Green-bar on-device shots only on contactPick, eventPick, route, toolChoice and sensitivity (PER_TYPE_TAU090.md).
- The message beat confirms by the hard rule "messages always confirm", not by confidence. Don't promise a green
  confirm bar.
- Rehearse every phone shot on the real phone. If it escalates in rehearsal, use the fallback in the last column or cut it.
- `[PHONE_CONF]` = read off the phone while recording. Never say a number that isn't measured.
- No health questions. Never say "never leaves your phone": escalations carry scrubbed memory lines.

Voiceover is verbatim, ≤ 30 words per beat, at about 2.5 words/s.

| # | Time | On screen | Voiceover (verbatim) | Must be visible | Fallback if it escalated / failed in rehearsal |
|---|---|---|---|---|---|
| 1 | 0:00–0:10 | **Phone clip.** Airplane Mode ON (icon visible). Pill "Offline · fully on device". Type *"Remind me to call Mom at 7."* Cut to Reminders. | "Airplane mode is on. No signal. It still does what I asked, on the phone." | `route → tool [PHONE_CONF]%`, `toolChoice → create_reminder [PHONE_CONF]%`, then the reminder in Reminders. Tap Confirm if asked | If route escalates (orange), retype with fewer words ("Remind me 7pm call Mom"). If still orange, open on beat 2's text-Mom clip and drop this one |
| 2 | 0:10–0:14 | **slide_01.png** (title) | "Pocket Glimmer: a Meta model that knows when it doesn't know." | Title + "Built with Llama" badge | Always available |
| 3 | 0:14–0:26 | **slide_02.png** (the moment). Lower third: "Habib · CS student, Hunter College · Bronx" | "I'm Habib, a CS student at Hunter, living in the Bronx. My commute is underground. Memory stays on my phone; the cloud only sees masked text." | Lower third | Alternative: phone zoom on a decision card with the same lower third (DEMO_SCRIPT 0:10–0:25) |
| 4 | 0:26–0:42 | **Phone clip.** Still offline. *"Text Mom I'll be home by 8."* Tap Confirm → Messages compose sheet, text filled in | "Every step is a typed decision with a confidence bar. Anything that speaks for me, like a message, always asks first. That's a rule, not a guess." | `toolChoice → send_message [PHONE_CONF]%`, confirm card (orange is fine), JSON tool call, Confirm button, compose sheet | If toolChoice is orange, keep it anyway: the confirm card still appears by rule. Change VO to "It isn't sure, so it shows me first." |
| 5 | 0:42–0:58 | **Phone clip.** Airplane OFF on camera (pill → "Online"). *"Help me budget: my salary is $2,100 a month and I owe $3,400 on my credit card."* | "Now I'm online. But this is my money, so it keeps it on the phone. Nothing is sent, even though the cloud is right there." | `sensitivity → sensitive [PHONE_CONF]%` and the lock badge "Kept on device · nothing sent", with "Online" pill visible. **No** Muse Spark badge | If sensitivity isn't confident, rephrase with more money words ("…my bank balance is $212"). If it still escalates, cut the beat and give 0:42–0:58 to beat 8 + slide_09 |
| 6 | 0:58–1:08 | **Phone clip.** *"When's my advising meeting?"* (two advising events on the calendar) | "Two advising meetings. It picks the right one on the phone, and the bar says how sure it is." | `eventPick → [event] [PHONE_CONF]%`, **green** bar, answer with date and time | If orange, keep the "Which one?" take and say: "Two advising meetings, and it isn't sure which. So it asks." |
| 7 | 1:08–1:17 | **Phone clip.** *"Text Sam I'm running late."* (Sam Lee + Sam Ortiz in Contacts, nothing in memory) | "Two Sams, and the small model isn't sure. So it doesn't guess. It asks." | `contactPick [PHONE_CONF]%` **orange below τ** → "Which Sam? Sam Lee, Sam Ortiz" | If contactPick is confident (green), cut this beat; don't fake it |
| 8 | 1:17–1:29 | **Phone clip (online).** *"DM Sam on Instagram: congrats"* → Confirm → Instagram opens the DM thread; status line "message copied to clipboard" | "Open-world actions use one more decision: which of 35 skills. It confirms, opens Instagram's own DM link and copies the text. iOS won't let any app press Send." | `skillPick → instagram_dm [PHONE_CONF]%` card, Confirm button, Instagram DM screen, clipboard status line | If it asks "Which Sam?", tap Sam Lee on camera (it's contactPick again, and that's fine). If skillPick is orange ("Did you mean: Instagram DM, …"), tap Instagram DM and keep the take: VO "Not sure which app, so it asks, then confirms." If Instagram isn't installed, cut beats 8–9 |
| 9 | 1:29–1:33 | **slide_09.png** (skills) | "Right skill 23 of 25 times, on a small smoke test." | 23/25 and 13/14 tiles, the N=25 footer | Cut if beat 8 is cut |
| 10 | 1:33–1:45 | **Phone clip (online, Meta key set).** *"Plan my week around Professor Lee's CSCI 335 final and my calc midterm."* Tap info → masked prompt | "Hard planning goes to Muse Spark 1.3 in Standard mode, so my data isn't used for training. Names are masked before anything leaves." | `route → escalate_cloud` (or orange) → badge "Meta Model API · Muse Spark 1.3 (Standard mode)"; info view showing `[PERSON_1]` | If the key fails: show the orange card and say "With the API key, this goes to Muse Spark 1.3 in Standard mode, names masked." Never show a fake answer |
| 11 | 1:45–1:53 | **OPTIONAL phone clip (online): voice.** Hold mic, say *"Remind me to call Mom at 7"*, release | "Voice goes through Muse Voice Transcribe, then through exactly the same decisions as typed text." | Transcript line `Muse Voice Transcribe · … · recording deleted`, then the same decision cards | Only if the mic works on the device build (META_MULTIMODAL.md: API verified live, iOS UI not yet verified on a device). Otherwise use the answerability swap below, or give the 8 s to beat 12 (1:45–2:03) |
| 12 | 1:53–2:03 | **slide_03.png** (how a decision works) | "Under the hood, each decision is one forward pass. It reads the answer-letter logits, compares confidence to a threshold, then acts or falls back." | Flow boxes, τ = 0.90, the 12 chips + skillPick (dynamic) | Always available |
| 13 | 2:03–2:15 | **slide_04.png** (before/after) | "On 120 held-out decisions, distilling from Muse Glimmer took accuracy from 74 to 82 percent, and it keeps three times as many on the phone." | Table + footer "frozen held-out test, N=120, one item = 0.83 pts" | Always available. Add phone speed only if `[PHONE_TOK_S]` was measured (DEMO_SCRIPT 1:45 row) |
| 14 | 2:15–2:27 | **slide_05.png** (certified threshold + risk–coverage) | "The threshold isn't a guess: at 0.9, errors among kept decisions stay at or under about ten percent, assuming new requests look like my calibration set." | τ = 0.90, 36%, 0 errors, ≤ 10.2%, the orange exchangeability box, chart | Always available |
| 15 | 2:27–2:36 | **slide_06.png** (out-of-scope) | "On 2,000 out-of-scope requests, it confidently kept just five on the phone. The untrained model only looks safe because it's unsure of everything." | 0.25% and the blanket-abstention panel | Always available |
| 16 | 2:36–2:46 | **slide_07.png** (four Meta models) | "Every model is Meta's. Meta distilled Glimmer from Spark; I distilled Glimmer into a 1B for my pocket. Spark gets only the hard questions." | Four cards + lineage line | Always available |
| 17 | 2:46–2:50 | **slide_08.png** (negative results) | "I kept what failed, too." | Six cards + Round 2 line | Always available |
| 18 | 2:50–2:54 | **slide_10.png** (closed loop) | "Its doubts become the next lesson." | Loop diagram | Always available |
| 19 | 2:54–2:57 | **Phone clip.** Airplane Mode ON again, Memory tab scrolls | "Open weights on the phone, Meta's cloud only when unsure…" | Airplane icon, Memory tab | Reuse the end of beat 1's clip |
| 20 | 2:57–3:00 | **slide_11.png** (close + repo URL) | "…It's in my pocket." | Repo URL | Always available |

**Optional swap, answerability offline (replaces beat 11, airplane mode ON):** *"What's my landlord's new Wi-Fi
password?"* → `answerability → no [PHONE_CONF]%` → "I can't answer that offline." VO: "Offline, when it can't know
the answer, it says so instead of making one up." (15 words). Keep it only if the card clears τ on the phone (3/10
clear τ on test).

**Timing check:** 20 beats, 0:00–3:00. Phone clips total 1:36 (beats 1, 4–8, 10, 11, 19); slides 1:24 (beat 3 is a slide with the lower third). If a phone beat
is cut, stretch its neighbour slide (slow the VO) rather than adding new claims.

## 25-second "no iPhone" variant (Mac run, labelled as such)

Use only if there's no working iPhone build (FINAL_HOURS.md C-fallback), or as a teaser. The caption **"Mac run, not
iPhone"** stays on screen for the whole terminal segment.

| Time | On screen | Voiceover (verbatim) |
|---|---|---|
| 0:00–0:04 | slide_01.png | "Pocket Glimmer: a Meta model that knows when it doesn't know." |
| 0:04–0:14 | Mac screen recording, Wi-Fi off (menu bar icon visible): `swift run pg-cli e2e --url http://127.0.0.1:8088 --tau 0.9 --calibration ../app/PocketGlimmer/Resources/Models/calibration.json` scrolling decisions with `conf` and `esc`. Caption: **"Mac run, not iPhone · Wi-Fi off"** | "Wi-Fi off, on my Mac: every decision gets a confidence. Below the threshold it escalates instead of guessing." |
| 0:14–0:21 | slide_05.png | "The threshold comes with a statistical error bound, assuming new requests look like my calibration set." |
| 0:21–0:25 | slide_11.png | "Built with Llama. It's open." |

Don't read the Mac run's totals aloud unless you read them off that screen (the box run gave 16/18 argmax, 10/10
correct on kept; E2E_SWIFT_SHIPPING.md, box CPU).

## 10-minute iMovie assembly checklist

1. **New project:** iMovie → Create New → Movie. File → Project Settings: theme None. Export will be 1080p.
2. **Import:** File → Import Media → select all phone clips (AirDrop them from the iPhone first) and
   `docs/img/slide_01.png` … `slide_11.png`.
3. **Kill Ken Burns:** select all PNGs on the timeline → Cropping (crop icon) → **Fit**. Otherwise iMovie pans and zooms the slides.
4. **Lay out the timeline** in the table order. Set each PNG's duration (select → clip inspector, or drag the edge) to
   the table's seconds. Trim phone clips to their windows. Use straight cuts; at most a 0.3 s cross-dissolve into slides.
5. **Lower third (beat 3):** Titles → "Lower Third" → text `Habib · CS student, Hunter College · Bronx`, over
   0:14–0:26. For the no-iPhone variant, add the "Mac run, not iPhone · Wi-Fi off" title over the whole terminal segment.
6. **Voiceover:** Window → Record Voiceover (mic icon) and read each beat's line over its clip, or record the whole VO
   in Voice Memos and drop it on the audio track. Mute the phone clips' audio (select → volume 0) unless it's clean.
7. **Check length:** the timeline must be **≤ 3:00**. Watch it once at full screen and check every `[PHONE_CONF]` you say
   matches the card on screen.
8. **Export:** File → Share → File → Resolution **1080p**, Quality High, Compress Better Quality → save as
   `pocket-glimmer-demo.mp4`.
9. **Upload:** YouTube → upload as **Unlisted** first, wait for HD processing, watch it once → switch to **Public**
   (the submission needs a public video, FINAL_HOURS.md §D). Title: `Pocket Glimmer: a 1B Meta model on iPhone that
   knows when it doesn't know`.
10. **Logged-out check:** open the link in a private window. It must play at full length, with sound, in HD. Paste the
    link into the submission and README only after this.
