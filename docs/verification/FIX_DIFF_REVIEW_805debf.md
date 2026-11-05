# Fix-diff review and signed install: 805debf

Reviewed, built and installed SHA: `805debfe791ec5dee430d5f308144f448db33ed9`. Diff reviewed: `8d477db..805debf`.

## Verdict

No critical or warning findings. The fix is safe to ship.

- `EffectLedger.readiness` now returns not-ready for any contract whose availability is not `.ready`. Every confirm path goes through this check, so does evaluate, and so do plan materialization and the card's `canConfirm`. A saved card from a previous build cannot confirm.
- `performClaimed` checks availability again right before `effects.perform`. That also blocks resuming an attempt that was already claimed.
- `validationHandoff` changes only `.notWired` contracts. It sets id `validation_<id>` and availability `.ready`, and keeps the argument schemas. The six tests still assert that bad input is rejected, so validation was not weakened.
- No Shortcut helper dependency came back. The unavailable text makes no claim that Shortcuts are installed.

Nits, none blocking:

1. An old card with a non-empty stored notice keeps showing that notice until the user taps confirm. `canConfirm` is false either way.
2. The new test covers the confirm path only. It does not cover claimed-resume.
3. The pause reason reuses `.contractVersionStale`.

## Evidence (UTC, 2026-11-05)

| Check | Result |
| --- | --- |
| Core `swift test` (macOS Xcode toolchain) | 396 executed, 1 skipped, 0 failed, 00:28:50 to 00:29:02 |
| Signed Release build (team 2VGYC6S9F3, `ios/.build/SignedDerivedData`) | BUILD SUCCEEDED 00:29:30. Binary mtime 00:29:30, newer than the 00:28:28 checkout |
| Binary strings | "is not available in this build" present. "needs a Shortcut named" absent |
| `codesign --verify --deep --strict` | OK, com.habib.pocketglimmer |
| `bash ios/mac_prep.sh check-app --app ... --require-model` | APP BUNDLE PASSED |
| Model | 807694080 bytes, sha256 a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2 |
| Calibration | sha256 b9ce25b5223103944803c2668784c484ac7eee75b33aa984e62185728970a8f1, tau 0.90 |
| `xcrun devicectl device install app` to 00008150-000A59811180401C | exit 0 at 00:29:58, databaseSequenceNumber 5968 |

Logs are in `docs/verification/logs/review805-*.log`.

## Not run

- Unsigned Release build. Skipped to meet the deadline.
- App launch, UI automation and phone checks. An install does not prove the app launches. UI automation still cannot run because `device_list` fails without `simctl`.
- The untracked `app/PocketGlimmer/Support/Info.plist` and `docs/verification/MAC_BUILD_2026-11-04.md` were preserved. Their sha256 hashes were checked before and after.
