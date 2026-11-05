# OffLlama three-minute demo

Updated November 5 for Habib's final recording. This is a recording plan, not
proof of every shot. The user confirmed the multi-line composer, whole-message
Copy, and a reviewed reminder saved in Reminders on installed source `805debf`.
An offline answer of 4 to “What is 2 + 2?” was confirmed on an earlier build.
The Apple TV request still fell into chat on `805debf`; routing repair `b5fdfb0`
passes core tests but awaits installation and phone rehearsal. Screen cleanup is
also in progress. Freeze the final installed build before recording.

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
| 0:30–0:55 | Enter `Remind me to rehearse the demo tomorrow at 9am`. Show the title, date and time on the review card. Keep this shot offline if it passes rehearsal that way. | “I can also ask for something useful: remind me to rehearse tomorrow at nine. OffLlama turns that request into a draft I can check before anything changes.” |
| 0:55–1:15 | Tap Confirm. Show the saved result, then the matching item in Reminders. Return to OffLlama. | “I confirm, and it saves a real reminder through iOS. This is an action on my phone, with the result recorded in the app.” |
| 1:15–1:35 | Enter `Make a chart: rent 1200, food 400, transit 130`. Show the inline chart. Open its decision details only if they identify the rule honestly. | “I can turn a few numbers into a chart right here. This uses a local chart tool—no cloud request.” |
| 1:35–1:55 | Show Chats and New chat, then return to the original conversation. Dismiss the keyboard with its inline button and long-press a message to Copy. Keep a waiting action only if one was intentionally created in rehearsal. | “Chats keep my conversations organized. I can return to an earlier one and copy a whole reply.” |
| 1:55–2:20 | Show the concise architecture diagram in the repository, or record a slide with `Local Llama → validated action → user confirmation → native iOS`. Add a separate optional arrow to `Muse cloud reasoning`. | “Under the hood, Llama chooses how to handle the request. The app checks the action, asks for review, and uses native iOS integrations. Larger Muse models are available for harder questions when I’m online.” |
| 2:20–2:45 | Show the saved shipping benchmark table with its source and `Linux decision benchmark, 120 authored examples` visibly labeled. Do not show a candidate as shipping. | “The shipping model chose the correct option in 98 of 120 authored benchmark decisions. At its current certainty threshold, it accepted 44 and got 41 of those right. These are Linux decision tests. They do not establish a phone task-success rate. Newer candidates stay experimental until they pass the same checks.” |
| 2:45–3:00 | Return to the app, then end with OffLlama, Built with Llama, the repository URL and Habib's name. | “OffLlama connects a small local model to useful phone actions, with visible boundaries and honest outcomes. The code, evaluation and failed experiments are in the repository. Built with Llama.” |

The timing includes typing and short pauses. Record narration after choosing the
successful footage. Trim narration before speeding up action footage. If a wait
is cut, show “time cut” and retain the measured duration where available. Do not
edit a failed action into an apparent success.

## Rehearsal gate

Use an installed Release build whose source commit and model hash are recorded.
Keep that build fixed throughout the recording.

1. Verify the offline answer with both Airplane Mode on and Wi-Fi off. Rehearse the reminder on the final installed build: check the date and time, confirm, and find the matching item in Reminders. The earlier successful phone check used the exact prompt above.
2. Use a dedicated demo contact bound to a number Habib controls. Verify the
   exact recipient, body, Confirm, native composer and Cancel sequence. Do not
   send to another person for the video. No existing group-chat lookup is claimed.
3. Repeat the identical text request after an ordinary chat answer. It must still
   produce the action card. Rehearse the two-turn form too: `text Demo`, then
   `iMessage saying I'll be there at 7.` Keep only the form that actually works.
4. Verify all three chart values appear with the correct labels. A code block,
   plaintext chart or a request to re-enter the numbers does not pass this shot.
5. Verify the composer stays visible while typing several lines. Verify chat
   switching and history recovery on the phone. Check the storage readback in Settings → Advanced.
6. Keep a waiting card, force quit and reopen, and verify the same card returns
   without execution. Cancel it before recording the clean take.
7. Capture only the measured benchmark table. Use
   `eval/results/PER_TYPE_TAU090.md` and `docs/EVALUATION_CLAIMS.md` as the source
   for the shipping decision result. Do not imply that the eight newer candidates
   are installed, or that more training has already improved the phone.

Do not include an alarm, timer, Notes creation, flashlight, Focus, Low Power,
weather-helper or arbitrary-app-opening demonstration. Those helper actions do
not have native implementations in this recording build. An Apple TV shot may
show search results only, after rehearsal; it must not imply automatic playback.

## Optional substitutions

- A verified message flow can replace the reminder shot. Use a demo contact
  Habib controls: `Text Demo saying I'll be there at 7.` Show the recipient and
  body, confirm into the native composer, then cancel. Say “I still control the
  final send.” The completed message status is “Message submitted”; it is not
  a recipient delivery receipt. Rehearse this exact flow first.
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
