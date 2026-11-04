# OffLlama conversations: independent review and Apple verification (Reviewer B)

Reviewer: fresh independent reviewer, Claude Sonnet 5.5 (claudeAgent_2), high effort, no subagents.
Reviewed source: `origin/master` **f87567b48170b802a7b68a1ccf5c6c5f4f36f203** (functional d3a76dd). Branch `review/conversations-independent-apple-2026-11-04`.
Production source was not edited. User files (`Info.plist`, `MAC_BUILD_2026-11-04.md`) preserved. Xcode 27.2, team 2VGYC6S9F3.
Nothing was installed. Nothing here was observed on a phone.

## Verdicts

| Gate | Verdict | Basis |
|---|---|---|
| A. Fix diff 85ffccc vs prior four warnings + nit | **PASS for the prior items; FAIL on one new regression (A-1)** | Parent's regression tests for empty-registry card, bare-`that` channel/group, compact charts and summary bytes pass in the 376-test suite. New probes found the chart change breaks year-labelled and unit-labelled lists. |
| B. Conversations/product review | **FAIL: 4 warnings, 0 critical** | B-1 to B-4 below. Nits listed. |
| C. Plan core d6f88bf migration + single-action claim | **PASS on core, not phone-ready** | Legacy-schema probe migrates and is idempotent; `claim` returns early for rows with `plan_size` NULL; all existing single-action and ActionPlan tests pass. Plans are not wired to the app, so no plan behavior is claimed. Full independent plan review is still a separate gate. |
| Core tests (macOS, exact source) | **PASS** | `swift test`: 376 executed, 1 skipped (opt-in live), 0 failures. `ios/.build/review-core-full.log`. |
| Unsigned Release build + bundle check | **PASS** | `ios/mac_prep.sh build-unsigned`, `ios/.build/review-unsigned.log`. |
| Signed Release build + codesign + bundle check | **PASS** | `generic/platform=iOS`, team 2VGYC6S9F3, `codesign --verify --deep --strict` valid, TeamIdentifier 2VGYC6S9F3, `check-app` PASS (`ios/.build/review-signed2.log`, `review-signed2-summary.log`). Not installed. |
| Physical-iPhone protection/persistence test | **COULD NOT RUN** | The iPhone (00008150-000A59811180401C) is listed Offline by xctrace; a device-destination build failed with "Unable to find a destination" (`review-signed.log`). `devicectl` is not on PATH. The project has no device test target. The earlier simulator failure (`file protection could not be verified`) is unresolved and is not a device pass. |
| Device UI / phone behavior | **COULD NOT RUN** | No device tool use attempted; device panel previously unavailable. |

Note: the first pipeline run recorded `codesign_exit=0`/`checkapp_exit=0` in `review-build-meta.txt` against a stale ff54688 product after its device-destination build failed. Those lines are not evidence. The valid signed evidence is `review-signed2*.log`, run after deleting the old `.app`.

## Artifact hashes (signed bundle, read from the .app)

- Source: f87567b48170b802a7b68a1ccf5c6c5f4f36f203
- Executable `PocketGlimmer`: sha256 d3b7298623fc32b7935eaf454acbe58ec95d9ca99439cca24f1c492025eb2bab
- Model: 807694080 bytes, sha256 a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2 (matches)
- `calibration.json`: sha256 b9ce25b5223103944803c2668784c484ac7eee75b33aa984e62185728970a8f1, tau 0.90 (checked by `check-app`)

## Findings

### A-1 [warning] Chart parser regression: years and units become bars or labels
`core/Sources/PocketCore/Skills.swift` `HTMLViz.pairs`. 85ffccc removed the `", "` split and keeps every number in a segment.
Path: any chart request, `Assistant.handle` before routing. Probe (`probe-output.txt`, old function copied verbatim for comparison):

| Input | before 85ffccc | now |
|---|---|---|
| `sales 2023 100, sales 2024 200` | sales 2023=100, sales 2024=200 | sales=2023, #2=100, sales=2024, #4=200 (end to end: "Chart ready: 4 bars") |
| `Jan 2023 100, Feb 2023 200` | correct 2 bars | 4 bars with years as values |
| `5 apples, 3 pears` | #1=5, #2=3 | #1=5, **apples=3** |
| `temperature 72 degrees, humidity 40 percent` | humidity=40 | label "degrees humidity" |

Impact: a plausible chart request renders a wrong chart while saying "Chart ready". Suggested fix: keep `", "` as a segment boundary, then split compact lists inside each segment; treat a 4-digit year-like number that directly follows a label and precedes another number as part of the label. Add the first two rows as tests.

### B-1 [warning] Composer text is lost on refusal
`app/PocketGlimmer/Views/ChatView.swift` send button: `let t = input; input = ""; Task { await model.send(t) }`; `AppModel.send` returns a refusal string for chat-full (`hasRoomForTurn` needs 4 free), >24,000 characters, and busy/not-loaded races. The string is discarded. A pasted long message is lost with only the global orange notice. Source-traced (app target cannot run here). Fix: clear the field only after `send` accepts, or restore it on refusal.

### B-2 [warning] Stored chat text can forge system turns in the local prompt
`ConversationContext.render` output is interpolated into the **system** turn by `Assistant.localPrompt(history:)`; `LlamaCppEngine.tokenize` uses `special: true`. Probe: an assistant message containing `<|eot_id|><|start_header_id|>system<|end_header_id|>…` yields two forged system headers in the system block; it persists for 6 turns and includes cloud-assistant text. Newline flattening does not remove tokens. Impact is bounded (on-device generation only, no tools in that path), but it raises untrusted text to system authority. Fix: strip `<|` … `|>` in `render` (and add a test).

### B-3 [warning] Post-work append failures are silent
`AppModel.append` catches `ConversationError` and only sets `historyNotice`. (a) `restoreHistory` adds an unknown waiting card to `book.activeID`; on a full chat the card has no message and the user cannot reach the waiting action until a later launch (core repro: a 200-message chat refuses a pending-action message). (b) A reply over 24,000 characters is dropped and `send` returns "". Source-traced for AppModel; core refusal reproduced. Fix: restore into a fresh chat when the active one is full; truncate or split an oversize reply instead of dropping it.

### B-4 [warning→nit, reviewer judgment: warning] `.unreadable` aside is overwritten
`ConversationStore.setAside` removes an existing `history-v1.unreadable` first. Probe: two corrupt events leave only the second file. The build report says unreadable history is "never overwritten". Fix: unique suffix per event.

### Nits (do not block)
- `AppModel.lastRoute`/`decisions` are global, so a new chat shows the previous chat's route strip.
- Chats footer asserts "protected while locked and left out of backups" above the readback line; it should read as the readback, since simulator readback already failed.
- `Error: \(error.localizedDescription)` and `Couldn't read saved actions: \(error)` system lines are persisted to history; they can carry raw error text.
- `Send that to Dana as an email` now asks "who should I send that to?" (bare `that` ends the head); safe clarify, no action.
- A card restored after a crash lands in the active chat, not the chat that asked, because the ledger records no conversation id.
- `persist()` is a synchronous full-snapshot write on the main actor after every append.
- Comments: no phase-narration problem found in the reviewed diff.

## Checks that passed (with the reproduction)
- Intent: `text Dana that email is down` and `…the group chat moved to 7` stage an `imessage_send` card on tool and chat routes; `email Dana that the group chat moved` stages `email_compose`; `performCount == 0` before Confirm in every probe. `send Dana an email that says hi` falls to chat (reply "OK") under a scripted answer route; I did not determine whether that predates 85ffccc.
- Context boundary: diff shows `conversationContext` used only in `localPrompt`; parent's transport tests assert the cloud body has no history.
- Clear keeps `pendingAction` messages and drafts are dropped; Delete refuses; `busyConversationID` blocks Clear/Delete on the in-flight chat; confirm/edit/cancel resolve the owning chat by message id, so cross-chat ownership holds. `confirm`/`edit` do not set `busyConversationID`, but a card message is pending, so Clear keeps it and Delete refuses.
- Ledger reconciliation failure now stops publishing the Assistant (`bootOnce`), and `recover()` places every non-settled row in `showAgain` or `unresolved`.
- Atomic save: same-directory `rename` replaces the tmp file; oversize snapshot keeps the old file (parent tests).

## Still open / not proven
- Complete file protection and backup exclusion on a real device (init and after later writes), first-unlock behavior, kill-during-claim recovery, App Intent process behavior.
- Keyboard/composer visibility, Chats UI, dialogs, Settings picker and Muse Voice Transcribe heading on a phone (source reads correctly: composer is a `.safeAreaInset(edge: .bottom)`, picker has Custom, heading text matches).
- Live-model routing: the installed build is 7857cd68; scripted tests are not live-model evidence.
- Secret-safe demo: no secret reaches history in the reviewed paths except user-typed text itself; not exercised on a phone.

## Artifacts
Logs under `ios/.build/`: `review-core-full.log`, `review-probes-1.log`, `review-probes-2.log`, `review-unsigned.log`, `review-signed.log` (failed device destination), `review-signed2.log`, `review-signed2-summary.log`. Probes and their output are committed under `docs/verification/independent-review-probes-2026-11-04/`.
