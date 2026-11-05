# Resumed final review, signed build and install: 4376810

Source reviewed, built and installed: `4376810e5cdbaf56b2d4b5c429154d9cd61fb5a3` (origin/master). Previous install: `805debf`. Diff reviewed: `805debf..4376810`. No source repairs. This report is committed on branch `review/resumed-final-4376810` only.

## Verdict

No blockers. Safe to ship.

- **Apple TV (b5fdfb0).** `ActionPlanner.isExplicitAppleTVRequest` matches only a whole command: open, play, watch or put on, then a title, then "on/in (the) Apple TV" or "TV app". It allows an optional "can/could/would you" and "please" in front. Questions, negations, message bodies, quoted text and compound requests do not match, and tests cover each. A match goes straight to the compiled `appletv_play` contract. That happens after the route decision but whatever route it picks, and without `skillPick` or chat generation. `explicitDraftOverride: true` sets `mustCard`, so the user always sees a review card first. Nothing runs before confirm. The action is the URL template `https://tv.apple.com/search?term={show}`, which only searches. The review text says it does not start playback, and a test checks that. A second confirm does not perform the action again. If the show title is missing, the app asks for it instead of chatting.
- **Message wording (b5fdfb0).** The repeated warning "Delivery is not confirmed" is gone. The status labels now read "Message submitted" and "Mail queued". The state types still separate submitted from delivered: `.sheet(.messagesQueuedOrSent)` is not committed, and tests check that no summary contains "deliver".
- **UI (c774bad).** The `app/` patch is byte-identical to `b78d1c6`. It shortens copy and moves explanatory footers into Details. It changes no behavior.
- **Copy (4376810).** Three lines are corrected. The Memory empty state no longer says memories stay on this phone. The Profile details now say relevant details can go with cloud requests after screening. Onboarding no longer claims "milliseconds" decisions.
- Nit, not blocking: an explicit Apple TV command sent while a message draft is pending first goes through `MessageFollowUp.resolve`. This is the same order as before the change.

## Evidence (UTC, 2026-11-05)

| Check | Result |
| --- | --- |
| Core `swift test` (macOS, Xcode 27.2 toolchain) | 399 executed, 1 skipped, 0 failed, 00:50:21 to 00:50:34. All 6 Apple TV tests passed |
| Project generation | `scripts/generate-offllama-project.sh`, exit 0. The preserved Info.plist was not touched |
| Signed Release build (team 2VGYC6S9F3, existing `ios/.build/SignedDerivedData`) | BUILD SUCCEEDED 00:51:19 |
| Freshness and exact source | HEAD `4376810`, clean tree except the 2 preserved untracked files. Branch checked out 00:49:5x. Binary mtime 00:51:19 |
| Binary strings | Present: "Which show would you like to find on Apple TV?", "Message submitted", "Review or forget saved details here.", "Small decisions, on device", "A summary of your saved memories." Absent: "Delivery is not confirmed", "Reflex decides in milliseconds", "Memories stay on this phone." |
| Executable sha256 | `4f4a54b799354cf009d8b26d3dd7adf4806e5c89a917263d7e2ec7aee9420589` |
| `codesign --verify --deep --strict` | OK. Identifier com.habib.pocketglimmer, TeamIdentifier 2VGYC6S9F3 |
| `bash ios/mac_prep.sh check-app --require-model` | APP BUNDLE PASSED |
| Model | 807694080 bytes, sha256 `a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2` |
| Calibration | sha256 `b9ce25b5223103944803c2668784c484ac7eee75b33aa984e62185728970a8f1` |
| `xcrun devicectl device install app` to iPhone 17 Pro 00008150-000A59811180401C | exit 0 at 00:51:37. databaseSequenceNumber 5976. Bundle container ECBFAD59-331C-4F4D-81B4-C3B0DAA641DC |

Logs are in `docs/verification/logs/resumed4376810-*.log`. Free disk space stayed at 2.1 GiB. No new framework or model copies were made, and nothing unrelated was deleted.

## Limits

- **Install only.** The install receipt does not prove the app launches. The Apple TV card, the message wording and the new copy have not been checked on the phone. The user needs to check them. Expect the Apple TV card to open a tv.apple.com search after confirm.
- No UI automation was tried. Device tools failed twice before because the system Xcode and the managed agent-device version do not match, and there is no new evidence that this changed. No simctl or ssh driving was used.
- No messages were sent and no external actions were taken.
- No unsigned build was run.
- The untracked `app/PocketGlimmer/Support/Info.plist` and `docs/verification/MAC_BUILD_2026-11-04.md` were preserved. Their sha256 hashes match before and after.
