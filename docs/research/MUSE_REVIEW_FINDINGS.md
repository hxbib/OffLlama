# Reviewed additions from Muse Wonder 1.0

Review started 2026-11-04. The user assigned Muse Wonder 1.0 through Muse Code ACP at
maximum effort to rerun the Grok investigations. The reports compare source at `009430f`
with the Grok reports and recovery contract; they are research, not device verification.

All four Muse reports have returned and are archived here. Their recommendations remain
research until the parent verifies them against source or primary documentation. This
review takes precedence over conflicting recommendations in the snapshots.

- [User journeys](MUSE_JOURNEYS_DELTA.md) and [independent notes](MUSE_JOURNEYS_INDEPENDENT_NOTES.md).
- [iOS capabilities](MUSE_CAPABILITY_DELTA.md).
- [Learned workflows](MUSE_LEARNING_DELTA.md) and [independent notes](MUSE_LEARNING_INDEPENDENT_NOTES.md).
- [Recovery contract](MUSE_CONTRACT_REVIEW.md) and [independent notes](MUSE_CONTRACT_INDEPENDENT_NOTES.md).

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
Those targeted passes did not close the cloud-text regressions. Subsequent integration of
`886047e`, the window-budget correction and B/F alias/export repairs passes 136 tests with
one skipped at Nov 4 17:39 UTC. Independent review and iPhone verification remain open.

Photo screening still sees only the first 240 OCR characters in the model decision and cannot
classify pixels. The deterministic floor scans all OCR but can miss unrecognized sensitive
content. Full photo privacy is still an open requirement; the upload-off switch is the only
unconditional block. No device acceptance row is marked passed by these repairs.

## Contract corrections accepted after the remaining reports

These are requirements for the running first recovery slice. They are not claims that the
implementation has passed. The original Grok contract remains a design snapshot.

| Muse finding | Parent judgment and required behavior |
|---|---|
| F1, displayed dates change at confirmation | Execute the stored instant. Revalidate whether it is usable without reparsing a relative phrase. An elapsed date needs an explicit edit and another review. |
| F2, edits race with claims | Store a draft revision and atomically apply approved edits and claim that revision, or prove an equivalent serialization contract. Test the exact winning body and recipient, not only the effect count. |
| F4, compiled policy lacks binding/execution data | Resolve argument kinds, required fields and invocation from compiled definitions. Cover every trained tool and keep reads out of effect executors. User JSON cannot supply native authority. |
| F6, attempt UUID in memory text | Do not embed receipt tokens in user memory. Repeated identical autoreply saves use semantic subject/attribute/value verification. `MemoryStore.upsert` preserves old text on its idempotent path. |
| F7, read confirmations disappear | Preserve required email/document review and its request-bound payload. A typed read result must preserve cloud provider, actual sent text and withheld state through immediate and confirmation paths. |
| F8, contact method and stale choices | Bind the exact selected method and value. A last-four display suffix alone is not unique. Refresh inaccessible or removed choices without silently switching recipients. |
| F10, two compose sheets and cancellation | Treat presenter contention as retryable only when the adapter proves nothing started. Cancel the owned presentation/continuation safely; a task cancellation alone does not prove no external action occurred. |
| F14, custom handoff destination hidden by a title | Validate external URL templates and schemes; reject raw insertion and unsafe destinations. Show the actual resolved destination and concrete invocation before confirmation. |

The current contract explicitly says to re-resolve instants, claims only by phase, and puts
attempt tokens into memory text. Parent inspection confirmed those three contradictions.
The remaining accepted rows close gaps in the proposed API migration and its existing
callers. Their acceptance tests remain part of Slice 1 review.

## Useful additions for later work

- Native flashlight control is a real public API opportunity that Grok's platform discussion
  missed. Apple's [torch API](https://developer.apple.com/documentation/avfoundation/avcapturedevice/settorchmodeon(level:))
  documents locking/configuration and failure conditions. Prefer explicit on/off with read-back;
  do not claim a Shortcut handoff already proves torch state. No native adapter has been added.
- Approved saved workflows could be exposed as dynamic
  [AppEntity values](https://developer.apple.com/documentation/appintents/appentity) and a staging
  intent. The intent must stage the current approved version for review, not execute effects.
- The future planner should honor the configured Standard-mode Meta model. Do not silently
  replace Wonder with Spark. [Meta's overview](https://dev.meta.ai/docs/overview) documents the
  shared request interface. Structured-output behavior still needs a fixture and a live check
  before a planner capability is claimed.
- `recordCorrection` and `reflexContext` have no production callers. Record explicit corrections
  when the feedback UI exists. Cancellation alone is not a corrected training label. Do not
  inject corrections into frozen decision prompts without a new calibration study.
- Novel skill vocabulary can lose to an existing trained tool before retrieval. Exact approved
  workflow triggers should work independently of the current keyword override table. This does
  not justify changing the frozen option sets or misinterpreting words inside message bodies.
- Before multi-step workflows, enforce order inside the atomic claim, allow one confirmed step
  per tap, and stop after failure or ambiguity. Muse's suggested predicate incorrectly treats
  every settled/ambiguous predecessor as permitting progress. Completion must mean a permitted
  successful predecessor, not merely a terminal row.
- Future callback work needs explicit waiting presentation, expiry on foreground/relaunch,
  bounded return text and cold-start buffering. Do not reserve unused tables now.
- Attempt bodies need visible retention/deletion and backup semantics. Purging must retain an
  identity tombstone and sufficient receipt state to prevent replay. Muse's suggested 30-day
  policy is a proposal, not a user preference or implemented retention guarantee.

## Rejected or qualified recommendations

- Apple Foundation Models and Private Cloud Compute are outside the user's Meta-only model
  runtime constraint. Do not add either reasoner as a hackathon enhancement. OS speech/OCR
  proposals also need a separate eligibility decision before any new model integration.
- The UPI citation is specialized device enrollment, not a general delivery receipt for
  Messages. Apple's [UPI callback documentation](https://developer.apple.com/documentation/messageui/mfmessagecomposeviewcontroller/setupiverificationcodesendcompletion(_:))
  confirms carrier transmission only for its entitled SMS flow. Grok's ordinary-message
  delivery boundary remains correct; its example must not become a product escape hatch.
- Muse's claim that calendar sync strips an attempt note was not demonstrated. Keep the
  conservative read-back rule until an actual SDK/device case establishes a needed change.
  The exact identifier lookup API still requires a Mac build and phone tests.
- Do not replace full contact-method binding with a label and last four digits. Two methods
  can share both. Display masking is not execution identity.
- A read-only skill may invoke cloud reasoning or consume a document. Merely deleting its
  confirmation or marking it completed before it runs is not an acceptable shortcut.
- A pasteboard write after app handoff may race with app suspension. Local-only/expiry options
  are worth testing, but the suggested ordering is not yet a verified repair.
- The proposed calendar-search token inversion cannot infer that "dentist" means "dental".
  That semantic example is not evidence for a one-line search fix.
- Unknown names in shared documents are a real limit of the known-name scrubber. A new name
  extractor is not a small guaranteed fix and may itself use a non-Meta model. Do not claim
  universal anonymization or silently add such a model. Complete-window screening guarantees
  coverage of sent text, not perfect sensitive-content or entity detection.
- AlarmKit was already present in Grok's journey/contract work. Re-ranking it is useful, but
  is not a new discovery. Version-dependent LongRunningIntent, advanced snippets, DOCX import,
  recurring calendar actions and speech support remain candidates requiring SDK/device proof.

Sources above were checked on 2026-11-04. Apple's Markdown documentation was fetched after
its HTML pages returned JavaScript shells. No current iPhone build, device interaction,
new runtime model, paid inference, or training run resulted from these reviews.

## Retained B/F audit integration

The [B/F audit](HISTORY_RETAINED_BF.md) records complete retained-position coverage and the
historical payload truncations that could not be recovered. It independently found ordinary
email misrouting, a memory-recall placeholder, cloud skill provenance loss, null-context
training exports and unmasked memory aliases. Parent tests reproduced the last two before
repair. The first three overlap the active recovery/reply migration and were passed to its
implementer with behavior tests required. The unconsumed Instagram autoreply promise and
the sensitive-offline answerability gap remain open until their owning paths are corrected.
