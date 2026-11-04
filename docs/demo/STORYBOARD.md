> Historical Pocket Glimmer draft. Use the current [OffLlama three-minute recording plan](OFFLLAMA_THREE_MINUTE_DEMO.md) for the final video. The older claims and shots below require rechecking.

# Pocket Glimmer: canonical 3:00 storyboard (edit-ready)

This is the canonical 3:00 cut. docs/DEMO_SCRIPT.md holds the τ = 0.90 rehearsal checks; docs/FINAL_HOURS.md should
point here for the shot list. The slides are the 11 PNGs `docs/img/slide_01.png` … `slide_11.png` (1920×1080,
rendered from `docs/demo/slides.html`; regenerate with `bash docs/demo/render_slides.sh`). In iMovie you drop phone
clips and PNGs onto the timeline in this order and lay the voiceover on top.

**Claim guardrails (check every take against these):**
- **Shipping model:** ep1 Q4_K_M, Glimmer-only, unchanged. Round 2 (Spark Open labels, H100 LoRA sweep) finished and
  was **rejected**; the Spark Open teacher experiment was rejected too. Say "rejected", not "running" or "may ship".
- **Skill probe:** 36 built-in skills. N=27 author-written smoke test: retrieval **27/27**, argmax **25/27**,
  **15/27** kept at τ = 0.90, **15/15** correct when kept. `skillPick` was never trained and has no cal180
  certificate. Full iOS action behavior is unverified on a device.
- **Privacy:** typed escalations send masked text. Voice audio uploads to Muse Voice Transcribe **before** any
  on-device sensitivity check. A permitted photo leaves as an image with EXIF/GPS stripped; the question text is
  masked, the **pixels are not redacted**. The photo gate is heuristic, not a guarantee. Never say "never leaves your
  phone" or "nothing leaves" for voice or photos.
- **Apple TV:** `appletv_play` only hands to a **user-installed Shortcut**. The app cannot detect whether it is
  installed, cannot confirm playback, and cannot guarantee the latest episode. The status must read **"Handed to
  Shortcut"**, not "Playing". If a build still says "Playing", do not use that take until the status is corrected.
  Fallback is a manual TV-app search or a labelled clip.
- **Clarifications are plain chat text.** The core sends a text question ("Which Sam? Sam Lee, Sam Ortiz"), not a
  tappable option picker. Never script a tap on a clarification choice.
- **No phone success claims.** Do not say the app runs on an iPhone, give phone speeds, or claim a public video unless
  that take was recorded and checked. If the phone build is unavailable or unverified, use the labelled Mac/Linux
  variant at the end and keep its caption on screen.
- **Evaluation:** the earlier 10.2% certificate is withdrawn. cal180 also selected the model. Use the measured counts on slide 5; see docs/EVALUATION_CLAIMS.md.
- No health questions.

**Rules carried over from DEMO_SCRIPT.md:**
- The app runs at τ = 0.90; the decision-card footer must read τ = 0.90.
- Green-bar on-device shots only on contactPick, eventPick, route, toolChoice and sensitivity (PER_TYPE_TAU090.md).
- The message beat confirms by the hard rule "messages always confirm", not by confidence. Don't promise a green
  confirm bar.
- Rehearse every phone shot on the real phone. If it escalates in rehearsal, use the fallback in the last column or cut it.
- `[PHONE_CONF]` = read off the phone while recording. Never say a number that isn't measured.

Voiceover is verbatim, ≤ 30 words per beat, at about 2.5 words/s.

| # | Time | On screen | Voiceover (verbatim) | Must be visible | Fallback if it escalated / failed in rehearsal |
|---|---|---|---|---|---|
| 1 | 0:00–0:10 | **Phone clip.** Airplane Mode ON (icon visible). Pill "Offline · fully on device". Type *"Remind me to call Mom at 7."* Cut to Reminders. | "Airplane mode is on. No signal. It still does what I asked, on the phone." | `route → tool [PHONE_CONF]%`, `toolChoice → create_reminder [PHONE_CONF]%`, then the reminder in Reminders. Tap Confirm if asked | If route escalates (orange), retype with fewer words ("Remind me 7pm call Mom"). If still orange, open on beat 2's text-Mom clip and drop this one. If no phone build, use the Mac variant |
| 2 | 0:10–0:14 | **slide_01.png** (title) | "Pocket Glimmer: a Meta model that knows when it doesn't know." | Title + "Built with Llama" badge | Always available |
| 3 | 0:14–0:26 | **slide_02.png** (the moment). Lower third: "Habib · CS student, Hunter College · Bronx" | "I'm Habib, a CS student at Hunter, living in the Bronx. My commute is underground. Memory stays on my phone; typed escalations send masked text." | Lower third | Alternative: phone zoom on a decision card with the same lower third (DEMO_SCRIPT 0:10–0:25) |
| 4 | 0:26–0:42 | **Phone clip.** Still offline. *"Text Mom I'll be home by 8."* Tap Confirm → Messages compose sheet, text filled in | "Every step is a typed decision with a confidence bar. Anything that speaks for me, like a message, always asks first. That's a rule, not a guess." | `toolChoice → send_message` or `skillPick → imessage_send [PHONE_CONF]%`, confirm card (orange is fine), JSON tool call, Confirm button, compose sheet | The exact phrase is below the skill threshold in the Linux real-model check and asks for clarification. Use a compose-sheet take only after successful device rehearsal; otherwise show the clarification and say "It asks me to restate the action" or cut the beat. Do not imply every orange tool decision reaches confirmation. |
| 5 | 0:42–0:58 | **Phone clip.** Airplane OFF on camera (pill → "Online"). *"Help me budget: my salary is $2,100 a month and I owe $3,400 on my credit card."* | "Now I'm online. But this is my money, so it keeps it on the phone. Nothing is sent, even though the cloud is right there." | `sensitivity → sensitive [PHONE_CONF]%` and the lock badge "Kept on device · nothing sent", with "Online" pill visible. **No** Muse Spark badge | If sensitivity isn't confident, rephrase with more money words ("…my bank balance is $212"). If it still escalates, cut the beat and extend beats 6 and 10 |
| 6 | 0:58–1:08 | **Phone clip.** *"When's my advising meeting?"* (two advising events on the calendar) | "Two advising meetings. It picks the right one on the phone, and the bar says how sure it is." | `eventPick → [event] [PHONE_CONF]%`, **green** bar, answer with date and time | If orange, keep the "Which one?" take and say: "Two advising meetings, and it isn't sure which. So it asks." The question is text, not buttons |
| 7 | 1:08–1:17 | **Phone clip.** *"Text Sam I'm running late."* (Sam Lee + Sam Ortiz in Contacts, nothing in memory) | "Two Sams, and the small model isn't sure. So it doesn't guess. It asks." | `contactPick [PHONE_CONF]%` **orange below τ** → chat text "Which Sam? Sam Lee, Sam Ortiz" (plain text, not a picker) | If contactPick is confident (green), cut this beat; don't fake it. Do not tap an option: the core only sends a text question |
| 8 | 1:17–1:29 | **OPTIONAL phone clip (online).** *"Open the latest episode of Severance on Apple TV."* Tap Confirm if the card asks, then read the status line. It must say **"Handed to Shortcut 'PG Play on Apple TV'"**. If the user-installed Shortcut is present, Shortcuts may start playback; the app cannot verify it. | "Open-world actions use one more decision: which of 36 skills. Here it hands the show to my Shortcut; that's a handoff, not the app pressing play." | `skillPick → appletv_play [PHONE_CONF]%` card, Confirm button only if the trained confirm decision asks (`appletv_play` has no hard-confirm rule), status line **Handed to Shortcut**, Shortcuts/TV screen. Do not show or say "Playing" as confirmation | If the Shortcut is missing, Shortcuts says so; do not fake playback. Open the TV app manually and search "Severance" on camera (manual open/search), or use a labelled clip. If skillPick is orange, answer the text question in chat or cut. If routing fails, cut this beat and keep slide_09 |
| 9 | 1:29–1:33 | **slide_09.png** (skills) | "Right skill 25 of 27 times, author-written smoke test." | 25/27 argmax, 27/27 retrieval, 15/15 correct when kept, 15/27 kept, the N=27 footer | Always available; cut only if the cut runs long |
| 10 | 1:33–1:45 | **Phone clip (online, Meta key set).** *"Plan my week around Professor Lee's CSCI 335 final and my calc midterm."* Tap info → masked prompt | "Hard planning goes to Muse Spark 1.3 in Standard mode, so my data isn't used for training. Names are masked before anything leaves." | `route → escalate_cloud` (or orange) → badge "Meta Model API · Muse Spark 1.3 (Standard mode)"; info view showing `[PERSON_1]` | If the key fails: show the orange card and say "With the API key, this goes to Muse Spark 1.3 in Standard mode, names masked." Never show a fake answer |
| 11 | 1:45–1:53 | **OPTIONAL phone clip (online): voice.** Hold mic, say *"Remind me to call Mom at 7"*, release | "Voice uploads to Muse Voice Transcribe first; then the transcript goes through the same decisions as typed text." | Transcript line `Muse Voice Transcribe · 2.6 s · 83 KB sent · recording deleted`, then the same decision cards. The audio leaves before any on-device check; the recording is deleted after upload unless keep-recordings is on | Only if the mic works on the device build (META_MULTIMODAL.md: API verified live, iOS UI not yet verified on a device). Otherwise use the answerability swap below, or give the 8 s to beat 12 |
| 12 | 1:53–2:03 | **slide_03.png** (how a decision works) | "Under the hood, each decision is one forward pass. It reads the answer-letter logits, compares confidence to a threshold, then acts or falls back." | Flow boxes, τ = 0.90, the 12 chips + skillPick (dynamic) | Always available |
| 13 | 2:03–2:15 | **slide_04.png** (before/after) | "On 120 held-out decisions, distilling from Muse Glimmer took accuracy from 74 to 82 percent, and it keeps three times as many on the phone." | Table + footer "frozen held-out test, N=120, one item = 0.83 pts" | Always available. Add phone speed only if `[PHONE_TOK_S]` was measured (DEMO_SCRIPT 1:45 row) |
| 14 | 2:15–2:27 | **slide_05.png** (shipping threshold + risk–coverage) | "At the shipping threshold, it accepted 44 of 120 test decisions, with 41 correct. These are measured choices, not a guarantee of complete task success." | τ = 0.90, 44/120 accepted, 41/44 correct, model-selection limitation, chart | Always available |
| 15 | 2:27–2:36 | **slide_06.png** (out-of-scope) | "A thousand out-of-scope requests became two thousand decision tests. Five were falsely confident. The untrained model mostly abstained." | 0.25% and the blanket-abstention panel | Always available |
| 16 | 2:36–2:46 | **slide_07.png** (Meta model roles) | "Every model is Meta's. Meta distilled Glimmer from Spark; I distilled Glimmer into a 1B for my pocket. Spark gets only the hard questions." | Student, teacher, Spark escalation, optional self-hosted Glimmer endpoint + lineage line. The endpoint card says cloud-only, saved smoke, not current liveness | Always available |
| 17 | 2:46–2:51 | **slide_08.png** (negative results) | "I kept what failed. Round 2 was rejected; ep1 still ships." | Six cards + Round 2 line "finished · rejected · ep1 stays" | Always available |
| 18 | 2:51–2:54 | **slide_10.png** (closed loop) | "Its doubts become the next lesson." | Loop diagram | Always available |
| 19 | 2:54–2:57 | **Phone clip.** Airplane Mode ON again, Memory tab scrolls | "Open weights on the phone, Meta's cloud only when it needs it…" | Airplane icon, Memory tab | Reuse the end of beat 1's clip. If no phone build, use the Mac variant |
| 20 | 2:57–3:00 | **slide_11.png** (close + repo URL) | "…That's Pocket Glimmer." | Repo URL | Always available |

**Optional swap, answerability offline (replaces beat 11, airplane mode ON):** *"What's my landlord's new Wi-Fi
password?"* → `answerability → no [PHONE_CONF]%` → "I can't answer that offline." VO: "Offline, when it can't know
the answer, it says so instead of making one up." (15 words). Keep it only if the card clears τ on the phone (3/10
clear τ on test).

**Timing check:** 20 beats, 0:00–3:00. Phone clips total 1:36 (beats 1, 4–8, 10, 11, 19); slides 1:24 (beat 3 is a
slide with the lower third). If a phone beat is cut, stretch its neighbour slide (slow the VO) rather than adding new
claims. Beat 8 is optional; if it is cut, keep slide_09 and give the 12 s to beat 10.

## 25-second "no iPhone" variant (Mac run, labelled as such)

Use only if there's no working iPhone build (FINAL_HOURS.md, no-phone path), or as a teaser. The caption **"Mac run, not
iPhone"** stays on screen for the whole terminal segment.

| Time | On screen | Voiceover (verbatim) |
|---|---|---|
| 0:00–0:04 | slide_01.png | "Pocket Glimmer: a Meta model that knows when it doesn't know." |
| 0:04–0:14 | Mac screen recording, Wi-Fi off (menu bar icon visible): `swift run pg-cli e2e --url http://127.0.0.1:8088 --tau 0.9 --calibration ../app/PocketGlimmer/Resources/Models/calibration.json` scrolling decisions with `conf` and `esc`. Caption: **"Mac run, not iPhone · Wi-Fi off"** | "Wi-Fi off, on my Mac: every decision gets a confidence. Below the threshold it escalates instead of guessing." |
| 0:14–0:21 | slide_05.png | "At the shipping threshold, 41 of 44 accepted test decisions were correct. That is a measurement, not a guarantee." |
| 0:21–0:25 | slide_11.png | "Built with Llama. Open weights, small enough for a phone." |

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
   (the submission needs a public video, FINAL_HOURS.md §D). Title: `Pocket Glimmer: a 1B Meta model built for iPhone`. Label a non-phone recording in the title and on screen.
10. **Logged-out check:** open the link in a private window. It must play at full length, with sound, in HD. Paste the
    link into the submission and README only after this.
