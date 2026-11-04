# Mac and iPhone runbook: Pocket Glimmer

Written 2026-11-04 on Linux. No Mac was available, so nothing in this file is an Xcode or
device result. It records what is known, the shortest trustworthy path, and the checks that
still need a Mac and an iPhone.

The requested phone target is **iOS 27.0.1**. The project's iOS 18.0 deployment target is
a minimum build setting, not evidence that either version has passed these checks. Record
the actual device and OS build before testing; do not update the phone merely to match a
newer SDK.

## Known state

- Repository: <https://github.com/hxbib/pocket-glimmer>, branch `master`. It is not a
  local-only repo. `git pull --ff-only` gets the current code; `git lfs pull` gets the model.
- Build provenance: the Nov 2 successful unsigned Simulator build is recorded in `613a612`
  for the unchanged `e0e5b82` source (`git diff e0e5b82..613a612 -- app core` is empty). The
  current tree is unbuilt. That was a Simulator build, not a device build, and it does not
  cover today's app changes. Build the current checkout first; do not read the old source
  reference as a code error and do not revert as a shortcut.
- Core baseline at `581fa3a`: 94 tests executed, 1 skipped, 0 failures. The Nov 4 17:39 UTC integrated run
  executed 136 tests with 1 skipped and 0 failures after cloud-text, memory-alias and
  training-export repairs. The message, Apple TV and complete-document screening regressions
  pass. Independent review of the new integration is still pending. A red core is not ready; do not fall back to an older tree.
- Shipping model: `models/SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf`,
  807694080 bytes, sha256
  `a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2`.
- Calibration: `app/PocketGlimmer/Resources/Models/calibration.json` is required, not
  optional. Its `defaultTau` is 0.90, the shipping operating point. It was generated from
  the shipping GGUF. The base Llama model is not compatible with this calibration.
- XcodeGen spec: `app/project.yml` uses Swift 5.0, iOS 18.0, and empty entitlements so a free
  personal team can provision it. The bundle identifier is `com.habib.pocketglimmer`.
- llama.cpp pin: `ddf48f85c933c1f438212a02eb21e7b001d2d37d`. `LlamaCppEngine.swift` uses the model/context, memory, batch,
  sampler, vocabulary, and token APIs present in the pinned header. That is a header check,
  not a compile result.

## Critical path

Run these from the repo root, one at a time. Each command exits non-zero on a real failure.

```bash
git clone https://github.com/hxbib/pocket-glimmer.git
cd pocket-glimmer
git switch master
git pull --ff-only
git lfs install
git lfs pull

./ios/mac_prep.sh verify-resources
(cd core && swift test)

# Only if app/Frameworks/llama.xcframework is absent:
./ios/mac_prep.sh framework --llama-src ~/src/llama.cpp

./ios/mac_prep.sh preflight
./ios/mac_prep.sh prepare --bundle-model --require-model
./ios/mac_prep.sh build-unsigned

open app/PocketGlimmer.xcodeproj
```

`build-unsigned` proves that the current source compiles and links for a generic iOS device
and that the bundle contains the calibration, skills, framework, and optional model. It does
not sign, install, or launch. The signed install is section 8 and is deliberately manual.

If you already have a checkout, replace the clone block with `cd <checkout>`, `git switch
master`, `git pull --ff-only`, and `git lfs pull`. Do not copy a tree over the LAN and do not
make a new remote.

## 1. Prerequisites

The script never installs these. Install them yourself.

- Full Xcode, not only the Command Line Tools package. `xcodebuild` ships with Xcode.
  Apple documents both options in
  [Installing the command-line tools](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools)
  and lists the Xcode-only tools in the
  [Xcode command-line tool reference](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference).
- An Xcode installation with an iOS SDK and device support for the connected phone.
  Keep the iOS 18.0 deployment target while using an SDK that supports the needed APIs.
  Check Apple's [SDK and system requirements](https://developer.apple.com/xcode/system-requirements)
  against the Mac's OS and phone's OS before choosing an Xcode version. If Xcode reports
  that the iOS platform is missing, install it in
  Xcode > Settings > Components. `xcodebuild -downloadPlatform iOS` is a large download and
  is your choice, not something this repo does automatically.
- XcodeGen. XcodeGen reads `app/project.yml`.
  `brew install xcodegen` is the usual install. Project: <https://github.com/yonaskolb/XcodeGen>.
- CMake only when `app/Frameworks/llama.xcframework` must be built. `brew install cmake`.
- Python 3 for strict artifact validation on macOS and Linux.
- Git LFS for `models/*.gguf`. `git lfs install` once per machine or checkout.

Check the active developer directory and license yourself:

```bash
xcode-select -p
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

## 2. Quick prerequisite check

```bash
./ios/mac_prep.sh preflight
```

It reports, without changing anything:

- host and Xcode, including `xcodebuild -version`, the active developer directory, the
  `iphoneos` SDK path, and the SDK version
- XcodeGen, CMake when a framework build is needed, `shasum`, and git
- `app/Frameworks/llama.xcframework` and its device slice
- the shipping model size and sha256, and any model already bundled in the app
- `calibration.json` (`defaultTau` 0.90 and the required prior keys), `builtin.json`, and
  the empty entitlements

A missing Xcode, XcodeGen, or framework is a hard failure with the exact resolution. The
script never runs `brew`, `xcode-select`, `xcodebuild -downloadPlatform`, `codesign`, or an
install.

`./ios/mac_prep.sh verify-resources` is the portable subset. It works on Linux and checks the
model, calibration, skills, and entitlements without claiming that an iOS build is possible.
`./ios/test_mac_prep.sh` runs fixture-based success and failure checks for the script itself.

## 3. Core first

```bash
cd core
swift test
cd ..
```

The core is the gate. It is pure Swift plus vendored SQLite and does not need the iOS SDK.
If it is red, stop and fix the core before touching the app. The dated baseline is in "Known
state"; do not hardcode a test count into a release claim, because the suite changes.

## 4. Build or verify the pinned llama.xcframework

Run this from the project root with a clean llama.cpp checkout at the exact full pin:

```bash
git -C ~/src/llama.cpp rev-parse HEAD
git -C ~/src/llama.cpp status --porcelain --untracked-files=normal
./ios/mac_prep.sh framework --llama-src ~/src/llama.cpp
```

The commit must equal `ddf48f85c933c1f438212a02eb21e7b001d2d37d`, and the status must be empty.
Ignored build outputs do not block a retry. The wrapper builds into the upstream output
folder, copies into a temporary staging directory, validates the device binary and headers,
and records their hashes with the source pin before installing the framework.

An existing framework is checked without overwrite. A manually copied framework without
`.pocketglimmer-provenance.json` returns exit 2 even when its structure is usable. Preserve it
under an unused backup name, then rerun the wrapper to build a provenance-recorded copy.
Do not create a marker by hand for an artifact whose source is unknown. A failed build or
staged validation leaves an existing framework untouched and permits a retry.

The argument behavior was verified against the pinned script, not against current llama.cpp
documentation:
[build-xcframework.sh at ddf48f8](https://github.com/ggml-org/llama.cpp/blob/ddf48f8/build-xcframework.sh).

- `./build-xcframework.sh ios-device` builds the device slice. This is all a device build
  needs.
- `./build-xcframework.sh ios-device ios-sim` adds a Simulator slice. Build the Simulator
  slice only if you also intend to compile for a Simulator.
- `./build-xcframework.sh` with no arguments builds all seven targets, including macOS,
  visionOS, and tvOS. It is not the shortest path and can fail when those SDKs are absent.

The pinned script writes `build-apple/llama.xcframework` under the llama.cpp checkout and
rebuilds its own `build-*` directories. Run it only from a checkout you are willing to have
rebuilt. The app consumes the copied framework at
`app/Frameworks/llama.xcframework`; keep it out of git, as the repo already does.

## 5. Model and calibrated resources

Preferred path, bundle the verified shipping model so the first install is usable without a
second file copy:

```bash
./ios/mac_prep.sh bundle-model
```

The script verifies the exact byte count and sha256, copies the model under its canonical
name into `app/PocketGlimmer/Resources/Models/`, and refuses to overwrite a different file.
A failed verification leaves no destination file behind.

Manual verification on macOS uses portable `shasum`, not Linux `stat -c`:

```bash
shasum -a 256 models/SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf
# a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2
wc -c < models/SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf
# 807694080
```

If the file is a few hundred bytes, it is a Git LFS pointer. Run `git lfs install` and
`git lfs pull`.

Unbundled alternative: build and install without the model, then open Finder > iPhone >
Files > Pocket Glimmer and copy the `.gguf` into the app's Documents folder. `AppModel`
checks Documents first and prefers a filename containing `reflex`. A launch with no model
shows "No model file"; it is not a usable demo.

Calibration is not optional and is not interchangeable with the base model:

- `calibration.json` must be in the built app. The source file is
  `app/PocketGlimmer/Resources/Models/calibration.json`.
- `defaultTau` must be the number 0.90 and `promptStyle` must be `fewShot`. The validator
  checks all 31 prior sets, their lengths, finite values, and permitted overrides. Strings,
  duplicate JSON keys and incompatible values fail. The exact calibration SHA-256 is
  `b9ce25b5223103944803c2668784c484ac7eee75b33aa984e62185728970a8f1`.
- The priors were measured on the shipping GGUF. A base model with these priors is not the
  shipping operating point.
- In the app, open any decision card. Its footer must read `τ = 0.90`. The current app stops startup if calibration is missing or incompatible. Seeing `τ =
  0.80` indicates an older build or a different configuration; stop and rebuild the reviewed source.
- `builtin.json` must also be in the bundle. It is the skills registry; the app has Swift
  built-ins as a fallback, but the shipped skill set is the JSON file.

`./ios/mac_prep.sh check-app --app <path>` validates these resources after a build without
requiring the simulator. It resolves calibration at the bundle root, then `Models/`, and
skills at the root, then `Skills/`, as the app does. Conflicting copies and nested-only
resources fail. Model files must be regular files at the root or in `Models/`; symlinked
models are rejected. The installed app's `Documents/` folder is not visible to this check.
Embedded frameworks may legitimately omit headers and module maps; source xcframeworks
must contain them.

## 6. Generate the Xcode project

```bash
cd app
xcodegen generate
cd ..
```

`prepare` runs this for you. XcodeGen writes `app/PocketGlimmer.xcodeproj`, which the repo
ignores. Edit `app/project.yml`, never the generated project, when a source or setting
changes. The current spec keeps `SWIFT_VERSION` at 5.0 because Xcode accepts 4.0, 4.2, 5.0,
or 6.0 and rejects values such as 5.10. Keep the deployment target at iOS 18.0 and keep the
entitlements empty for a free personal team.

If `com.habib.pocketglimmer` is already taken by another team, change
`PRODUCT_BUNDLE_IDENTIFIER` in `app/project.yml` and run `xcodegen generate` again. Do not
edit the generated project.

## 7. Unsigned generic iOS Release compile

```bash
./ios/mac_prep.sh build-unsigned
```

The wrapper always regenerates the project and removes only its prior `PocketGlimmer.app`
build product before building. `--no-generate` is no longer accepted. A successful command
that leaves no fresh app fails validation. The build invocation is:

```bash
xcodebuild -project app/PocketGlimmer.xcodeproj -scheme PocketGlimmer \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath ios/.build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= build
```

It uses `generic/platform=iOS`, so it needs the device SDK but not a Simulator runtime. The
output is `ios/.build/DerivedData/Build/Products/Release-iphoneos/PocketGlimmer.app`.

What success means: the current source compiled and linked for iOS, and the built `.app`
contains `calibration.json` with tau 0.90, `builtin.json`, the embedded `llama.framework`,
`UIFileSharingEnabled`, and a verified model if one was bundled. Logs are under
`ios/.build/logs/`.

Exit 0 means the required checks passed. Exit 1 means a required check failed. Exit 2 means
a required artifact/check was skipped or the source framework lacks verified provenance.
A compile with an unverified framework can return exit 2; retain the log but do not call it
release-ready. The wrapper's 73 Linux fixture checks include mocked Xcode and native tools.
They verify control flow, not a real iOS binary or SDK build.

What success does not mean: it is not signed, not installed, not launched, and does not prove
Metal offload, permissions, Shortcuts, or phone performance. Section 8 is the first signed
step.

Common failures:

- `No such module 'llama'`: `app/Frameworks/llama.xcframework` is missing or lacks a device
  slice. Re-run `./ios/mac_prep.sh framework` and `xcodegen generate`.
- Linker errors around C++: the framework module map links `c++`, `Accelerate`, `Metal`, and
  `Foundation`, and `project.yml` already sets `-lc++`. Check that the whole xcframework was
  copied, not a single slice by hand.
- Swift 6 concurrency diagnostics: keep the project in Swift 5 mode. Fix the source warning
  if it is real; do not switch the language mode to hide it.
- `Unable to find a destination` or a missing iOS platform: install the iOS platform support
  in Xcode > Settings > Components. The generic unsigned build does not need a connected phone.
- A missing destination for a specific device ID: reconnect that phone, unlock it and verify trust.

## 8. Signed install on the iPhone

Signing and device trust are manual because they use your Apple ID, your team, and your
device. The script never signs, registers a device, or opens Xcode.

1. Xcode > Settings > Accounts > `+` > Apple ID.
2. Open `app/PocketGlimmer.xcodeproj`, select the `PocketGlimmer` target, open Signing &
   Capabilities, enable Automatically manage signing, and choose your personal team.
3. Connect the iPhone by cable, unlock it, and tap Trust on the computer prompt. Apple's
   [Device Hub guide](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub)
   covers pairing and trust.
4. On the iPhone, enable Settings > Privacy & Security > Developer Mode and restart when
   asked. Apple documents the exact prompt in
   [Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
5. Select the iPhone as the run destination. Edit Scheme > Run > Build Configuration >
   Release. Debug is much slower for llama.cpp.
6. Press Run. If the app is refused on first open, trust the developer in Settings > General
   > VPN & Device Management. Apple documents the trust step in
   [Install custom enterprise apps](https://support.apple.com/en-us/118254), which covers
   enterprise distribution. For a development-signed build, follow the exact Xcode and
   device prompts rather than assuming enterprise instructions apply.
7. Grant Reminders, Calendars, Contacts, and notifications when the app asks. Microphone,
   camera, and Photos are requested only when those features are used.

The free personal team has limits: the app expires after 7 days, and there is a cap on apps
per device. Reinstall before the expiry if the demo is later. The entitlements file is
intentionally empty. Do not add `com.apple.developer.kernel.increased-memory-limit` to work
around a free-team signing error. Verify the model's actual memory use on this phone.

Command-line build after the team is selected in Xcode (optional):

```bash
xcodebuild -project app/PocketGlimmer.xcodeproj -scheme PocketGlimmer \
  -configuration Release -destination 'platform=iOS,id=<device-udid>' \
  -allowProvisioningUpdates build
xcrun devicectl device install app --device <device-udid> <path-to>/PocketGlimmer.app
```

Apple's [Running your app on simulated or physical devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)
explains automatic signing and device registration. If Xcode asks you to register the device,
accept it there. The repo does not store a team identifier or a provisioning profile.

## 9. First-launch verification

Do this before recording or filling any phone number into the submission.

1. The onboarding completes and the app shows the Assistant tab. Permission prompts appear
   for Reminders, Calendars, Contacts, and notifications.
2. Open Settings in the app. "On-device model" shows the model name, not "No model file".
3. Send a request that produces a decision card. Expand the card. The footer must read
   `τ = 0.90`. If it reads `τ = 0.80`, stop; this is not the reviewed shipping configuration.
4. If the model was not bundled, copy it through Finder > iPhone > Files > Pocket Glimmer,
   then relaunch. Confirm the model name again.
5. Turn on Airplane Mode, turn Wi-Fi off, and confirm the status pill reports offline. Ask a
   local request such as "Remind me to call Mom at 7." Record the actual route and confidence.
   If the app proposes a reminder, verify its title and time in Reminders. If it asks for
   clarification, record that outcome; a clarification does not prove the reminder flow.
6. Run one skills action that does not need a third-party app, such as a battery or storage
   question. The registry comes from `builtin.json`; a missing file falls back to the Swift
   built-ins and should be visible in the built bundle check.
7. Confirm the app still answers with no API key. The cloud path is optional and only runs
   when the user configures it.

## 10. PGPERF and the offline demo

Use airplane mode with Wi-Fi off. The status pill and the absence of network traffic are part
of the demo evidence.

1. Record one cold launch and five consecutive warm runs of the same local-answer prompt, for example "Write a two-line thank-you text
   to my roommate".
2. In Xcode, filter the console for `PGPERF`. Each local generation prints:
   `PGPERF prompt_tokens=... prefill_ms=... ttft_ms=... gen_tokens=... decode_tok_s=...`.
3. Report the cold run separately. For the five warm runs, retain every sample and report the median and range
   for `ttft_ms` and `decode_tok_s`. Record device/iOS, build SHA, model hash, settings, token counts and thermal state.
   Do not discard slow runs or combine cold and warm measurements. Also retain complete request wall time:
   TTFT measures generation only, not the preceding routing, retrieval and other decisions.
4. For RAM, use the Xcode Debug navigator (⌘7) > Memory peak during a generation. For a
   cleaner number, use Product > Profile > Allocations or VM Tracker and read the peak
   Physical Footprint.
5. A Reflex decision card prints one forward pass in milliseconds. Do not quote that as
   tokens per second.
6. Fill `[PHONE_TOK_S]`, `[PHONE_TTFT_MS]`, and `[PHONE_RAM_GB]` only from these measurements,
   labeled with the actual device, OS, Release build, and airplane-mode setting. If a number was not
   measured, leave the placeholder out of the claim.

The demo beats and the permission seeding are in `docs/DEMO_SCRIPT.md`. Rehearse every
offline shot on the real phone and keep only the shots that clear tau. Messages always
confirm by rule, even when the confidence is high.

## 11. Phone acceptance and known limitations

Use [DEVICE_ACCEPTANCE.md](DEVICE_ACCEPTANCE.md) to retain outcomes, failure recovery, and
evidence for the exact installed build. Every row starts untested. An app/Shortcut handoff
must not be counted as completion of the action inside that app.

These cannot be settled on Linux or in a Simulator:

- Metal offload (`n_gpu_layers = 99`) and the real decode speed, TTFT, and peak RAM on the
  A-series GPU.
- Thermal behavior after repeated generations.
- EventKit permission variants and whether Reminders and Calendars actions land correctly.
- Contacts resolution with duplicate names, and the "Which Sam?" confirmation path.
- Messages and Mail compose sheets, and the Shortcuts bridges.
- Files sharing, the Documents model path, and a relaunch with the copied model.
- Notification permission and the proactive Shortcut triggers.
- Free-team signing, device trust, Developer Mode, and the 7-day expiry.

Known limitations at this baseline:

- The current tree is unbuilt. The next Mac run is the first compile of the current checkout,
  including the skills and media work. The pinned llama header matches the engine's symbols,
  but that is not a compile. Do not revert to `e0e5b82` and then present the old tree as the
  current skills/media build.
- The repo is private until submission. A private repo is release-incomplete, not a core
  build failure. `scripts/verify_submission.sh` reports it separately.
- The app is calibrated for tau 0.90. Lowering tau or using the base model changes the
  shipping configuration and must not be presented as the shipped operating point.
- A free-team install expires after 7 days.

## 12. Troubleshooting

| Symptom | Check | Resolution |
|---|---|---|
| `xcodebuild: command not found` | `xcode-select -p` | Install full Xcode, then `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| `No such module 'llama'` | Device binary, headers and module map in `app/Frameworks/llama.xcframework` | Run `./ios/mac_prep.sh framework --llama-src ~/src/llama.cpp`, then `xcodegen generate` |
| Framework has no usable provenance | `ios/mac_prep.sh framework` returns 2 | Preserve the old framework under an unused backup name and rebuild with the wrapper from the clean full pin |
| Framework has only a Simulator slice | `ios/mac_prep.sh framework` | Rebuild with `./build-xcframework.sh ios-device` |
| `xcodegen: command not found` | `command -v xcodegen` | `brew install xcodegen` |
| Model is 132 bytes | `wc -c < models/...gguf` | `git lfs install && git lfs pull` |
| Model hash mismatch | `shasum -a 256 <file>` | Use the shipping file from LFS or the release asset; never edit the calibration to match a different model |
| App says "No model file" | Settings tab, Files app | Bundle the model or copy it into Documents through Finder |
| Decision card says `τ = 0.80` | Built app resources | Rebuild with `calibration.json` in Copy Bundle Resources; run `check-app` |
| Device build asks for a team | Signing & Capabilities | Select your personal team; do not commit a team id |
| App is untrusted on first open | Settings > General > VPN & Device Management | Trust the developer, then open again |
| App expired | Free-team 7-day limit | Reinstall from Xcode |
| Visibility check says PRIVATE | `gh repo view --json visibility` | Make the repo public before submission; this is release-incomplete, not a compile failure |

## References

Apple primary documentation:

- [Installing the command-line tools](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools)
- [Xcode command-line tool reference](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference)
- [Running your app on simulated or physical devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)
- [Managing your simulated and physical devices in Device Hub](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub)
- [Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
- [Distributing your app to registered devices](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)
- [Install custom enterprise apps on iOS, iPadOS, and visionOS](https://support.apple.com/en-us/118254), for the trust flow

Project references:

- [llama.cpp build-xcframework.sh at ddf48f8](https://github.com/ggml-org/llama.cpp/blob/ddf48f8/build-xcframework.sh)
- [llama.cpp commit ddf48f8](https://github.com/ggml-org/llama.cpp/commit/ddf48f8)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- `app/README.md` for the app layout and the model contract
- `ios/mac_prep.sh --help` for the script commands
