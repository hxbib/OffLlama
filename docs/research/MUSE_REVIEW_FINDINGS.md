# Reviewed additions from Muse Wonder 1.0

Review started 2026-11-04. The user assigned Muse Wonder 1.0 through Muse Code ACP at
maximum effort to rerun the Grok investigations. The reports compare source at `009430f`
with the Grok reports and recovery contract; they are research, not device verification.

The [journeys report](MUSE_JOURNEYS_DELTA.md) and its
[independent notes](MUSE_JOURNEYS_INDEPENDENT_NOTES.md) have returned. The capability,
learning and contract reports have not yet been integrated. This document records parent
review decisions, including corrections to Muse's proposals. It takes precedence over the
unreviewed recommendations in those reports.

## Accepted requirements

- Contact identity binding was already in Grok's contract. Muse adds an important missing
  requirement: a contact with multiple phone numbers or email addresses needs an explicit
  method selection. Bind and revalidate the chosen method, not the first address currently
  returned by Contacts. A removed or changed method requires another review.
- Preserve the requested time wording through extraction. Show the resolved date, time and
  timezone on the draft and result. An unsupported zone qualifier must not disappear before
  parsing and become an apparently successful local-time write. Calendar identity and DST
  behavior still require device checks; they are not established by a parsed Date alone.
- Preserve requests arriving while busy as separately identified, explicitly resumable inputs.
  They must retain their own shared document or audio and must not execute automatically.
  The existing one-slot SharedInbox cannot provide this guarantee. Merely moving `put` before
  the busy guard is rejected: a running document request could consume the new request's data.
- Retained memory revisions and diagnostic context need distinct deletion semantics. Removing
  a fact must also remove the revisions it superseded. That repair does not erase telemetry,
  user-created exports, external shares or device backups. Do not claim universal erasure.
- Family-role aliases should become visible contact suggestions requiring review, never silent
  recipient rewrites. Existing-calendar edits, actionable nudges and object-level VoiceOver
  descriptions are useful additional work; they are not implemented by the first recovery slice.

The contact-method, time-display and readable confirmation requirements were sent to the
running recovery implementation. Request-bound deferred input remains a separate integration
unit; no busy-data preservation is claimed yet.

## Corrections and qualifications

Muse's N5 says both SpeechAnalyzer and SFSpeechRecognizer require the older Speech
authorization prompt and usage-description key. Apple explicitly limits that authorization
process to SFSpeechRecognizer; SpeechAnalyzer's transcriber modules do not send voice data
to Apple's servers. Microphone access, model assets, locale and hardware support still need
their own checks. See [Apple's authorization documentation](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition?changes=l_6_4__3__8).

Apple's [WWDC25 SpeechAnalyzer session](https://developer.apple.com/videos/play/wwdc2025/277/)
introduces the API in iOS 26, describes on-device SpeechTranscriber, and identifies
DictationTranscriber as an alternative for other supported languages/devices. This strengthens
the offline-input proposal, but does not establish support, installed assets, latency or
accuracy on the user's phone. These would be OS-provided speech services, not Meta models;
keep that distinction explicit in product and hackathon descriptions. No speech code or new
model has been added by this review. Sources checked 2026-11-04.

Other qualifications:

- A busy result explicitly says the request was not handled. It is poor input preservation,
  but is not evidence that Siri falsely reports the underlying action as completed.
- The code returns proactive nudge text to Shortcuts even without a visible notification.
  The source proves the absence of an app notification response flow, not the exact behavior
  of every denied-notification request on iOS 27.0.1.
- A limited Contacts lookup cannot distinguish an inaccessible contact from a nonexistent
  one. Say the app cannot find the person in its accessible contacts; do not claim to know
  that a particular hidden person exists.
- Regex recognition of compound commands cannot reliably infer all unfulfilled intent.
  Multi-step proposals need explicit reviewed steps; avoid treating a second verb inside a
  message body as another command.
- Badges and the system network indicator alone cannot prove zero network traffic. Offline
  voice acceptance needs request instrumentation or a controlled network capture as well.
- Grok's reports are dated snapshots. Their old message-success quotation was already fixed
  before the Muse review; it is not a newly discovered implementation regression.

## Related retained-history repairs

The [completed G/H history audit](HISTORY_RETAINED_GH.md) independently found unfinished
retention and photo-filter work. Parent verification reproduced the failures before repair:

| Finding | Implemented repair | Evidence |
|---|---|---|
| Forget leaves superseded fact rows | One atomic recursive delete removes the selected fact and its predecessor chain; unrelated facts survive | Real file reopen and budget-eviction regressions |
| Cash receipt with only `TOTAL 42.10` can upload | Amount-bearing receipt text and common currency formats join the lexical floor | Captured fake transport receives zero requests for five amount fixtures even when the classifier says OK |
| CSV share keeps the first export | Generate a fresh file on every share-button tap | Source review and Swift syntax parse; iPhone share-sheet check pending |
| Diagnostic write error aborts a decision | Failed telemetry write returns the computed decision with no telemetry ID and a content-free diagnostic | Read-only SQLite regression; threshold and model errors are unchanged |
| SAM whiteboard confidence overstated | Quote saved whiteboard values 0.812865–0.816092 | Saved `eval/meta_api/sam_segment.json` box confidences |
| Settings and photo privacy copy stale | Describe existing voice control and photo-screening limitations accurately | Source inspection; no universal sensitive-photo guarantee |

The targeted memory/photo suite passed 30 tests (one opt-in live test skipped), and the
decision suite passed three tests. The modified app view passed syntax parsing only.
The two previously committed cloud-text privacy regressions remain assigned to the parallel
privacy repair; these targeted passes do not close them or establish a green integrated suite.

Photo screening still sees only the first 240 OCR characters in the model decision and cannot
classify pixels. The deterministic floor scans all OCR but can miss unrecognized sensitive
content. Full photo privacy is still an open requirement; the upload-off switch is the only
unconditional block. No device acceptance row is marked passed by these repairs.
