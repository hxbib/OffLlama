# Pocket Glimmer — iOS 27.0.1 capability delta (independent second investigation)

- **Investigator:** Muse Code, provider `muse`, model `muse-wonder-1.0`, reasoning effort `max` (user-assigned; not substituted, not delegated).
- **Date / retrieval date:** 2026-11-04. All Apple availability statements below were retrieved 2026-11-04 from Apple's documentation JSON mirror (`https://developer.apple.com/tutorials/data/documentation/<path>.json`, the data behind the canonical `https://developer.apple.com/documentation/<path>` pages). Canonical URLs are cited; the HTML pages themselves return a JS shell to non-browser fetchers, so the JSON mirror is the inspected body.
- **Baseline:** commit `009430f` (`docs: preserve reviewed action recovery implementation contract`). Grok reports originally examined `d782b81`; the reviewed contract is `7b8d014`. Product-source diff `d782b81..009430f` is comment/copy only plus tests and docs (see §2.4). All `git show 009430f:<path>` citations below are that baseline.
- **Method, in order:** (1) independent inspection of baseline source and entitlements/project, (2) independent official-documentation sweep, (3) only then full reads of `docs/research/IOS27_CAPABILITY_MAP.md` (352 lines), `docs/research/WORKFLOW_DELIVERY_PLAN.md` (96), `docs/research/EFFECT_RECOVERY_CONTRACT.md` (968), `docs/research/IOS27_END_TO_END_JOURNEYS.md` (428), `docs/research/LEARNED_WORKFLOWS.md` (527). Findings in §3–§5 were formed before step (3); §6 classifies each against Grok as **new**, **correction**, **already-covered**, or **unresolved**.
- **Hard limits observed:** no product source edited, no paid API called, no credentials read, no τ/priors/prompts/evaluation artifacts changed, no push/PR, no device interaction. **No iPhone, Xcode, or iOS 27.0.1 build exists in this environment. Nothing in this report is a device result.** Linux Swift tests were not used as iPhone evidence and were not re-run for this report; where Grok cites the 108-test CPU run, that remains Grok's cited artifact, not re-verified here.
- **Scope fence:** target is **iOS 27.0.1** (iOS 27.0 feature base, 2026-09-14, plus 27.0.1 bug-fix, 2026-09-28). Anything introduced in 27.2, or beta in 27.3, is out. Later previews do not count.

---

## 1. Executive answer

Grok's central verdict is correct and is **not** overturned: on iOS 27.0.1 Pocket Glimmer is an honest preparer/record-keeper, not a GUI agent. It cannot read or send inside Instagram/X/WhatsApp/Mail, cannot prove playback/ride/delivery, and cannot invoke another app's App Intent. The durable-journal + EventKit read-back + Shortcut x-callback direction in `WORKFLOW_DELIVERY_PLAN.md` / `EFFECT_RECOVERY_CONTRACT.md` remains the right first work.

Grok nevertheless **missed or mis-described a material set of finishable, verifiable capabilities** that need no Shortcut, no GUI automation, and no new model:

1. **Flashlight is natively controllable and observable today** (`AVCaptureDevice` torch, iOS 6+). Grok lumps it with Focus/Low-Power as Shortcut-only. That is wrong for flashlight and is the cheapest true completion in the whole map.
2. **The Foundation Models framework (iOS 26.0) and its Private Cloud Compute variant (iOS 27.0) are absent from all three Grok reports.** On Apple-Intelligence iPhones this is a free on-device ~3B reasoner plus a PCC reasoner, both addressable from the app on 27.0.1 — distinct from the correctly-excluded Siri AI ToolIntent preview (27.3 beta). It does not replace the frozen Reflex; it is a gated enhancement for summarise/translate/draft where the 1B currently truncates or escalates to Meta.
3. **`SpeechAnalyzer` / `SpeechTranscriber` (iOS 26.0) on-device transcription is unnamed by Grok.** Journeys notes "no on-device speech recognizer" as a gap but never names the shipping remedy. It directly repairs the voice privacy/accessibility journeys (J15/J16) without sending audio to Meta.
4. **AlarmKit (iOS 26.0) is correctly discovered by Journeys/Contract/Plan but dropped from the Capability Map's ranked 15**, which instead ranks an inferior in-app `UNUserNotification` timer (#8). The ranking, and the recovery depth (system-owned alarm list survives SQLite loss), are the delta — not the discovery.
5. **App Intents beyond `supportedModes` housekeeping:** `LongRunningIntent` (27.0, in scope), `CancellableIntent` (26.4), `UndoableIntent` (26.0), `SnippetIntent` (26.0), `IndexedEntity` (18.0), Controls (18.0), `LiveActivityIntent` (17.0). Grok ranks the `openAppWhenRun`→`supportedModes` migration #15 as housekeeping and stops. `LongRunningIntent` is the documented answer to Grok's own "intent must return promptly / 808 MB load may be killed" concern.
6. **EventKit completion surface beyond create/find** (complete, edit/move, delete-by-id already in Contract, recurrence, reminder lists, day-bounded reads) and **document completion via Vision OCR for scanned PDFs + `.docx` text extraction**. Grok names the gaps ("Word unsupported", "scanned PDF no text layer", "`timing` never runs") without the concrete public-API closures that already exist in frameworks the app links (Vision is already used for Glimpse OCR).
7. **One outright citation error:** the Capability Map's "entitlement-gated UPI callback … reports transmission to the carrier" misreads `setUPIVerificationCodeSendCompletion(_:)` — a Unified Payments Interface (India) verification-code API (iOS 17.0). There is **no** public delivery-receipt API for ordinary iMessage/SMS. Grok's contract conclusion (delivery unconfirmed) is right; the cited escape hatch does not exist.

None of items 1–6 changes Slice 1 of the active plan (privacy repair → durable attempt journal → EventKit contract). Items 1, 3, 4, 6 are **near-term adapters behind the same `EffectSession`/`PhoneEffects` contract**; item 2 and the PCC half of item 2 are **future, device-gated work**; item 5 splits (Controls/Snippets future, `LongRunningIntent` design input now, migration housekeeping whenever intents are touched). §7 gives the per-finding plan impact.

---

## 2. Independent findings — before reading Grok

### 2.1 What the baseline app actually is (source evidence)

Files read at `009430f`: `core/Sources/PocketCore/{Skills,Assistant,ActionPlanner}.swift`, `core/Sources/PocketCore/{Decision,Proactive}.swift` (routing context), `app/PocketGlimmer/Actions/{SystemActions,SkillRunner}.swift`, `app/PocketGlimmer/Intents/{Intents,SkillIntents}.swift`, `app/PocketGlimmer/{AppModel,PocketGlimmerApp}.swift`, `app/PocketGlimmer/Capture/{CameraGlimpse,VoiceCapture}.swift`, `app/PocketGlimmer/Support/PocketGlimmer.entitlements`, `app/project.yml`, `app/PocketGlimmer/Resources/Skills/builtin.json`, `docs/SKILLS.md`.

**Architecture in one paragraph.** `Assistant.handle` (`Assistant.swift`) runs `rememberOrNot` → `route` → optional `skillOverride`/`toolPath`. Open-world actions go through `ActionPlanner.planSkillCore`: BM25+trigram retrieval (`SkillRegistry.retrieve`, k≤7, score>0.6) → one dynamic `skillPick` letter decision (τ=0.90) → regex args (`SkillArgs.extract`) → trained `contactPick` for `.contact` args → `confirmBeforeAct` + hard `skill.confirm` → `PlannedAction(tool:"skill:<id>")` → `Assistant.execute` → either `SystemActions.perform` (7 executor tools) or `IOSSkillRunner.run`. `AppModel` holds chat/pending in memory; SQLite holds facts/telemetry only. There is no journal, no stored EventKit identifier, no callback URL scheme, no background mode.

**Entitlements/deployment (hard constraints).** `PocketGlimmer.entitlements` is an empty `<dict/>`. `app/project.yml`: `deploymentTarget iOS 18.0`, iPhone-only, `MessageUI.framework` linked, usage strings only for Reminders/Calendars/Microphone/Camera/PhotoLibrary/Contacts, `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` on. Consequence: every iOS 26/27 API below needs an `if #available` guard (target stays 18.0); AlarmKit additionally needs `NSAlarmKitUsageDescription`; WeatherKit/MusicKit/Focus-status each need a capability/entitlement + usage string the tree does not have. "Available on 27.0.1" ≠ "callable from this binary today".

### 2.2 The 36 built-in skills — independent completion map

Source of truth: `BuiltinSkills.all` (`Skills.swift`) ≡ `builtin.json` (36 ids, verified by count). `ActionPlanner.executorTools = [send_message, send_email, create_reminder, create_event, find_event, lookup_contact, search_memory]`; `textSourceHandlers = [analyze_document]`. Classification below is by **observed postcondition in this code**, not by skill prose:

| Class | Skills | Observed postcondition in baseline code |
|---|---|---|
| **Verified local effect** (app reads back / system delegate reports) | `reminder_create`, `calendar_create` | `EKEventStore.save` returns (`SystemActions.perform`). **But:** identifier discarded, no read-back, event start defaults to `Date()+3600` when `NSDataDetector` fails. Effect happened; recovery identity did not survive. |
| **Verified local read** | `device_status`, `html_viz`, `memory_recall`, `calendar_find` | `UIDevice.batteryLevel`/`volumeAvailableCapacity…` (`IOSSkillRunner.deviceStatus`); `HTMLViz.render` bar count + presented sheet; `MemoryStore.retrieve`; `EKEventStore.events(matching:)` next-30-days. `device_status` also reads `isLowPowerModeEnabled`. |
| **System-sheet observed** (user act visible, downstream invisible) | `imessage_send`, `email_compose` | `MFMessageComposeViewController`/`MFMailComposeViewController` delegate: `.sent`/`.cancelled`/`.failed` (`.saved` for mail) via `ComposeSheets`. At `009430f` copy is already honest: "Messages accepted … delivery not confirmed", "queued in Mail". Fallbacks (`sms:&body=`, `mailto:`, `PG Send Message` Shortcut) degrade to open-only. Only first phone/email used (`prefix(1)`). |
| **Shared-text reasoning** (finishes only if user shared first) | `email_digest`, `analyze_document`, `summarize_text`, `translate` | `SharedInbox.take/peek` (15-min, single-slot, process-memory) → `Assistant.reason` (1B ≤2500 chars; else scrubbed Meta escalation if online+`sensitivity==ok`). `analyze_document` falls back to `DocumentPicker.pickText` (PDF via `PDFDocument.string`, `.txt`/`.md` UTF-8 only). `email_digest` parses `n` then ignores it. |
| **Memory-only** | `instagram_autoreply` | Upserts `autoreply_rule` fact + honest refusal text (`IOSSkillRunner.runNative`). No message sent, by design. |
| **Handoff only** (`UIApplication.open` Bool is the ceiling) | `instagram_dm`, `x_dm`, `whatsapp_send`, `call`, `facetime`, `maps_directions`, `uber_ride`, `web_search`, `open_url`, `music_play`, `spotify_play`, `photos_open`, `run_shortcut`, `create_shortcut` | Clipboard pre-copy for IG/X only. `music_play` template is bare `music://` — `{query}` ignored. `whatsapp_send` template carries `text` only, no recipient. `call`/`facetime` substitute `{phone}` from first Contacts number. |
| **Shortcut handoff only** (existence/result unobservable) | `alarm_create`, `timer_start`, `appletv_play`, `open_app`, `notes_create`, `flashlight_toggle`, `focus_toggle`, `low_power_toggle`, `weather` | `SkillTemplate.shortcutURL` → `shortcuts://run-shortcut`. `appletv_play` alone has a fallback (`tv.apple.com/search`) when Shortcuts itself won't open. "Turn on" vs "turn off" are the same toggle handoff for flashlight/Focus/Low-Power. |

Intents surface (`Intents.swift`, `SkillIntents.swift`): exactly 4 `AppShortcut`s (`AskPocketGlimmerIntent`, `ProactiveTriggerIntent` with `openAppWhenRun=false`, `HandleTextIntent`, `RunSkillIntent` over a 7-case `QuickSkill` enum). No `AppEntity`, no Spotlight indexing, no `UndoableIntent`, no snippets, no controls/widgets, no Live Activities. `ProactiveTriggerIntent.perform` boots the full model (`AppModel.shared.handleTrigger` → `boot()` → 808 MB GGUF load) — the background-lifetime risk is structural, not hypothetical.

Capture: voice is **cloud-only** (`VoiceCapture.swift`: AVAudioRecorder 16 kHz WAV → Muse Voice Transcribe → `AppModel.send`; offline/local-only refuses). Camera glimpse is cloud-only after on-device Vision OCR for the sensitivity check (`CameraGlimpse.swift`, `VNRecognizeTextRequest` fast level). The app already links Vision and already does on-device OCR — a fact §3.6 uses.

### 2.3 Independent API sweep (official docs, retrieved 2026-11-04)

Availability is `introducedAt` for iOS from Apple's docs JSON. "In 27.0.1" means introduced ≤27.0 and not beta-gated above 27.0.1.

| Surface | Availability | Entitlement / permission | Relevance to this app |
|---|---|---|---|
| [AlarmKit](https://developer.apple.com/documentation/alarmkit) (`AlarmManager`, `Alarm`, `AlarmAttributes`) | iOS **26.0** | `AlarmManager.requestAuthorization()` + `NSAlarmKitUsageDescription` ([key doc](https://developer.apple.com/documentation/bundleresources/information-property-list/nsalarmkitusagedescription)). **No `com.apple.developer.alarmkit` entitlement exists** — do not invent one. | Replaces `alarm_create`/`timer_start` Shortcut handoffs with app-owned alarms/countdowns: schedule/cancel/list (`AlarmManager.alarms`), snooze, Live-Activity/Dynamic-Island presentation. System-owned list is the recovery source if SQLite is lost. Still not a Clock-app alarm. |
| [Foundation Models](https://developer.apple.com/documentation/foundationmodels) (`SystemLanguageModel.default`, `LanguageModelSession`, `@Generable`, `Tool`) | iOS **26.0** | No entitlement/key; gated by `SystemLanguageModel.default.availability` (`.available` / `.unavailable(.deviceNotEligible/.modelNotReady/…)`) — Apple-Intelligence devices only (iPhone 15 Pro+ class), region/language limits. | Free offline 3B-class reasoner for summarise/translate/extract/draft on eligible devices. Must be progressive enhancement; never a dependency (most iPhone 11–14 on 27.0.1 are ineligible). |
| [`PrivateCloudComputeLanguageModel`](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel) | iOS **27.0** → **in 27.0.1** | Same availability gate; runs on Private Cloud Compute. | Larger-context Apple reasoning without a Meta key, on eligible devices. In-app only — it does **not** make Siri call this app. |
| [`SpeechAnalyzer` / `SpeechTranscriber`](https://developer.apple.com/documentation/speech/speechanalyzer) | iOS **26.0** | Microphone permission (already declared); locale assets via `AssetInventory` download; `SpeechTranscriber.supportedLocales` async. | On-device transcription replacing/augmenting Muse Voice Transcribe. Audio need not leave the phone. |
| [`TranslationSession`](https://developer.apple.com/documentation/translation/translationsession) | iOS **18.0** (framework 17.4) | Language packs installed (system-managed); `Configuration` source/target. | Deterministic offline translate for the `translate` skill; available on **all** 27.0.1 iPhones (target 18.0 already satisfies). |
| `AVCaptureDevice` torch (`hasTorch`, `torchMode`, `setTorchModeOn(level:)`) | iOS **4.0/6.0** | Camera permission only when configuring capture device; no entitlement. Observable via `isTorchActive`-family state on the device instance the app holds. | Native `flashlight_toggle` with read-back. No Shortcut. (Device has no torch → honest unavailable.) |
| [EventKit](https://developer.apple.com/documentation/eventkit) completion surface (`EKReminder.isCompleted`, `EKRecurrenceRule`, `remove(_:span:commit:)`, day predicates, `EKEventStoreChanged`) | iOS 4–6 era | Full-access usage strings already in `project.yml`. Write-only cannot read back. | Complete/move/cancel/recurring/list-choice flows; "mark done", "move", "every Monday" become verified writes, not one-shot creates. |
| [App Intents](https://developer.apple.com/documentation/appintents): [`LongRunningIntent`](https://developer.apple.com/documentation/appintents/longrunningintent) | iOS **27.0** → **in 27.0.1** | None. Requires progress reporting. | Extends background intent lifetime — the documented fix for a trigger intent that must load a model or finish a multi-step run. |
| [`CancellableIntent`](https://developer.apple.com/documentation/appintents/cancellableintent) | iOS **26.4** → in 27.0.1 | None. | Graceful cleanup when Siri/Shortcuts/user cancels an intent mid-run. |
| [`UndoableIntent`](https://developer.apple.com/documentation/appintents/undoableintent), [`SnippetIntent`](https://developer.apple.com/documentation/appintents/snippetintent) | iOS **26.0** | None. | System Undo for reversible writes; interactive confirm/result UI inside Siri/Spotlight without opening the app. |
| [`IndexedEntity`](https://developer.apple.com/documentation/appintents/indexedentity) + Core Spotlight | iOS **18.0** | None. | App content (saved workflows, memory-backed entities) discoverable in Spotlight semantic index. |
| Controls (`ControlWidgetButton`/`ControlWidgetToggle`, WidgetKit) | iOS **18.0** | Widget extension target (new target, not an entitlement). | Control Center / Lock Screen button for flashlight/focus-style actions owned by **this** app (e.g. start timer, toggle app flashlight). Cannot toggle system Focus/Low-Power. |
| [ActivityKit](https://developer.apple.com/documentation/activitykit) Live Activities + `LiveActivityIntent` (17.0) | iOS **16.1/17.0** | `NSSupportsLiveActivities` Info key. | Observable countdown/brief UI in Dynamic Island/Lock Screen; complements AlarmKit, fallback UI on pre-26 OS. |
| [`ApplicationMusicPlayer`](https://developer.apple.com/documentation/musickit/applicationmusicplayer) (MusicKit 15.0) / MediaPlayer | iOS **15.0** | Music usage string + authorization; Apple Music/library limits. | Verifiable queue+`playbackState` for library/catalog items only — not Spotify, not Apple TV shows. |
| [`INFocusStatusCenter`](https://developer.apple.com/documentation/intents/infocusstatuscenter) | iOS **15.0** | Focus-status entitlement + user permission; **read-only**. No public setter for Focus or Low Power Mode exists. | Read Focus to phrase a handoff honestly. Setting remains Shortcuts-only. Grok is correct here. |
| [WeatherKit](https://developer.apple.com/documentation/weatherkit) (`WeatherService`) | iOS **16.0** | `com.apple.developer.weatherkit` entitlement + App ID capability (paid Developer Program to configure). | Verifiable forecast text vs. Shortcut handoff. Account-gated; not a silent dependency. |
| [`ToolIntent` / `@AppIntent(.tool)` Siri tool-calling](https://developer.apple.com/documentation/appintents/toolintent) + [Siri AI developer preview (3 Nov 2026)](https://developer.apple.com/news/?id=gdk2umrf) | **beta, iOS 27.3** → **OUT of 27.0.1** | Apple-Intelligence device + supported language. | Must not be promised, designed against, or "prepared for" as if present. Agrees with Grok. |
| `AssistantIntent`/assistant schemas (iOS 18.0 types exist) | Types 18.0; **Siri AI invocation 27.3 beta** | — | Conforming early buys Shortcuts/Spotlight structure, **not** Siri AI tool-calling on 27.0.1. Do not market as Siri integration. |

Also swept and **rejected as not useful here** (disconfirming sweep, §5): HealthKit/HomeKit/CoreNFC/FamilyControls/ClassKit (entitlement/school/parental surfaces, high privacy cost, no fit with frozen `skillPick`), CallKit (VoIP provider only — does not improve `tel:` calls), `SFSpeechRecognizer` (superseded by `SpeechAnalyzer` for this use), arbitrary GUI automation (no shipping API; test tools are not product permissions).

### 2.4 Baseline drift Grok could not have seen

`git diff d782b81..009430f` (product files): only string/copy corrections — `ComposeSheets` now says "Messages accepted … delivery not confirmed" / "queued in Mail" (the Capability Map's Slice C copy is therefore **already done at baseline**; its proposed unit test on fallback strings is still meaningful for the `sms:` path) — plus comment removal and `TakeoverRegressionTests` additions. No capability, entitlement, or executor changed. Grok's per-skill code claims remain accurate at `009430f` except those two status strings, which Grok quotes in their old "Sent to … via Messages" form (Capability Map §`imessage_send`, Journeys J1). Any implementation must re-baseline tests to the `009430f` strings.

---

## 3. Detailed independent findings (user flows, failure/recovery, smallest change)

Each finding states: flow → observed postcondition → failure/recovery → smallest implementable change → device acceptance. "Plan impact" is summarised here and consolidated in §7.

### F1. Flashlight — native, verified, no Shortcut (correction-grade)

- **Flow:** "Turn on/off the flashlight" → `skillPick:flashlight_toggle` → confirm (device category, currently model-gated) → native torch set → status reads back torch state.
- **Postcondition:** the `AVCaptureDevice` instance's torch mode/level after `lockForConfiguration` + `setTorchModeOn(level:)`/`torchMode=.off`. The app can truthfully say "Flashlight is on/off". Today it says "Handed to Shortcut" for a toggle whose direction it never specified.
- **Failure/recovery:** no torch hardware (some iPads — target is iPhone, all target iPhones have torch, still guard `hasTorch`); configuration lock failure; camera-in-use contention. Each maps to a typed failure, zero Shortcut fallback inside the same attempt (user may start a new Shortcut request explicitly, per Contract's no-fallthrough rule).
- **Smallest change:** one new native handler in `IOSSkillRunner.runNative` (e.g. `flashlight_set` with `args["state"]=on|off|toggle` resolved from the utterance — `SkillArgs` must stop collapsing on/off into one toggle skill; keep `flashlight_toggle` id for retrieval, add `state` arg). No entitlement, no usage string beyond existing Camera string if device access requires it on the chosen API path — **device-verify** whether torch-only access prompts. Availability: all iOS 18.0-target devices.
- **Acceptance (device, 27.0.1):** on/off/toggle each observed in Control Center torch indicator + app read-back; kill app with torch on, relaunch, read state (system may have turned torch off — status must reflect read, not memory).

### F2. Alarms & timers — AlarmKit as app-owned, system-listed effects

- **Flow:** "Wake me at 6:30" / "Timer 25 minutes" → AlarmKit `schedule(id:configuration:)` with a UUID bound to the attempt → receipt is the returned `Alarm` + a list query containing that id. Cancel/list read `AlarmManager.alarms`. Countdowns support pause/resume semantics AlarmKit defines.
- **Postcondition:** id ∈ system alarm list. Survives app death and SQLite loss (reconcile on launch: journal id missing from system list = fired/cancelled externally — ask, never silently reschedule).
- **Failure/recovery:** authorization denied → `notStarted(.permission)` (Contract Slice 5 shape is correct); unparseable time → card with empty time field (never `NSDataDetector` guess alone); duplicate time → hint + new `UserRequestID` still allowed (Contract's anti-title-key rule). Denied must **not** auto-run the Clock Shortcut in the same attempt.
- **Smallest change:** exactly Contract Slice 5 (`alarmkit_schedule` v2 behind `if #available(iOS 26,*)`, `NSAlarmKitUsageDescription` in `project.yml`, deployment target stays 18.0). Add: launch reconciliation against `AlarmManager.alarms` and snooze/countdown states in the receipt summary ("This app's alarm", never "Clock alarm"). Do **not** add any `com.apple.developer.alarmkit` entitlement — it does not exist; signing would fail.
- **Acceptance:** Journeys A11/A12 plus: schedule → kill → relaunch → list shows id; cancel → list omits id; denied → zero alarms + Settings path; Focus/silent ring-through recorded as observed-or-not, never assumed.

### F3. Voice — on-device transcription (`SpeechAnalyzer`) + editable transcript

- **Flow:** tap-to-record (new; hold remains) → `SpeechTranscriber(locale:preset:.transcription)` via `SpeechAnalyzer` on the recorded file or live buffer stream → **transcript card the user edits** → Confirm sends edited text through `Assistant.handle`. Muse Voice Transcribe becomes the fallback for unsupported locales, not the default.
- **Postcondition:** transcript text produced on device; zero network bytes for audio (assertable in device test by airplane mode). Edited text is what `handle` receives — closing Journeys' "wrong transcript is still a completed pipeline" hole.
- **Failure/recovery:** locale unsupported / assets not downloaded (`AssetInventory` request fails offline) → offer download when online or Muse fallback **only if** voice-upload setting allows; mic denied → Settings path (existing copy); <0.5 s clip → existing "hold while you speak" guard adapted to tap model.
- **Smallest change:** `VoiceCapture.swift` gains a `SpeechAnalyzer` path behind `if #available(iOS 26,*)`; keep WAV recorder (Analyzer accepts file input via `AnalyzerInput` conversion — exact format negotiation `bestAvailableAudioFormat` is device/SDK-verify in code, do not hardcode sample-rate assumptions beyond Apple's sample). Add tap-to-start/stop alongside the `DragGesture` (accessibility: hold is the barrier Grok J16 identifies; a toggle serves Switch Control/VoiceOver).
- **Acceptance:** airplane-mode transcription of a synthetic phrase; locale-missing path; edit-then-send shows edited body in Messages sheet; `voice_stays_on_device` forces local path or refuses — never uploads.

### F4. Reasoning enhancement — Foundation Models (on-device) + PCC, strictly gated

- **Flow (eligible devices only):** `summarize_text`/`analyze_document`/`translate`/`email_digest` when text >1B window or 1B confidence path would escalate to Meta → offer `LanguageModelSession` (`SystemLanguageModel.default`) with `@Generable` structured output (e.g. `{bullets, deadline, nextStep}`) → same scrubber/sensitivity gate for any PCC/Meta leg. On ineligible devices the flow is byte-identical to today.
- **Postcondition:** generated text + provider badge distinguishing "Apple on-device" / "Apple PCC" / "Meta". Structured deadline extraction feeds a **user-reviewed** reminder card (never auto-binds — Contract's rejection of `$digest.when` stands).
- **Failure/recovery:** `.modelNotReady` (downloading) → fall back to 1B truncated-window copy; `.deviceNotEligible` → feature invisible, no error; guardrail refusal → local 1B or clarify. No availability = no UI promise.
- **Smallest change:** a `ReasoningBackend` probe in `Assistant.reason` (`PocketCore` protocol, app-side FoundationModels adapter) behind `#available(iOS 26,*)` + availability check; PCC variant behind `#available(iOS 27,*)` (i.e. present on the 27.0.1 target OS, absent on 18–26 runtime — guard accordingly). **No Reflex/τ/prompt change.** This is an `LLMEngine`-adjacent enhancement, not a decision.
- **Acceptance:** eligible device: airplane-mode summarise of a >2500-char synthetic document names Apple on-device and sends nothing (proxy/airplane evidence); ineligible device: identical request matches today's badge/copy. PCC leg only claimed after an eligible-device run records it.

### F5. App Intents modernization — split, don't lump

- **Now (design input, no behaviour claim):** `LongRunningIntent` (27.0) + `CancellableIntent` (26.4) shape for any intent that loads the model or runs multiple steps — progress reporting prevents the system stall Grok flags for `ProactiveTriggerIntent`. The morning-brief split (no-model SQLite/EventKit path first) remains necessary; `LongRunningIntent` does not make an 808 MB cold load cheap, it makes it survivable/cancellable.
- **Whenever intents are next touched:** `openAppWhenRun` → `supportedModes` (deprecated 26.0, message "Please provide 'supportedModes' instead" — verified in docs JSON). Grok ranks this #15/housekeeping; correct, but it should ride along with the next intent edit, not wait for rank order.
- **Future:** `UndoableIntent` for EventKit-backed intents (system Undo mirrors Contract compensation, still confirm-first); `SnippetIntent` confirm/result snippets in Siri/Spotlight; `IndexedEntity` for saved workflow definitions; Control Center **Controls** for app-owned toggles (flashlight/timer) — each a new extension target decision, not a skill-JSON addition.
- **Explicit non-claim:** none of this enables Siri AI tool-calling on 27.0.1. `ToolIntent` is beta 27.3 (docs JSON: `beta:true, introducedAt:27.3`). Preparing entities/intents is fine; marketing "works with Siri AI" on 27.0.1 is false.
- **Acceptance:** intent timeout/cancel test with model load; `supportedModes` build with zero deprecation warnings; snippet/control items only after their targets exist and are device-run.

### F6. EventKit completion — complete / move / cancel / recur / choose list

- **Flows:** "Mark buy milk done" → fetch incomplete reminders by title → `isCompleted=true`+save → read-back. "Move lunch to 2pm" → fetch by stored id (or `eventPick` among matches) → mutate `startDate/endDate` → save(span:) → read-back. "Cancel my yoga" → `remove(_:span:commit:)` by id after confirm → fetch-miss as receipt. "Remind me every Monday…" → `EKRecurrenceRule` on reminder/event (the frozen `timing` decision exists in `Decision.swift` but `handle` never calls it — wiring `timing` as an arg-parser hint, not a retrain, is the honest bridge; Shortcuts automations remain for location triggers the app cannot arm).
- **Postcondition:** read-back of the mutated/removed item by `calendarItemIdentifier` (Contract Slice 1 receipt rules unchanged).
- **Failure/recovery:** several matches → `eventPick`/`contactPick`-style card, never first-match; externally edited item → Contract `objectChanged`, no delete; write-only access → cannot read back → not-recorded-as-saved (Contract copy already specifies).
- **Smallest change:** extend `SystemActions.perform` with `complete_reminder`/`update_event`/`delete_event` executor tools + registry skills (compiled catalog rows in Contract terms: `localWrite`, compensation `deleteEventKitItem` only for creates). Fix `searchEvents` matching while there: current filter keeps events whose **title words** are substrings of the lowercased query (`q.contains(word)`), so "dentist" works only accidentally; tokenise both sides and match on shared tokens, and add a day-bounded read reusing `eventsOn(_:)` for "today" queries (Journeys' wind-down note identifies the same helper).
- **Acceptance:** complete→Reminders app reflects; move→Calendar reflects new time; cancel→gone; duplicate-title disambiguation card; "today" query ignores tomorrow's same-title event.

### F7. Documents — scanned-PDF OCR + `.docx`, still on device first

- **Flow:** pick/share a scanned PDF → `PDFDocument` pages have no text → render pages → existing Vision OCR (`VNRecognizeTextRequest`, accurate level for documents vs. Glimpse's `.fast`) → summarise pipeline. Pick a `.docx` → unzip (`ZIPFoundation`-free: `Foundation` has no zip reader — use `Compression`/manual central-directory parse or accept `.docx` via `NSAttributedString` docx import on iOS? **Unresolved in this pass:** the lightest public path (attributed-string `.docx` data read vs. bundled zip parser) must be prototyped on SDK; do not promise `.docx` until one is proven. `.rtf`/`.html` via attributed string are lower-risk adds.)
- **Postcondition:** extracted-text length + source filename reported with the summary (kills the stale-share ambiguity Grok Slice-5-adjacent copy targets).
- **Failure/recovery:** OCR-empty → "No text found" (existing honest string); encrypted PDF → explicit failure, no summary; huge doc → page cap + "read first N pages" copy mirroring the 2500-char window honesty.
- **Smallest change:** `DocumentPicker.text(of:)` OCR fallback + `HandleTextIntent` file branch parity. Reuses Vision import already in `CameraGlimpse.swift`.
- **Acceptance:** scanned-image PDF fixture summarises; text-PDF path unchanged; cancelled picker still returns nil→honest message (Journeys A14 extended).

### F8. Timers/alerts on pre-26 OS + observable countdown UI (fallback tier)

Deployment stays 18.0, so AlarmKit (26+) strands iOS 18–25 runtimes. Tiered design: AlarmKit (26+) → else in-app timer backed by `UNUserNotificationCenter` scheduled request (list/cancel via `getPendingNotificationRequests`/`removePendingNotificationRequests` — observable, unlike a Shortcut) + optional Live Activity countdown (ActivityKit). Copy must say "this app's timer/notification", never "Clock timer". Grok Capability Map #8 gestures at the notification timer; the delta is the pending-request read-back as the receipt and the Live Activity as the visible postcondition. Priority: low — only if pre-26 support is a product requirement; on the 27.0.1 target phone AlarmKit alone suffices.

### F9. Contacts identity (mostly Contract-covered; one addition)

Contract already fixes display-string contacts via `ContactBinding`/`CNContact.identifier` re-resolution. Addition: surface iOS 18 `ContactAccessButton` in the limited-access recovery card ("Mom is outside the set this app can see → Add…") — Journeys J1 mentions the button, Capability Map never ranks it. One SwiftUI view in the draft card; no new permission. Also: `addresses(for:)`/`phoneNumber(for:)` take `.first` silently — multi-number choice (Grok #9) should reuse the `contactPick` card pattern with number labels, resolved at perform time by identifier, never stored in definition bytes.

### F10. Weather/Music/Maps/Focus — verifiability upgrades, account-gated (future)

- **Weather:** WeatherKit `WeatherService` returns forecast text the app can quote/check (vs. Shortcut text it cannot see until x-callback). Cost: paid-program capability configuration. Keep Shortcut default; WeatherKit only if a paid team already exists for other reasons. Grok's "paid capability" shorthand is directionally right; precisely, the entitlement is free to declare but the capability must be enabled on an App ID under a paid membership, with service quotas.
- **Music:** `ApplicationMusicPlayer` queue+state verifies "playing X from your library/catalog". Does not generalise to Spotify (`spotify:search:` stays handoff) or TV. Grok #13 already scopes this correctly.
- **Maps:** `MKMapItem.openInMaps(launchOptions:)` / unified `maps.apple.com` URL cleans the archived `maps://?daddr=` form (Grok #11). Add `MKLocalSearch` disambiguation ("Springfield — IL or MA?") as a card before opening; arrival remains unobservable.
- **Focus/Low-Power:** read-only status (`INFocusStatusCenter` with entitlement; `ProcessInfo.isLowPowerModeEnabled` already read) to phrase "Focus appears on; the Shortcut will toggle it" — Grok #12. No setter exists; any "set Focus" claim remains false.

---

## 4. What Grok got right (already-covered — do not re-claim)

Verified against baseline source + docs; Muse concurs without reservation:

1. **Completion contract** (Capability Map "What done means", Contract `Disposition.classify`): `UIApplication.open==true` is URL acceptance only; compose `.sent` is acceptance/queueing, never delivery; Shortcut `result` is author-chosen text, never an OS attestation. The UPI sentence (see C1) is the sole blemish.
2. **EventKit ledger** (Capability #1, Contract Slice 1): refuse unparsed time (kill the `Date()+3600` default in `SystemActions.perform` `create_event`), save→fetch-by-id→token/title/minute match, duplicate *hint* not title/time primary key, compensation only after re-read + fresh confirm.
3. **Shortcut x-callback** (Capability #2, Contract Slice 3): `shortcuts://x-callback-url/run-shortcut` + per-attempt `UUID` token on a registered `pocketglimmer` scheme, one-time consume, cancel/error/timeout → `ambiguous`, never auto-replay. Custom schemes do not authenticate the sender.
4. **`sms:&body=` is not a documented prefill** (Capability #3): MessageUI sheet is the only prefilled send; sheet-unavailable ends the attempt (no silent `sms:`/Shortcut fallthrough). Baseline copy already matches for the sheet path.
5. **Compiled capability authority** (Learned Workflows + Contract catalog): JSON `category`/`confirm`/`effect` are not authority; `SkillRegistry.merge` id-replacement cannot downgrade `imessage_send`; immutable approved versions; exact-phrase triggers are user bindings, not model confidence; `$digest.when`-style output bindings pause for review.
6. **27.3 fence:** Siri AI third-party App Intents (`ToolIntent`, news `gdk2umrf`) start on 27.3 betas, Apple-Intelligence-gated. Describe a Shortcut (iOS 27 Shortcuts feature) is user-owned; the app can copy a description + open `shortcuts://create-shortcut`, never submit/inspect it. 27.2 features out.
7. **AlarmKit discovery itself** (Journeys Slice 3, Contract Slice 5, Plan row "Native alarms and timers"), **TranslationSession** (Capability #7), **MusicKit state** (#13), **Focus/Low-Power read** (#12), **calendar/reminder list choice** (#14), **digest honesty** (#5), **file postcondition** (#6), **phone-number choice** (#9), **in-app notification timer sketch** (#8). Muse's deltas on these are ranking/depth/receipt-shape only (§6).
8. **No-GUI-automation boundary**, frozen 1B/τ=0.90/priors/prompts, Meta Standard-only (`muse-spark-1.3`) planner with local validation, no tool loop — all concurred. XCUITest/agent-device are lab tools, not product execution.

## 5. Disconfirming evidence & rejected candidates

- **Flashlight-via-Shortcut is not forced by iOS.** Counterexample is F1: torch APIs predate the Shortcut bridge by a decade. Grok's Settings paragraph ("Setting Focus, Low Power, or the flashlight … is a Shortcut action") overgeneralises from the two true cases (Focus, Low Power) to a false third.
- **"No public alarm API" is false on 27.0.1** (AlarmKit 26.0) — Grok Journeys/Contract already disconfirm the Capability Map's handoff framing; the Map's ranked list simply never promotes their own correction.
- **Foundation Models ineligibility is the norm, not the edge:** iPhone 11–14 (all supported by iOS 27) have no Apple Intelligence. Any design that *requires* `SystemLanguageModel` breaks the majority of the 27.0.1 fleet. Hence gated enhancement only (F4).
- **HealthKit/HomeKit/NFC/FamilyControls** were swept and rejected: each demands entitlements/privacy review disproportionate to any everyday flow the frozen `skillPick` could route to, and none yields a receipt this app's catalog can honestly name today. Listing them as "capabilities" would manufacture breadth without finishable actions.
- **Private APIs / entitlement inventing disconfirmed:** `com.apple.developer.alarmkit` does not exist (AlarmKit uses an Info-plist usage string + runtime authorization). Similarly, no entitlement unlocks Mail/Instagram reading or Focus writing. Future agents must not "fix" signing by adding invented keys.
- **What Muse could NOT establish:** (a) any 27.0.1 runtime behaviour (no device/Xcode); (b) the lightest public `.docx` extraction path (F7 unresolved); (c) whether torch-only access triggers a Camera permission prompt on 27.0.1; (d) Uber/WhatsApp current deep-link contracts (not re-fetched — same limit Grok declares; templates remain code facts); (e) `photos-redirect://` resolution on 27.0.1 (no Apple page found — Grok's "unresolved" stands); (f) Foundation Models PCC quota/cost terms for this app (availability verified; programme terms not in docs JSON); (g) whether `LongRunningIntent` progress reporting materially extends a GGUF cold load (documented purpose verified; magnitude is a device measurement).

## 6. Comparison table — Muse vs. Grok

| # | Finding | Class | Plan impact |
|---|---|---|---|
| F1 | Native flashlight with read-back; Grok Shortcut-only claim wrong for flashlight | **Correction + new** | Near-term adapter (post-journal). Tiny. |
| F2 | AlarmKit ranking (Map omits from top-15, prefers UN timer) + system-list reconciliation | **Correction (priority)**; discovery already-covered | Stays Contract Slice 5; promote above Map #8. |
| F3 | `SpeechAnalyzer` on-device transcription + editable transcript + tap-to-record | **New** (gap named, remedy unnamed) | New near-term slice beside voice; privacy-positive. |
| F4 | Foundation Models on-device (26.0) + PCC (27.0) gated reasoning | **New** | Future. Eligible-device only. No Slice-1 change. |
| F5 | `LongRunning`/`Cancellable`/`Undoable`/`Snippet`/`IndexedEntity`/Controls split | **New** (beyond #15 housekeeping) | Design input now; targets future. |
| F6 | EventKit complete/move/cancel/recur + `searchEvents` token fix + day reads | **New depth**; create/read-back already-covered | Extends Contract Slice 1/6 scope modestly. |
| F7 | Scanned-PDF Vision OCR; `.docx` path unresolved | **New** (gap named, closure unnamed) | Near-term (OCR half). |
| F8 | Pre-26 timer tier: UN pending-request receipt + Live Activity | **New depth** on Map #8 | Low/future unless pre-26 matters. |
| F9 | `ContactAccessButton` in recovery card; number choice by identifier | Already-covered (Journeys/Contract) + small new placement | Rides draft-card work. |
| F10 | WeatherKit/MusicKit/Maps/Focus verifiability | Already-covered (#11–13) with precision notes | Future, account-gated. |
| C1 | UPI callback ≠ carrier delivery receipt; no delivery API exists | **Correction** (citation) | Copy/doc fix only; contract unchanged. |
| C2 | Baseline `009430f` already has honest compose copy; Grok quotes `d782b81` strings | **Correction** (staleness) | Re-baseline Slice-C tests. |
| C3 | `ToolIntent`/Siri AI 27.3-beta exclusion; Describe-a-Shortcut user-owned | Already-covered — **concur** | None. |
| C4 | Journal/EventKit/x-callback/compiled-catalog core | Already-covered — **concur** | Active plan unchanged. |

## 7. Priorities & tradeoffs (consolidated)

**Do first (unchanged active plan):** privacy repair → `EffectSession` journal (Contract Slice 1) → x-callback (Slice 3) → reviewed definitions (Slice 2 ordering per Contract). Muse adds nothing ahead of these.

**Adopt into the adapter tier (small, verified, no new accounts):** F1 flashlight native handler; F7 OCR fallback; F6 EventKit complete/move/cancel (+`searchEvents` fix); F3 `SpeechAnalyzer` path with transcript editing. Each slots into `PhoneEffects` with an existing receipt kind (`eventKit`, `textProduced`-adjacent) or one new observed kind for torch/alarm state — catalog version bump per Contract rules, never JSON-authored.

**Keep sequenced as already planned:** F2 AlarmKit (Contract Slice 5) — but record it as the timer/alarm answer on the 27.0.1 target; the UN-notification timer (F8) is only a pre-26 fallback, not a peer.

**Future / gated:** F4 Foundation Models + PCC (eligible devices; measure before promising), F5 snippets/controls/indexing (extension-target decisions), F10 WeatherKit/MusicKit (paid-team decisions). None blocks, and none should delay, the journal.

**Tradeoff statement:** every addition above trades breadth for receipts. The rejected breadth (Health/Home/social-send/GUI taps) would demo wider and verify nothing. The accepted set demos narrower and can say, per attempt, exactly what was observed — which is the product's stated contract.

## 8. Verification still required (no device claim made)

Mac + physical iPhone on **27.0.1 specifically** (record OS build, model, region, Apple-Intelligence eligibility): signed Release build; F1 torch read-back incl. relaunch; F2 A11/A12 + reconciliation; F3 airplane-mode transcription + edit-then-send; F4 eligible vs. ineligible badge behaviour; F6 complete/move/cancel in Reminders/Calendar; F7 scanned-PDF fixture; intent timeout under cold model load (F5); limited-contacts `ContactAccessButton` flow (F9); `maps://` vs. unified URL and `photos-redirect://` resolution (carried over, still open). Simulator/XCUITest results close none of these.

## 9. Sources (retrieved 2026-11-04)

Apple docs (canonical; inspected via `/tutorials/data/documentation/*.json` mirror): AlarmKit & scheduling article; `NSAlarmKitUsageDescription`; Foundation Models, `SystemLanguageModel`, `PrivateCloudComputeLanguageModel`; Speech `SpeechAnalyzer`/`SpeechTranscriber`; Translation `TranslationSession`; AVFoundation `AVCaptureDevice`; EventKit; App Intents (`LongRunningIntent` 27.0, `CancellableIntent` 26.4, `UndoableIntent`/`SnippetIntent` 26.0, `IndexedEntity` 18.0, `ToolIntent` beta 27.3, `supportedModes`/`openAppWhenRun` deprecation 26.0); WidgetKit controls (18.0); ActivityKit (16.1); MusicKit `ApplicationMusicPlayer` (15.0); `INFocusStatusCenter` (15.0); WeatherKit (16.0); MessageUI `setUPIVerificationCodeSendCompletion` (17.0, UPI validation); [Siri AI developer preview, 3 Nov 2026](https://developer.apple.com/news/?id=gdk2umrf). Repo: `git show 009430f:` for every code citation; Grok reports as listed in the header.

*End of report. No implementation performed. No device test performed or implied.*
