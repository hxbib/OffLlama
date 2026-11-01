# app/ — Pocket Glimmer for iPhone (SwiftUI, iOS 18+)

Not compiled on the Linux box (no Xcode). Written against llama.cpp `ddf48f8` C API (2026-10-31) and iOS 18 SDK.

## Build on the Mac (exact commands)

```bash
# 0) tools
xcode-select -p || xcode-select --install
brew install xcodegen cmake

# 1) core logic first: must be green before touching the app
cd pocket-glimmer/core && swift test

# 2) llama.cpp -> llama.xcframework (Metal, iOS + simulator + macOS slices; ~10 min)
git clone https://github.com/ggml-org/llama.cpp ~/src/llama.cpp && git -C ~/src/llama.cpp checkout ddf48f8
cd ~/src/llama.cpp && ./build-xcframework.sh ios-device ios-sim   # device + simulator slices only
mkdir -p ~/path/to/pocket-glimmer/app/Frameworks
cp -R build-apple/llama.xcframework ~/path/to/pocket-glimmer/app/Frameworks/

# 3) model (≈0.8 GB). Distilled reflex-Q4_K_M.gguf when ready, base model until then:
mkdir -p ~/path/to/pocket-glimmer/app/PocketGlimmer/Resources/Models
#   copy Llama-3.2-1B-Instruct-Q4_K_M.gguf there (or later drop it into the app's Documents via Finder > iPhone > Files)
#   optional: training/out/calibration.json -> app/PocketGlimmer/Resources/Models/calibration.json

# 4) project + build
cd ~/path/to/pocket-glimmer/app && xcodegen generate
open PocketGlimmer.xcodeproj            # Signing & Capabilities: pick your Team once
xcodebuild -project PocketGlimmer.xcodeproj -scheme PocketGlimmer \
  -destination 'platform=iOS,name=<Your iPhone 17 Pro>' -allowProvisioningUpdates build
```

If Xcode complains about `import llama`: confirm `app/Frameworks/llama.xcframework` exists and is "Embed & Sign".
The `increased-memory-limit` entitlement is OFF by default (free personal teams cannot provision it; 1B Q4 fits). See ../ios/MAC_DAY_RUNBOOK.md.

## Shortcuts automations (the proactive layer)

1. Shortcut **"PG Send Message"** (message bridge): *Receive Text input* → *Split Text* by `|` → *Send Message* (Message: item 2, Recipients: item 1). Turn off "Show When Run" if you want it silent.
2. Personal Automations (Shortcuts → Automation → New), each running **Pocket Glimmer Trigger**:
   - Time of Day 8:00 → Trigger = Time
   - Arrive at a grocery store → Trigger = Arrive, Place = "Trader Joe's grocery"
   - Email from *anyone* → Trigger = Email, Sender = Shortcut Input › Sender, Text = Subject
   - Message from *anyone* → Trigger = Message, Sender = Sender, Text = Content
   - Charger connected → Trigger = Charger
   Set each to "Run Immediately".

## Layout
- `Engine/LlamaCppEngine.swift` — `LLMEngine` on llama.cpp: KV-prefix reuse, one forward pass, letter-token logits; Metal offload.
- `AppModel.swift` — wires PocketCore (Reflex, Assistant, MemoryStore, ProactiveEngine, TelemetryLog) to the UI.
- `Actions/SystemActions.swift` — EventKit reminders/calendar, Contacts, Shortcuts message bridge.
- `Intents/Intents.swift` — App Intents for Shortcuts triggers + "Ask Pocket Glimmer".
- `Views/` — Onboarding, Chat (+ live Reflex strip), Reflex (Swift Charts telemetry + live feed + CSV export), Memory, Settings.
