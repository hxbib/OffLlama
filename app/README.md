# app/ Pocket Glimmer for iPhone (SwiftUI, iOS 18+)

The app is built with XcodeGen from `app/project.yml` and depends on the local Swift package
`core/` (PocketCore) plus a llama.cpp xcframework. Build provenance: the Nov 2 successful
unsigned Simulator build is recorded in `613a612` for the unchanged `e0e5b82` source
(`git diff e0e5b82..613a612 -- app core` is empty). The current tree is unbuilt. Build the
current checkout first; that old record is not a device or current-tree result, and reverting
would omit the current skills and media work.

## Shortest path

See `../ios/MAC_DAY_RUNBOOK.md` for the full path, troubleshooting, signing, device trust,
first-launch checks, and the PGPERF recipe. In short, from the repo root on macOS:

```bash
./ios/mac_prep.sh verify-resources
(cd core && swift test)
./ios/mac_prep.sh framework --llama-src ~/src/llama.cpp   # only if app/Frameworks is empty
./ios/mac_prep.sh preflight
./ios/mac_prep.sh prepare --bundle-model --require-model
./ios/mac_prep.sh build-unsigned
open app/PocketGlimmer.xcodeproj
```

`preflight` and `build-unsigned` never sign, install, download a runtime, or change the
active Xcode. The signed install is manual in Xcode.

## Exact dependencies

- Full Xcode with an iOS 18 or newer SDK. Command Line Tools alone do not include
  `xcodebuild`. See Apple's
  [command-line tools](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools)
  and [Xcode command-line tool reference](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference).
- XcodeGen: `brew install xcodegen`, <https://github.com/yonaskolb/XcodeGen>.
- CMake only when building the xcframework: `brew install cmake`.
- Python 3 for strict artifact validation.
- Git LFS for `models/*.gguf`.

`app/project.yml` fixes Swift 5.0, iOS 18.0, `com.habib.pocketglimmer`, and empty
entitlements for a free personal team. Do not edit the generated `.xcodeproj`; edit
`project.yml` and regenerate. `SWIFT_VERSION` must stay one of 4.0, 4.2, 5.0, or 6.0, so
5.0 is intentional.

## llama.xcframework

The app links llama.cpp at commit `ddf48f85c933c1f438212a02eb21e7b001d2d37d`.
Use a clean checkout at that exact pin. From this project root:

```bash
./ios/mac_prep.sh framework --llama-src ~/src/llama.cpp
```

The wrapper stages and validates the build, records source/binary/header provenance, and
installs it only after validation. Existing artifacts are not overwritten. A manual copy
without the provenance marker is incomplete and returns exit 2. Preserve that copy under
an unused backup name before rebuilding with the wrapper. See the runbook for recovery.

The pinned script accepts `ios-device` and `ios-sim`; no arguments builds all seven targets,
including visionOS and tvOS, which a device build does not need. Verified against
[build-xcframework.sh at ddf48f8](https://github.com/ggml-org/llama.cpp/blob/ddf48f8/build-xcframework.sh).
`app/Frameworks/` is gitignored. `xcodegen generate` embeds the framework.

## Model and calibration

The submission model is the distilled shipping GGUF, not the base model:

```
models/SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf
807694080 bytes
sha256 a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2
```

`./ios/mac_prep.sh bundle-model` verifies the size and hash and copies it into
`app/PocketGlimmer/Resources/Models/`. It refuses to overwrite a different file.
`AppModel.findModel()` checks the bundle first, then Documents if no bundled model
exists. Within either location it prefers a filename containing `reflex`.
For an unbundled development build, copy the exact shipping file through
Finder > iPhone > Files > Pocket Glimmer. Startup verifies the selected file's
byte count and SHA-256 before loading it; another `.gguf` cannot use this calibration.

`app/PocketGlimmer/Resources/Models/calibration.json` is required. It was generated from the
shipping GGUF and sets `defaultTau` to 0.90, the shipping operating point. A missing, malformed or incompatible file stops app startup with an error. The base model
does not share this calibration. Check a decision card: its footer must read `τ = 0.90`.

## Build and install

Unsigned compile check, no Simulator runtime and no signing:

```bash
xcodebuild -project app/PocketGlimmer.xcodeproj -scheme PocketGlimmer \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath ios/.build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= build
```

`./ios/mac_prep.sh build-unsigned` regenerates the project, removes its old app build product,
runs this command, and validates the fresh bundle. It no longer accepts `--no-generate`.
`check-app` follows the app's root-then-`Models`/`Skills` lookup and rejects conflicting
resources and symlinked models. The installed Documents folder needs a separate device check.
Exit 2 means incomplete checks or unverified framework provenance, even if compilation passed. A
successful compile is not a device install. For signing, open the project in Xcode, select
your personal team in Signing & Capabilities, enable Developer Mode on the iPhone, and run a
Release build. The runbook covers the prompts and the free-team 7-day expiry.

## Shortcuts automations (the proactive layer)

1. Shortcut **"PG Send Message"** (message bridge): *Receive Text input* -> *Split Text* by
   `|` -> *Send Message* (Message: item 2, Recipients: item 1). Turn off "Show When Run" if
   you want it silent.
2. Personal Automations (Shortcuts > Automation > New), each running **Pocket Glimmer
   Trigger**:
   - Time of Day 8:00 -> Trigger = Time
   - Arrive at a grocery store -> Trigger = Arrive, Place = "Trader Joe's grocery"
   - Email from *anyone* -> Trigger = Email, Sender = Shortcut Input > Sender, Text = Subject
   - Message from *anyone* -> Trigger = Message, Sender = Sender, Text = Content
   - Charger connected -> Trigger = Charger
   Set each to "Run Immediately".

## Layout

- `Engine/LlamaCppEngine.swift` runs llama.cpp with KV-prefix reuse, one forward pass, and
  letter-token logits. Metal offload is on.
- `AppModel.swift` wires PocketCore (Reflex, Assistant, MemoryStore, ProactiveEngine,
  TelemetryLog) to the UI and loads the model and calibration.
- `Actions/SystemActions.swift` owns EventKit reminders and calendars, Contacts, and the
  Shortcuts message bridge.
- `Intents/` owns App Intents for Shortcuts triggers and the share sheet.
- `Views/` owns onboarding, chat, the Reflex cards, memory, and settings.
- `Resources/Skills/builtin.json` is the shipped skills registry.
