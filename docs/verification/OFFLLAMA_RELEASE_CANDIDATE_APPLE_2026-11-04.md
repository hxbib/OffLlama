# OffLlama release candidate: independent fix-diff review and Apple verification

Reviewer: Gmail Claude Sonnet 5.5 (high), linked Mac, checkout `/Users/habib/src/pocket-glimmer`, Xcode 27.2 (DEVELOPER_DIR set on every command), team `2VGYC6S9F3`.
Production source was not edited. Scratch probes live outside the repo; their output is in `ios/.build/rc-review-*.log` (local, gitignored).

| Role | SHA |
| --- | --- |
| Reviewed | `7bb9c490a56e9969b29f16cf4bb2e22ef6a8f387` (origin/master; functional change 5382349) |
| Built (unsigned and signed) | `7bb9c490a56e9969b29f16cf4bb2e22ef6a8f387` |
| Installed | `7bb9c490a56e9969b29f16cf4bb2e22ef6a8f387`, signed build from `ios/.build/SignedDerivedData` |

**No phone UI outcome was observed.** The app was installed with `devicectl device install app` and never launched. No message was sent and no contact or calendar data was touched. The device panel was not used (agent-device 0.21.31 still missing per the brief).

## Verdicts

| Item | Verdict | Evidence |
| --- | --- | --- |
| A. Chart repair 5784c72 | **PASS** (3 nits) | 50-input old-vs-new probe, `rc-review-chart-probe.log`. Prior failures fixed, no value regression found. |
| B1 composer loss on refusal | **PASS** | Refusals return before `onAccepted`, so the field keeps the text. See C. |
| B2 stored special-token injection | **PASS** | `ConversationContext.neutralize`. Exhaustive check over all strings of length 1..8 from `< \| > a space newline`, after newline flattening: 0 survivors of `<\|` or `\|>` (`rc-review-neutralize-fuzz.log`). Core test passes. |
| B3 recovered cards / oversize reply | **PASS** | `chatWithRoom` (active, else fresh chat, else any with room), `unplaced` count surfaced as a notice, `ConversationBook.fit` shortens with a marker. Core tests pass. |
| B4 corrupt snapshot overwrite | **PASS** | Per-event UUID suffix. Test writes two bad files and finds both. |
| B extras: per-chat route strip, honest footer, generic errors ephemeral | **PASS** | `lastRoute` derives from the active chat. The footer shows the file-system readback, not an assertion. `Error:` lines carry `ephemeral: true`. |
| C. `onAccepted` composer clearing | **PASS** (1 nit) | Compiles in both Release builds. `AppModel` is `@MainActor`, the callback is `@MainActor`, and `send` runs it after admission and `busy = true` with no `await` before it. Refusals (busy, no model, empty, too long, chat full) return before it, so typed text stays. No durable-input-store claim is made here. |
| D. Route-only context 22e67a6 + 5382349 | **PASS** | `Assistant.swift:141-193`: `routeCtx` goes only to the route decision. `ctx = mem + routeCtx` is byte-identical to the old context and feeds toolChoice, contactPick, eventPick, skillPick, confirmBeforeAct and the planners. answerability and local generation still use `mem`. Both tests assert the exact route row `Network: offline\nUser: ...` and the retained memory in the pick context and local prompt. No numerical claim checked. Shipping model, calibration, tau and DecisionPrompt are unchanged. |
| Full core tests | **PASS** | `swift test`: 386 executed, 1 skipped (opt-in live), 0 failures (`rc-review-core.log`). |
| Unsigned Release build | **PASS** | EXIT 0, product removed first and freshly built (`rc-review-unsigned.log`). `check-app --require-model` PASS. |
| Signed Release build | **PASS** | `BUILD SUCCEEDED`, product removed first, mtime 18:55:52 (`rc-review-signed.log`). |
| `codesign --verify --deep --strict` | **PASS** | "valid on disk", "satisfies its Designated Requirement". Identifier `com.habib.pocketglimmer`, TeamIdentifier `2VGYC6S9F3`. |
| `check-app` on the signed product | **PASS** | "APP BUNDLE PASSED" (`rc-review-signed-check.log`). |
| Name, icon, bundle id | **PASS** | `CFBundleDisplayName` OffLlama, `CFBundleIconName` AppIcon, bundle id `com.habib.pocketglimmer`. |
| Install on iPhone 17 Pro (00008150-000A59811180401C) | **PASS (installed, not launched)** | `devicectl` exit 0, `App installed`, bundleID `com.habib.pocketglimmer` (`rc-review-install.log`). |
| Physical file-protection / persistence | **COULD NOT RUN** | No device test target. Core tests run on macOS and do not prove iOS protection. Read the Chats footer on the phone. |
| Device UI checks (keyboard, chat switch/clear, chart, repeated message, footer) | **COULD NOT RUN** | Device panel unavailable. Left to root's manual pass. |

No critical or warning findings. Installed as authorized.

## Resource and executable hashes (signed bundle)

- Model `SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf`: 807694080 bytes, sha256 `a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2`. Matches the expected value.
- `calibration.json`: sha256 `b9ce25b5223103944803c2668784c484ac7eee75b33aa984e62185728970a8f1`, defaultTau 0.90, fewShot, 31 prior sets. Matches.
- Signed executable `PocketGlimmer`: sha256 `a316ea29193a8792ac0c79b8d8d1f78fa20ceea9845871dcc3e32419577f4eaf`.
- Unsigned executable (separate build): sha256 `0dbd50f747d9fb8e2fcd750278810833718c4468d44ee3963d40a7a2427444e7`.
- `Frameworks/llama.framework/llama`: sha256 `adb93beca517a6debbdb132cb4f6e997902f2e73a64e09538201300c82059541`.
- `Info.plist`: sha256 `dcdb8ddd057368627a50f79df6b9ac7fb3a8fb3cd0b324f71658dd75e270e832`.

## Findings (all nits, none block)

**N-1 [nit] A comma between a label and its number loses the labels.** `core/Sources/PocketCore/Skills.swift:HTMLViz.pairs` (comma now splits segments, around lines 340-345 of the new version). `bob, 5, alice, 7` gave `bob=5, alice=7` before 5784c72 and gives `#1=5, #2=7` now. `Smith, John 5, Doe, Jane 7` gives labels `John`, `Jane`. Values stay correct and paired in order, only labels degrade. Smallest fix: if a comma-split segment has no label and the previous one ends with a letter-only fragment, use it as the label. Not worth the risk before rehearsal.

**N-2 [nit] Value-first lists without a colon label the first bar with the request word.** `HTMLViz.requestData` passes the whole utterance when there is no colon. `chart 5 apples, 3 pears` gives `chart=5, pears=3`. Before: `chart=5, apples=3`. With `Make a chart: 5 apples, 3 pears` (the tested form) it is correct. Rehearse with the colon.

**N-3 [nit] The "I'm working on another request" and "No request was provided" notices are sticky.** `AppModel.send` now calls `noteHistory` on these refusals. `historyNotice` is cleared only for save failures (`AppModel.swift:357`), so a notice from a rare double-tap or a share request that arrives while busy stays above the composer until another notice replaces it. The same stickiness already existed for chat-full and too-long at f87567b. Not reachable from a single normal tap because the button is disabled once `busy` is set.

Other unchanged nits (global `decisions`, synchronous snapshot write, `special: true` tokenization of user text and memory facts, Files sharing enabled in the generated Info.plist) are not caused by these fixes.

## Not covered

- Live-model routing quality and any numeric benchmark. Scripted tests are not live-model evidence.
- Multi-step UI and durable busy/voice/camera intake, which remain unwired by design.
- The Chats storage footer on the phone: the first install check should read protection `complete` and backups `excluded`. A different value there is the result to report.

## Local logs

`ios/.build/rc-review-core.log`, `rc-review-unsigned.log`, `rc-review-unsigned-check.log`, `rc-review-signed.log`, `rc-review-signed-check.log`, `rc-review-codesign.log`, `rc-review-hashes.log`, `rc-review-install.log`, `rc-review-chart-probe.log`, `rc-review-neutralize-fuzz.log`.
