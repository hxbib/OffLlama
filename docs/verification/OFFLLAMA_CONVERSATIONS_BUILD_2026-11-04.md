# OffLlama conversations build

Branch `feature/offllama-conversations`, built on `origin/master` f77e5e8 plus the cherry-picked parent repair 85ffccc.
**Built source SHA: `ff54688f1276fcd635317ef900d6f8a1e92a2716`.** Xcode 27.2, iPhoneOS SDK 27.2, team `2VGYC6S9F3`.
**Installed SHA: none.** The signed build exists locally but was not installed, because the parent coordinates the
independent review first. The phone still runs the earlier 7857cd68 build. Nothing below was observed on a phone.

## What changed

1. **Keyboard.** The chat composer moved from a `VStack` under the `ScrollView` to `.safeAreaInset(edge: .bottom)`, so the
   scroll view, keyboard and composer share one inset. Scroll-to-bottom runs on focus and while typing. The field grows to
   5 lines. Done still resigns any responder. Choice rests on documented SwiftUI safe-area behavior. It is **not measured**:
   there was no device automation. Glimpse, Settings and card fields live inside `ScrollView`/`Form` and were not changed.
2. **Conversations.** `ConversationBook` (core) holds `ConversationID`-keyed chats, each with its own ordered messages and
   its own unfinished `MessageDraft`s. `AppModel.send` captures the chat ID before any await and writes the reply, card,
   notes and drafts to that chat, whichever chat is on screen when it finishes. Card actions (confirm, edit, cancel,
   refresh contact) find the owning chat from the message ID. UI: **Chats** list (top left), **New chat** (top right),
   swipe or long-press for **Clear messages** and **Delete chat**, both behind a confirmation that says what changes.
3. **Persistence.** One protected JSON snapshot (`Application Support/PocketGlimmer/Conversations/history-v1.json`).
   Chosen over one file per chat because a single atomic replace keeps all chats and the active selection consistent and
   the 4 MiB bound keeps each write small. Limits: 40 chats, 200 messages per chat, 24,000 characters per message, 5 drafts
   per chat, 4 MiB encoded. Nothing is evicted: a full chat or chat count refuses with a message, an oversize snapshot
   fails the save and keeps the old file, and a save failure shows an orange notice above the composer. Complete file
   protection and backup exclusion are applied with readback (same pattern as `RequestInputStore`). Unreadable or
   future-version history is renamed to `history-v1.unreadable`, never overwritten. Bundle id is unchanged.
   Not stored: effect records, cards, decision rows, screened cloud text, API keys, raw remote errors.
4. **Effects stay in the ledger.** A message stores only the ledger `attemptID` and whether it is pending (a waiting card
   or an unverified outcome). On launch, waiting cards are re-attached to their saved message, unknown cards are added to
   the active chat, unresolved attempts are shown as rebuilt (unsaved) notes, and a saved pending message whose attempt has
   settled is rewritten to say so. **Clear** keeps those messages and says how many. **Delete** is refused while a chat has
   one. Neither touches the ledger, and neither replays or cancels anything. Restored drafts are checked against the
   ledger's `request_id` column before follow-up is enabled; a draft whose action already reached the ledger is dropped
   with a notice. Clear and Delete are refused while that chat has a request in flight.
5. **Context.** `ConversationContext` renders at most the last 6 user and assistant turns, 300 characters each, 1,200
   total, skipping cards, pending actions and system lines. Parent-approved edit: `Assistant.handle(conversationContext:)`
   and `localPrompt(history:)`, default empty and byte-identical. It reaches **only on-device generation prompts**
   (answer, clarify, sensitive-local, offline and cloud-failed fallback). It is never in routing contexts, Reflex decisions,
   draft handling or any cloud request, so **cloud requests get no chat history**. A follow-up that routes to the cloud
   therefore has no memory of earlier turns. Saved long-term memory is separate and New chat, Clear and Delete do not touch it.
6. **Readable numbers.** Primary surfaces use `DecisionPresentation`: "Answer on this iPhone", "Create a reminder",
   "Model certainty 62%, below the 90% needed". The shown choice is the option actually used. When the model's top option
   differs (fell back because it was under the bar) a note says so. A rule-based path (explicit message request or numeric
   chart request over a different route pick, or a draft follow-up) is stated under *How this was decided*. Raw ids,
   probabilities, tau and the tool JSON moved to Details. The old per-turn "ms" was the **sum of classifier passes**; it is
   now labelled that way in Details, and the badge shows real elapsed time measured around `assistant.handle`
   ("answered in 1.8 s"). Action status uses `ActionStatusLabel`: needs your review, saved on this iPhone, Messages sheet
   completed (delivery not confirmed), handed to iOS (result not confirmed), cancelled, outcome unverified. A score is never
   presented as a success or delivery probability.
7. **Settings (parent steering).** Meta model is a picker: Muse Spark 1.3 / 1.2 / 1.1 and Muse Wonder 1.0
   (source: dev.meta.ai/docs/models) plus **Custom**, which shows a Model ID field. A saved unknown or custom value opens in
   Custom unchanged; nothing is substituted. The existing Standard-mode validator is still the authority, so contributor
   ids are shown as refused and never requested. The heading is exactly **Muse Voice Transcribe**. The on-device toggle is
   now "Reuse prompt prefix in the on-device model", off by default, explained as local-only, and says speed is unmeasured.
   The footer says the cloud service caches prompt starts itself and there is no switch here. No speedup is claimed and no
   cache control was added.

## Diagnosis of the repeated-message state (real device data, aggregate only)

`devicectl device copy from` pulled `pocket.sqlite` (+ WAL) from the app container (`ios/.build/device-diag/`, gitignored).
I read **only** columns type, chosen, confidence, escalated, latency, time. I did not read the `context` column and nothing
private is committed. 71 logged decisions, 20:48 to 22:50 UTC on the installed 7857cd68 build:

| Route decision | n | below the 0.90 bar | confidence range |
| --- | --- | --- | --- |
| top option answer_local | 10 | 9 | 0.39 to 0.91 |
| top option tool | 10 | **10** | 0.40 to 0.85 |
| top option clarify | 2 | 1 | 0.90 to 0.99 |

All ten `tool`-ranked route decisions were under the bar and therefore fell to the cloud-route fallback; rememberOrNot was
under the bar 19 of 22 times. Mean route time 439 ms. The ledger had 3 `imessage_send` and 1 `html_viz` attempts, all
settled. So the live 1B model is routinely unsure on exactly the requests that must be actions. A repeated message request
that lands as a low-confidence route would reach chat generation unless a rule intercepts it. That is consistent with the
reported "hii" and with the parent's rule-based guards, but **I cannot tie any specific logged row to the "hii" turn
without reading private prompt text, which I did not do**. No prompt-level, before/after-generation comparison with the
live model was possible here: the llama xcframework is `ios-arm64` only, so the bundled engine cannot run in a macOS test
runner, and there is no device automation. Scripted tests are not live-model evidence.

## Tests actually run

- Core suite on macOS (`swift test`, Swift 6.2.3): **360 executed, 1 skipped (opt-in live), 0 failures**
  (`ios/.build/conv-core-full2.log`).
- New: `ConversationTests` (18) and `DecisionPresentationTests` + `MetaModelPresetTests` (7):
  isolation, blank-chat reuse, titles, full-chat and chat-count refusal, clear keeps pending and drops drafts, delete
  refusal, clear never touches the ledger, round trip across relaunch, ephemeral not written, oversize save keeps the old
  file, unreadable and future-version set aside, attribute readback, ledger reconciliation (real `EffectLedger` stage, then
  a stale draft is dropped), context bounds, **context only in the on-device prompt**, **real `OpenAICompatibleBrain`
  transport body never contains history on success or on the cloud-failure fallback** (the fallback's local prompt does),
  empty-context prompts byte-identical on every local path, labels have no raw ids, status labels never imply delivery.
- Unsigned Release build via `ios/mac_prep.sh build-unsigned`: PASS, app bundle check PASS (`conv-final-unsigned.log`).
- Signed Release build, team 2VGYC6S9F3: PASS. `codesign --verify --deep --strict`: valid, TeamIdentifier `2VGYC6S9F3`,
  identifier `com.habib.pocketglimmer`. `check-app` PASS (`conv-final-signed.log`, `conv-final-signed-check.log`).
- **Apple protection readback: partly run.** On macOS the backup-exclusion readback passes; the iOS-only complete-protection
  branch cannot run there. I ran `ConversationTests` and `RequestInputStoreTests` on the **iOS 27.2 Simulator** (project
  test runner, no UI automation). Result: the iOS branch executes, but the simulator does not report the Complete
  protection class, so **all 23 `RequestInputStoreTests` and the 5 file-writing `ConversationTests` fail closed** with
  "file protection could not be verified". The pure-logic tests passed (13 of 18 `ConversationTests`). That is a simulator
  limitation shared by the existing store, not evidence that a phone passes or fails. Whether a real iPhone reports
  `NSFileProtectionComplete` for these files is **unverified**. The Chats sheet footer shows the file system's own
  readback for the phone check below. If readback fails on the phone, chat still works in memory and an orange notice says
  history is not being saved.

## Resource hashes (signed bundle, read from the .app)

- Model `SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf`: 807,694,080 bytes, SHA-256
  `a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2`.
- `calibration.json`: 4,687 bytes, SHA-256 `b9ce25b5223103944803c2668784c484ac7eee75b33aa984e62185728970a8f1`, tau 0.90, fewShot.
- Framework provenance check passed. Icon `AppIcon` unchanged. Display name OffLlama. HTML isolation, protected key entry
  and the privacy shield sources are unchanged.

## Limitations

- **Nothing here was seen on a phone.** Keyboard behavior (portrait, landscape, Dynamic Type, multi-line, card fields,
  sheets), the Chats UI, dialogs and the new labels are compiled but unobserved. `AppModel` glue has no unit test; the
  logic it calls is covered in core.
- Chat history is not sent to the cloud, so cloud follow-ups lack earlier turns. Making it cloud-aware needs the privacy
  boundary applied to every history line and was not attempted.
- A pending or unverified action keeps its chat undeletable until resolved, and "outcome unverified" has no resolution
  button, so such a chat can only be cleared (the item stays). Honest, but sticky.
- A message from before a save gap (kill during a turn) can be lost; the ledger-backed cards are not.
- Group chats: the parent's unsupported-group refusal is unchanged. No existing-group lookup was added.
- `RequestInputStore` is still not wired to ingress; chat storage does not solve busy, voice or camera admission.
- Parent items still open: fresh independent review of the core repairs, Apple F3 checks in
  `CORE_FIX_REPAIRS_V2_2026-11-04.md`.
- A disk-full condition (ENOSPC) interrupted the shell once during the simulator test; I removed only my own
  `ios/.build/CoreSimDerived` and nothing else.

## Short phone checks (after the parent approves install)

1. Open Chats. Footer says protection complete and backups excluded (else note what it says).
2. Type in the composer to 5 lines, in portrait and landscape, and with large Dynamic Type: nothing sits under the keyboard.
   Done dismisses it. Tap a draft-card text field: it scrolls into view.
3. Ask "what is 2+2", tap New chat, ask "what did I just ask": the new chat has no earlier turn.
4. Switch away while a reply is running: the reply appears in the chat where you asked.
5. "text Dana hi": a review card appears, status "Needs your review". Clear the chat: the card stays. Delete: refused with a reason.
6. Force quit and reopen: chats and the waiting card are back. Cancel the card: status "Cancelled · nothing done".
7. "Make a chart: rent 1200, food 400, transit 130": inline chart. Tap *How this was decided*: the note names the rule.
8. Settings: model picker shows Muse Spark 1.3 and Custom; enter a contributor id: refused. Heading reads Muse Voice Transcribe.

## Review-fix round (source `003ab249213447a57646984c3940efe7d570783b`, branch `feature/offllama-conversations-fixes` off f87567b)

Independent Reviewer B findings acted on (items 2 to 4 and nits; item 1, `HTMLViz.pairs` in Skills.swift, is parent-owned and untouched):

- **Typed text lost on refusal.** `AppModel.sendRefusal(for:)` now runs before the field is cleared; a full chat or an over-long
  paste keeps the text and shows the orange notice.
- **Forged prompt headers.** `ConversationContext.neutralize` breaks every `<|` and `|>` in stored text before it enters the
  on-device system prompt. Test: a stored reply with `<|eot_id|><|start_header_id|>system...` yields only the three real headers.
  The user's own current utterance still goes into the prompt unchanged by this code path (Assistant is parent-owned).
- **Dropped waiting action.** Restore places unknown cards and unresolved notes via `ConversationBook.chatWithRoom()` (active chat,
  else a fresh chat, else any chat with room). If every chat is full and no new chat is allowed, a persistent notice says so;
  nothing is run or cancelled. A >24,000-character reply is now shortened with a marker instead of dropped.
- **Nits.** Unreadable history gets a unique `history-v1.unreadable-<uuid>` name (a second bad file no longer replaces the first;
  test added). The decision strip follows the active chat. The Chats footer no longer asserts protection above the readback line.
  The two generic error lines are not persisted.

Tests: core suite on macOS 378 executed, 1 skipped, 0 failures. Unsigned Release PASS, signed Release PASS (team 2VGYC6S9F3),
`codesign --verify --deep --strict` valid, `check-app` PASS, model and calibration SHA-256 unchanged. **Not installed. Still unobserved on a phone.**
