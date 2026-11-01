# Mac day runbook: Pocket Glimmer on iPhone 17 Pro

The iOS app lives in `app/` (XcodeGen spec `app/project.yml`) and depends on the local SwiftPM package `core/` (PocketCore).
None of this has been compiled yet: the Linux box has no Swift toolchain. Expect a few small compile fixes. Fix them in this order: core, then the engine, then the views.

Timebox: about 2.5 h. If the app build is still red at T+2h, record the airplane-mode clip with whatever runs, and log the numbers from step 8.

## 0. Tools (≈10 min)
```bash
xcode-select -p || xcode-select --install   # use an Xcode whose SDK matches the iOS version on the phone
sudo xcodebuild -license accept
xcodebuild -downloadPlatform iOS                 # only if Xcode says the iOS platform is missing
brew install xcodegen cmake
```

## 1. Get the repo onto the Mac
The repo is local-only (no remote, by design: do not create one). Copy it over the LAN or a USB stick:
```bash
# on the box:  cd /workspace && tar czf pg.tgz --exclude='training/local_teacher/out' --exclude='*.gguf' pocket-glimmer
# on the Mac:
mkdir -p ~/dev && cd ~/dev && tar xzf ~/Downloads/pg.tgz && cd pocket-glimmer
git log --oneline | head -3                     # sanity check: same HEAD as the box
export PG=~/dev/pocket-glimmer
```
(Or use `git clone /Volumes/<stick>/pocket-glimmer` if you copied the .git directory.)

## 2. Core first (must pass before you touch the app)
```bash
cd $PG/core && swift build && swift test
```
Fix anything red here first. This is pure Swift plus the vendored SQLite.

## 3. llama.cpp → llama.xcframework, pinned to ddf48f8 (≈10–15 min)
```bash
git clone https://github.com/ggml-org/llama.cpp ~/src/llama.cpp
cd ~/src/llama.cpp && git checkout ddf48f8
./build-xcframework.sh ios-device ios-sim       # outputs build-apple/llama.xcframework (module name "llama")
mkdir -p $PG/app/Frameworks
rm -rf $PG/app/Frameworks/llama.xcframework
cp -R build-apple/llama.xcframework $PG/app/Frameworks/
```
Every C symbol that `LlamaCppEngine.swift` uses was checked against `include/llama.h` at ddf48f8 on the box: model/context load, `llama_get_memory`, `llama_memory_seq_rm`/`clear`, `llama_batch_get_one`, the sampler chain, `llama_vocab_is_eog` and the `llama_tokenize`/`llama_token_to_piece` signatures. They all match.

## 4. Model file (≈0.8 GB)
Option A, bundled (easiest for the clip):
```bash
mkdir -p $PG/app/PocketGlimmer/Resources/Models
cp ~/Downloads/Llama-3.2-1B-Instruct-Q4_K_M.gguf $PG/app/PocketGlimmer/Resources/Models/
# when the distilled model exists, use it instead (findModel() prefers a filename containing "reflex"):
# cp Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf $PG/app/PocketGlimmer/Resources/Models/
# optional: cp $PG/training/out/calibration.json $PG/app/PocketGlimmer/Resources/Models/
```
Option B, no rebuild: after installing, open Finder → iPhone → Files → Pocket Glimmer and drag the .gguf in. `UIFileSharingEnabled` is now set. The app checks Documents first, then the bundle.
Base model download: `huggingface-cli download bartowski/Llama-3.2-1B-Instruct-GGUF Llama-3.2-1B-Instruct-Q4_K_M.gguf --local-dir ~/Downloads` (or whichever mirror you used on the box).

## 5. Generate the project
```bash
cd $PG/app && xcodegen generate && open PocketGlimmer.xcodeproj
```

## 6. Signing with a free Apple ID (personal team)
1. Xcode → Settings → Accounts → **+** → Apple ID and sign in.
2. Select the PocketGlimmer target → Signing & Capabilities → check "Automatically manage signing" → Team: *Your Name (Personal Team)*.
3. If the bundle ID is taken, change `PRODUCT_BUNDLE_IDENTIFIER` in project.yml (e.g. `com.habib.pocketglimmer.dev`), then run `xcodegen generate` again.
4. The entitlements file is intentionally empty: a free team cannot provision `increased-memory-limit`, and the 1B fits without it. Free-team limits: the app expires after 7 days, and you can have 3 apps per device.
5. On the iPhone, turn on Settings → Privacy & Security → **Developer Mode** (it reboots), then connect over USB and tap Trust.
6. After the first install, go to Settings → General → VPN & Device Management → your Apple ID → **Trust**.

## 7. Build and run on the iPhone 17 Pro
In Xcode, pick the phone as the run destination, set the scheme to **Release** (Product → Scheme → Edit Scheme → Run → Build Configuration: Release; Debug is much slower for llama.cpp), then press ⌘R. Or use the CLI:
```bash
xcodebuild -project PocketGlimmer.xcodeproj -scheme PocketGlimmer -configuration Release \
  -destination 'platform=iOS,name=<Habib’s iPhone 17 Pro>' -allowProvisioningUpdates build
```
On first launch, grant Reminders, Calendars and Contacts. The usage strings are in project.yml → Info.plist.
Likely compile issues and their fixes:
- `No such module 'llama'`: the xcframework is not at `app/Frameworks/llama.xcframework`, or it is not set to Embed & Sign. Run `xcodegen generate` again.
- Linker errors about the C++ std lib: `OTHER_LDFLAGS: -lc++` is already set. Also add `-framework Metal -framework Foundation -framework Accelerate` if needed.
- Swift 6 concurrency errors: keep `SWIFT_VERSION` at 5.0 (already set). They should only show up as warnings.

## 8. Measure (for the airplane-mode clip)
1. Turn on airplane mode (Wi-Fi off too). The status pill should show offline, and every answer should carry the "on device" badge.
2. Ask the three demo prompts from docs/DEMO_SCRIPT.md.
3. **tokens/s and TTFT**: filter the Xcode console for `PGPERF`. Each local generation prints `prompt_tokens, prefill_ms, ttft_ms, gen_tokens, decode_tok_s`. Reflex decisions (one forward pass each) show their ms on the decision cards.
4. **RAM**: Xcode → Debug navigator (⌘7) → Memory gauge, peak during a generation. For a cleaner number, use Product → Profile → Allocations / VM Tracker and read the peak Physical Footprint.
5. Note the device temperature: run each prompt 3×, use the median of runs 2–3, and write down the thermal state.
6. Record the numbers in docs/SUBMISSION.md in place of the `[PHONE_*]` placeholders, labeled "measured on iPhone 17 Pro, Release build, airplane mode".
7. Screen recording: Control Center → Screen Recording. Make sure the airplane icon is visible.

## Things only the Mac can confirm
- Whether the whole app compiles at all (it has never been compiled). The C API names were checked statically.
- Metal offload (`n_gpu_layers = 99`) on A19 Pro, and real tokens/s, TTFT and RAM.
- The EventKit full-access prompts on the phone's iOS version, and the Shortcuts "PG Send Message" bridge.
