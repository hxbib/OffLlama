# OffLlama three-minute demo

Prepared November 4 for Habib's final recording. This is the recording plan, not a
claim that every shot has passed on the latest build. Rehearse the exact installed
commit once before filming. The confirmed phone result is an answer of 4 with
Airplane Mode on and Wi-Fi off. The newer conversation build is awaiting review
and installation. Keep the narration aligned with what appears on screen.

## Story

A small Llama model runs on the iPhone. It can answer offline, make bounded
decisions, and prepare native actions. The app checks action arguments and asks
for confirmation before messaging. Larger Muse models supply optional cloud
reasoning and experimental training labels. The demonstration should show useful
behavior first, then explain the model and its measured limits.

## Recording timeline and spoken script

| Time | Screen and exact action | Narration |
| --- | --- | --- |
| 0:00–0:15 | Begin on the iPhone. Show Airplane Mode on and Wi-Fi off, then return to OffLlama. | “I'm Habib. I ride the subway in New York, where a useful assistant needs to keep working without a signal. This is OffLlama, with a small Llama model running on my iPhone.” |
| 0:15–0:30 | In a new chat, enter `What is 2 + 2?`. Show the answer and on-device badge. Keep the real waiting time visible in this shot. | “The network is off. This answer comes from the model on the phone. The interface tells me where the answer came from.” |
| 0:30–0:55 | Turn connectivity back on for the native messaging demonstration. Enter `Text Demo saying I'll be there at 7.` Use the contact verified in rehearsal. Show the recipient and exact body on the review card. | “Now I ask it to text my demo contact. An action request becomes a structured draft with the recipient and message visible. The app does not treat a chat reply as proof that a message was sent.” |
| 0:55–1:15 | Tap Confirm. Show the native Messages composer containing the correct recipient and body. Cancel in the native sheet, then show the resulting app status. | “Confirm opens the native iOS message composer. I still control the final send. Here I cancel, and OffLlama records the cancellation. It does not claim delivery.” |
| 1:15–1:35 | Enter `Make a chart: rent 1200, food 400, transit 130`. Show the inline chart. Open its decision details only if they identify the rule honestly. | “For structured tasks, the app can use a direct local implementation. These numbers become a chart inside the conversation. That distinction matters: model decisions and application rules are shown separately.” |
| 1:35–1:55 | Show Chats and New chat, then return to the original conversation. Dismiss the keyboard once. Keep a waiting action only if one was intentionally created in rehearsal. | “Separate chats keep the working context organized. Recent chat context is used for local answers. The action journal keeps unfinished work visible across a restart, without automatically performing it.” |
| 1:55–2:20 | Show the concise architecture diagram in the repository, or record a slide with `Local Llama → validated action → user confirmation → native iOS`. Add a separate optional arrow to `Muse cloud reasoning`. | “The local model scores a small set of choices, including whether to answer, ask, or use an action. Low certainty takes a fallback. Typed contracts check what can actually run. Optional cloud reasoning screens text first and exposes the outbound text for inspection.” |
| 2:20–2:45 | Show the saved shipping benchmark table with its source and `Linux decision benchmark, 120 authored examples` visibly labeled. Do not show a candidate as shipping. | “The shipping model chose the correct option in 98 of 120 authored benchmark decisions. At its current certainty threshold, it accepted 44 and got 41 of those right. These are Linux decision tests. They do not establish a phone task-success rate. Newer candidates stay experimental until they pass the same checks.” |
| 2:45–3:00 | Return to the app, then end with OffLlama, Built with Llama, the repository URL and Habib's name. | “OffLlama connects a small local model to useful phone actions, with visible boundaries and honest outcomes. The code, evaluation and failed experiments are in the repository. Built with Llama.” |

The timing includes typing and short pauses. Record narration after choosing the
successful footage. Trim narration before speeding up action footage. If a wait
is cut, show “time cut” and retain the measured duration where available. Do not
edit a failed action into an apparent success.

## Rehearsal gate

Use an installed Release build whose source commit and model hash are recorded.
Keep that build fixed throughout the recording.

1. Verify the offline answer with both Airplane Mode on and Wi-Fi off.
2. Use a dedicated demo contact bound to a number Habib controls. Verify the
   exact recipient, body, Confirm, native composer and Cancel sequence. Do not
   send to another person for the video. No existing group-chat lookup is claimed.
3. Repeat the identical text request after an ordinary chat answer. It must still
   produce the action card. Rehearse the two-turn form too: `text Demo`, then
   `iMessage saying I'll be there at 7.` Keep only the form that actually works.
4. Verify all three chart values appear with the correct labels. A code block,
   plaintext chart or a request to re-enter the numbers does not pass this shot.
5. Verify the composer stays visible while typing several lines. Verify chat
   switching and history recovery on the phone. Check the Chats storage readback.
6. Keep a waiting card, force quit and reopen, and verify the same card returns
   without execution. Cancel it before recording the clean take.
7. Capture only the measured benchmark table. Use
   `eval/results/PER_TYPE_TAU090.md` and `docs/EVALUATION_CLAIMS.md` as the source
   for the shipping decision result. Do not imply that the eight newer candidates
   are installed, or that more training has already improved the phone.

## Optional substitutions

- A verified reminder creation can replace the chart shot. Use an explicit date
  and time, show the review, then show the saved item in Reminders. Rehearse the
  exact phrase first. Describe this as an EventKit result, not message delivery.
- A verified cloud answer can replace the chat-list shot. Show the provider badge
  and the exact screened outbound text. Never show an API key or private material.
  Say that cloud reasoning is optional; do not describe the entire app as offline.
- A multi-step action can replace the architecture shot only after its complete
  app flow passes on the phone. The current journal-core tests alone do not meet
  that condition. Do not include the unit as a working phone feature prematurely.
- If a new UI feature fails rehearsal, keep the valid footage and shorten the
  video. Do not use a mockup as live application evidence.

## Production setup

Use demo text and a clean chat. Turn on Focus to avoid notification banners. Set
readable text size and a stable orientation. Keep private contacts, memories and
past chats out of the recording. Save credentials before recording and leave
replacement-key fields empty. Avoid Settings footage unless the shot requires it.
The app's key fields are concealed, but a video should not depend on a blur added
later to hide a secret.

Record the native screen at full resolution and keep the raw take. Add narration
and captions in an editor, export a 1080p MP4 under three minutes, and verify the
uploaded video plays while logged out. Preserve the exported file and final URL.

## Final-hour order

Freeze features when Habib starts submission preparation. Complete only fixes
needed for the selected demonstration and final repository checks. Record the
installed commit, shipping hashes and phone acceptance results. Then finish the
README, public-history secret check, model/license links and concise submission
description. Record and upload the video, verify the public repository and video
links, and leave time to submit the form and retain its confirmation.

This file supersedes the older Pocket Glimmer demo drafts for the final recording.
