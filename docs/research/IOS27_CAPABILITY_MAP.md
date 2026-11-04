# iOS 27.0.1 capability map

> Parent review update, 2026-11-04. This report is a historical source snapshot. Native torch
> control is supported by AVFoundation; it is not inherently Shortcut-only. The UPI callback
> is specialized device enrollment, not ordinary message delivery. See
> [reviewed Muse findings](MUSE_REVIEW_FINDINGS.md) for corrections and current evidence limits.

Audit date: 2026-11-04. Audited tree: `d782b81` (`docs: correct round-two data provenance and comparison limits`). This pass changes no product code. The iPhone app in this tree is unbuilt. Nothing here is a device measurement.

Labels used below:

- **Doc.** A primary page says this.
- **Code.** The committed sources do this.
- **Inference.** A conclusion from those two, not from a phone.
- **Device.** Only an iPhone on iOS 27.0.1 can settle it.

## Requested outcome

A third-party SwiftUI app on iOS 27.0.1 can prepare a small set of on-device results and can hand the user to system sheets, Maps, Phone, Shortcuts, and other apps. It cannot observe most of those other apps' outcomes. This map says which of the 36 built-in skills can finish and check a result, which stop at a person or a Shortcut, and which must not be promised. It also names a short implementation set that stays inside public APIs, the frozen model, and Meta Standard mode.

## Version fence

Research target is **iOS 27.0.1**, not "current iOS" and not the 27.3 developer beta.

| Release | What Apple documents | Use for this app |
|---|---|---|
| iOS 27 | Siri AI, Describe a Shortcut, Shortcuts "Use Model" updates, automations embedded in shortcuts, Apple Intelligence photo and Safari tools. Device and region limits apply. [Doc](https://support.apple.com/en-us/149076), [Doc](https://support.apple.com/en-nz/149045) | The feature surface of 27.0.1, because 27.0.1 is a bug-fix update on that base. |
| iOS 27.0.1 | Bug fixes only: unexpected restart when Face ID fails on iPhone 18 Pro, a color artifact on some 2x photos, and a frozen touchscreen if Notification Center and Control Center open together. Security list dates this release 28 Sep 2026 and lists no CVEs for it. [Doc](https://support.apple.com/en-us/149076), [Doc](https://support.apple.com/en-us/100100) | The OS this map is about. |
| iOS 27.2 | Siri AI conversation memory, more personal-context sources, more Siri AI languages, Messages suggestions, Apple TV simple profiles. Apple's security page calls 27.2 the latest iOS as of 30 Oct 2026. [Doc](https://support.apple.com/en-us/149076), [Doc](https://support.apple.com/en-nz/149045), [Doc](https://support.apple.com/en-us/100100) | Out of scope. Do not implement or claim these as 27.0.1 behavior. |
| iOS 27.3 beta | 3 Nov 2026: Siri AI developer preview so apps can expose App Intents to Siri AI. Requires an Apple Intelligence device and a supported language. [Doc](https://developer.apple.com/news/?id=gdk2umrf) | Not on 27.0.1. Cloud escalation cannot unlock it. |

Apple's iOS 27 download page lists hardware from iPhone 11 and iPhone SE (2nd generation) upward, including later models. [Doc](https://support.apple.com/en-au/128058). Apple Intelligence on iOS 27, including Describe a Shortcut and Use Model, is documented for iPhone 15 Pro, iPhone 15 Pro Max, and iPhone 16 and later, and is not available in every language or region. Usage limits apply. [Doc](https://support.apple.com/en-om/guide/shortcuts/tpg3vrvwmclv/10.0/ios/27), [Doc](https://support.apple.com/en-us/121115). Confirm the signed-in device, Siri language, and region on the phone. A URL about a feature is not that confirmation.

The app's deployment target is iOS 18.0 (`app/project.yml`), which permits targeting 27.0.1; installation still requires a successful build and signing. The audited source does not call iOS 27-only symbols. Entitlements are empty (`app/PocketGlimmer/Support/PocketGlimmer.entitlements`). There is no increased-memory entitlement, no WeatherKit, no Family Controls, no MusicKit, no Focus status, no background mode, and no registered URL scheme.

## Plain-language summary

**Local outcomes supported by the source and public APIs, still unverified on this phone**

- Read this phone's battery level and a storage figure from Apple's APIs, and say when the battery reading is unknown.
- Draw a bar chart from numbers the user typed or shared, inside the app.
- Save and later find a fact in the app's own database.
- Save a reminder or a calendar event into the user's calendars, and look up events in the next 30 days. The current code does not read the saved item back, and a vague time can become "one hour from now" without an extra confirm.

**Needs the user, or a Shortcut the user installed**

- Text and email: the system compose sheet, then the user taps Send. The app can see that tap. It cannot see that the other person received it.
- A phone call or FaceTime: the system prompt. Connecting is not reported back.
- Instagram, X, WhatsApp, Uber, Maps, Safari search, Music, Spotify, Photos: the app opens a link. The user finishes in the other app.
- Alarms, timers, Notes, Focus, Low Power, flashlight, weather, "open this app," and Apple TV: a Shortcut named in advance. The app only learns that Shortcuts accepted the link.

**Cannot honestly promise**

- Sending or reading Instagram, X, WhatsApp, or the Mail inbox.
- Proof that a show, song, alarm, timer, or ride started.
- A general agent that taps other apps, learns new iOS permissions, or runs Siri AI on the app's behalf. That developer preview starts on the 27.3 betas.
- The demo line "Text Mom I'll be home by 8." On the CPU engine it asks for clarification and does nothing. "Text Sam…" asks which Sam. Apple TV plans a Shortcut handoff. [Code] `docs/ENGINE_REHEARSAL_NOV4.md`.

## What "done" means

Use this contract for every skill and every new flow. A step is complete only when its postcondition is observed. `UIApplication.shared.open` returning true means the system opened the URL. If no app handles the scheme, it returns false. [Doc](https://developer.apple.com/documentation/uikit/uiapplication/open(_:options:completionhandler:)). That Boolean is not a sent message, a finished Shortcut, or playback.

| Clause | Rule for this app |
|---|---|
| Outcome | One sentence the user can check. "Reminder exists in Reminders" is an outcome. "Opened a URL" is a handoff. |
| Preconditions | Permission, account, installed app, installed Shortcut, network, Apple Intelligence device, and model confidence at or above τ = 0.90. |
| Actions | Only public APIs already in the process, or a URL/Shortcut the user finishes. |
| Postcondition | A value the app read back: EventKit identifier, compose-sheet result, file contents, chart bar count, or x-callback `result` text. |
| Permission | Prompt with the existing usage strings. A denial is a stopped flow, not a silent fallback that claims success. |
| Handoff | Name the app or sheet the person must use. Return to Pocket Glimmer only through a documented callback. |
| Failure | Missing permission, missing contact, low confidence, bad arguments, sheet unavailable, URL refused, Shortcut error, user cancel. |
| Retry | Same idempotency key. Ask again only if the first attempt did not record a postcondition. |
| Undo | Store the EventKit identifier or the memory row id and delete that object. There is no undo for a message the user already sent. |
| Duplicates | One in-flight confirm per card is already cleared in `AppModel.confirm` before `execute`. A second utterance still creates a second reminder or event. New writes need a key. |

Opening `shortcuts://run-shortcut` is the handoff the code uses (`SkillTemplate.shortcutURL`). Apple also documents `shortcuts://x-callback-url/run-shortcut` with `x-success`, `x-cancel`, and `x-error`. On success, a `result` parameter carries the shortcut's textual output. Cancel returns no output. Error appends `errorMessage`. [Doc](https://support.apple.com/en-om/guide/shortcuts/apdcd7f20a6f/10.0/ios/27), [Doc](https://support.apple.com/en-om/guide/shortcuts/apd624386f42/10.0/ios/27). The app does not register a callback scheme, so it cannot receive those parameters. **Inference:** `result` is text the shortcut author chose to output. It is not an operating-system attestation that an alarm exists or that Apple TV is playing.

## How a request becomes an action

Code path, frozen model, τ = 0.90:

1. `Assistant.handle` runs the trained `route` decision.
2. Explicit requests can try `skillPick` even when route confidence is low (`ActionPlanner.skillOverride`, `isExplicitRequest`). An explicit "Text …" that misses τ asks for clarification and does not execute. [Code] `ActionPlanner.planSkillCore`, `docs/ENGINE_REHEARSAL_NOV4.md`.
3. `skillPick` is one forward pass over at most seven retrieved skills. Below τ the reply is "Did you mean" and no side effect runs.
4. Arguments are regexes (`SkillArgs.extract`), not a general parser. Several contacts go through trained `contactPick`.
5. `confirmBeforeAct` runs. Categories `message`, `social`, and `email` force confirm even if JSON says false (`SkillCategory.reachesOtherPeople`). Phone calls and Uber confirm because their JSON says `confirm: true`, not because of that category rule.
6. `Assistant.execute` sends EventKit and compose actions to `SystemActions`. Everything else goes to `IOSSkillRunner`.
7. `AppModel.confirm` clears `pending` before it executes, so a second tap on the same card does not fire twice. Cancel only clears the card.

CPU rehearsal at the shipping GGUF, bundled calibration, τ = 0.90, prefix reuse off. These are development rows, not phone latency. [Code] `docs/ENGINE_REHEARSAL_NOV4.md`.

| Utterance | Route | Skill | Result |
|---|---:|---:|---|
| Text Mom I'll be home by 8 | 0.826 | 0.810 | Clarification, no action |
| Text Mom that I'll be home by 8 | 0.868 | 0.805 | Clarification, no action |
| Text Mom: I'll be home by 8 | 0.819 | 0.787 | Clarification, no action |
| Text Sam I'm running late | 0.801 | 0.989 | Asks "Which Sam?" (contact choice 0.573) |
| Open the latest episode of Severance on Apple TV | 0.762 | 0.995 | Plans `appletv_play` and asks for confirmation |

The integrated core run recorded with that rehearsal is 108 tests, 1 opt-in API test skipped, 0 failures. App Swift files had syntax parsing only. No iPhone build, tokenization check, or memory measurement exists for this tree. [Code] `docs/ENGINE_REHEARSAL_NOV4.md`, `docs/PROJECT_STATUS.md`, `docs/EVALUATION_CLAIMS.md`.

Decision-label accuracy is not task success. The withdrawn 10.2% figure stays withdrawn. Do not retrain, retune τ, run gold inference, or call a paid API to "improve" this map.

## The 36 skills

Source of truth: `app/PocketGlimmer/Resources/Skills/builtin.json`, `IOSSkillRunner`, `SystemActions`, `Assistant.execute`.

### Finish inside the app

These can meet a local postcondition. They are still **device-unverified** until a signed 27.0.1 build runs them.

| Skill | Outcome that can be checked | Preconditions | What the code does now | Gap |
|---|---|---|---|---|
| `device_status` | A battery percent, or "unknown", plus a volume-capacity figure and Low Power state. | None beyond the app running. | `UIDevice.batteryLevel` after enabling monitoring. Level below 0 becomes "unknown". Storage uses `volumeAvailableCapacityForImportantUsage`. [Code] `IOSSkillRunner.deviceStatus` | The number is the API value, not a promise that it matches Settings. Simulator and some states report unknown battery. |
| `html_viz` | A sheet whose bar count matches numbers parsed from the text. | The text contains label/number pairs. | `HTMLViz.render`, then `HTMLSheet` in a `WKWebView` with JavaScript off. [Code] | The chart is not saved unless the user taps Share. Title generation uses the local model for at most 12 tokens. |
| `memory_recall` | A row from the app SQLite store, or a miss. | The fact was stored earlier by this app. | Native `search_memory`. The store answers before the runner. [Code] `SystemActions` comment and `Assistant` | This is the app's memory, not Messages, Mail, Photos, or Notes. |
| `reminder_create` | `EKEventStore.save` returns for a new `EKReminder`. | Full reminders access. `NSRemindersFullAccessUsageDescription` is set. [Code] `project.yml`. API: `requestFullAccessToReminders`. [Doc](https://developer.apple.com/documentation/eventkit/accessing-the-event-store) | Builds a reminder, optional due date via `NSDataDetector`, alarm at that date, saves. Confirm is false unless the model asks. [Code] `SystemActions.perform` | No read-back, no identifier kept, no duplicate check. Access denial is ignored at request time (`try?`) and surfaces only when save throws, as "Failed". Notification delivery is a separate permission. |
| `calendar_create` | `save(_:span:)` returns for a new `EKEvent`. | Full calendar access. Usage string is set. [Doc](https://developer.apple.com/documentation/eventkit/accessing-the-event-store) | Title plus parsed start, or **now + 1 hour** if parsing fails. End is start + 1 hour. Default calendar. Confirm is false unless the model asks. | A vague utterance can write a real event at the wrong time with no confirm. No read-back, no calendar picker, no duplicate check. iCloud sync is not observed. |
| `calendar_find` | A title and time from events in the next 30 days, or the miss string. | Full calendar access. Write-only access cannot read. [Doc](https://developer.apple.com/documentation/eventkit/accessing-the-event-store) | Token overlap between the query and the title. [Code] `searchEvents` | Easy to miss "dentist" if the title does not share a token. Window is 30 days from now, not the past. |

`lookup_contact` is a trained tool, not one of the 36, and uses the same Contacts permission.

### The user must act, and the app can see that act

| Skill | Observable postcondition | Not observed |
|---|---|---|
| `imessage_send` | `MessageComposeResult.sent` after the user taps Send in `MFMessageComposeViewController`, when `canSendText()` is true. The status string is "Sent to … via Messages". Cancel and failure are distinct. [Code] `ComposeSheets` | Carrier delivery. The entitlement-gated UPI callback is the API that reports transmission to the carrier, and this app does not use it. [Doc](https://developer.apple.com/documentation/messageui/mfmessagecomposeviewcontroller/setupiverificationcodesendcompletion(_:)). If the sheet cannot show, the code opens `sms:<digits>&body=…` or the Shortcut "PG Send Message". Apple's current `sms` and `im` documentation says the URL must not include message text. [Doc](https://developer.apple.com/documentation/messages/preparing-your-app-to-be-the-default-messaging-app). **Inference:** the body-prefill fallback is undocumented and must not be described as a filled message. Only the first phone number is used. The Mom demo never reaches this sheet on the CPU engine. |
| `email_compose` | `MFMailComposeResult.sent` means the message was queued in the user's outbox. `.saved` is a draft. `.cancelled` sends nothing. [Doc](https://developer.apple.com/documentation/messageui/mfmailcomposeresult), [Code] `ComposeSheets.mail` | SMTP delivery. `mailto:` fallback only means Mail or another handler opened. [Doc](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app) lists `mailto` as a system scheme. First email address only. |
| `analyze_document` | The user picks one PDF, `.txt`, or `.md`. `PDFDocument.string` or UTF-8 text comes back, then a summary is generated. Cancel returns nil and the user is told no text was found. [Code] `DocumentPicker` | Word files. Scanned PDFs with no text layer. Summary quality. |
| `email_digest` | If `SharedInbox` has text from `HandleTextIntent`, the app summarizes that text. | The Mail inbox. The `n` argument ("last 5") is parsed and then ignored. [Code] `Assistant.execute` case `.native("email_digest")`. The honest path is Mail, select, Share, Shortcut "PG Share Emails", then this intent. |
| `summarize_text` | Summary text from shared or inline text. | That the summary is faithful. Long text can go to Muse Spark 1.3 only when online, configured, and `sensitivity` allows, after scrubbing. [Code] `Assistant.reason` |
| `translate` | Generated text. Short text stays on the 1B. [Code] skill invocation `cloud` / `generation` | Translation correctness. The system Translation framework is a better checker and is not used. See proposals. |

`HandleTextIntent` and `RunSkillIntent` return the assistant's reply string to Shortcuts (`IntentResult & ReturnsValue<String>`). They set `openAppWhenRun = true`, so Shortcuts brings the app forward. [Code] `SkillIntents.swift`. That string is the app's reply, including handoff wording. It is not an external receipt.

### Handoff only

`IOSSkillRunner.runShortcut` and `openURLSkill` treat a true open as success. Status strings say "handed to" or "opened". They do not wait for the other app. [Code]

| Skill | What opens | User still has to | Cannot check |
|---|---|---|---|
| `alarm_create` | Shortcut "PG Create Alarm" with `{time}\|{label}` | Have that Shortcut, and let Clock create the alarm | That an alarm exists. No public Clock framework is used. |
| `timer_start` | Shortcut "PG Start Timer" with `{duration}` | Same, with Clock's Start Timer action | That a timer is running. |
| `appletv_play` | Shortcut "PG Play on Apple TV" with the show name. If Shortcuts itself will not open, a `https://tv.apple.com/search?term=` page. [Code] | Build a Shortcut whose actions exist on that device. Confirm is model-dependent (`confirmBeforeAct`), not a category hard rule. The Severance rehearsal asks. | Playback, the right episode, or that the Shortcut exists. `docs/SKILLS.md` already says the playback recipe is unverified. |
| `open_app` | Shortcut "PG Open App" with the app name | The Shortcut and the app | That the intended app became frontmost. |
| `notes_create` | Shortcut "PG Create Note" | Notes' Create Note action | A note identifier. `mobilenotes://` is documented in the skill note as open-only, and the code does not use it. |
| `flashlight_toggle` | Shortcut "PG Toggle Flashlight" with empty input | A toggle Shortcut | On versus off. "Turn on" and "turn off" are the same handoff. |
| `focus_toggle` | Shortcut "PG Toggle Focus" | Same | Focus state. No `INFocusStatusCenter` read. |
| `low_power_toggle` | Shortcut "PG Toggle Low Power" | Same | The toggle result. A later `device_status` can read `isLowPowerModeEnabled` only after the user comes back and asks. |
| `weather` | Shortcut "PG Weather" | The Shortcut, location permission inside Shortcuts, network | The forecast text, unless the Shortcut is later switched to x-callback and returns text. WeatherKit needs a paid capability. The skill note is right to avoid it. |
| `run_shortcut` | `shortcuts://run-shortcut?name=&input=text&text=` | The named Shortcut. First run from another app can require the user's Shortcuts privacy choice. [Doc](https://support.apple.com/en-om/guide/shortcuts/apd624386f42/10.0/ios/27) | Output, cancel, or error. |
| `create_shortcut` | `shortcuts://create-shortcut` | Build the shortcut in the editor. [Doc](https://support.apple.com/en-om/guide/shortcuts/apda283236d7/10.0/ios/27) | That anything was saved. |
| `call` | `tel:<first number>` | The system call prompt. `confirm: true` in JSON. | That the call connected. Open success is not the prompt's result. Several numbers on one contact are not disambiguated. |
| `facetime` | `facetime:<first number>` | The FaceTime prompt and an Apple ID path that can place the call | That a call connected. |
| `maps_directions` | `maps://?daddr=<place>` | Maps, then start navigation | Arrival or that a route was chosen. Archived Map Links use `daddr` on `maps.apple.com` URLs. [Doc](https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/MapLinks/MapLinks.html). A 2025 DTS note points current work at unified Maps URLs from iOS 18.4. **Device:** confirm which form 27.0.1 still opens. |
| `uber_ride` | `uber://?action=setPickup&…dropoff[formatted_address]=` | Confirm a paid ride in Uber | Price, driver, or trip. This pass did not re-fetch Uber's current deep-link contract. Treat the template as code, not as Uber's current guarantee. |
| `web_search` | DuckDuckGo `https` query | Read the results | That a result was useful. |
| `open_url` | The URL the user named, inserted without extra encoding | The browser or universal-link app | Page contents. |
| `music_play` | `music://` only. The query argument is ignored. [Code] builtin template | Pick and play in Music | Playback state. |
| `spotify_play` | `spotify:search:<query>` | Spotify account and a tap | Playback. |
| `photos_open` | `photos-redirect://` | The Photos app, if this scheme still resolves | Any photo. This pass found no Apple URL-scheme page for `photos-redirect`. Classify as unresolved on 27.0.1. |
| `instagram_dm` | `https://ig.me/m/<handle>` plus clipboard | Paste and send in Instagram | A sent DM. Meta's documented Instagram send API is for a professional account replying to a person who already messaged that account, using an Instagram-scoped id and a page token. [Doc](https://developers.facebook.com/docs/messenger-platform/instagram/features/send-message). It is not a personal-DM API for an arbitrary handle. |
| `x_dm` | `https://x.com/<handle>` plus clipboard | Tap Message, paste, send | A sent DM. The skill note is right that a numeric recipient id is required for a prefilled X DM, and the app does not have one. |
| `whatsapp_send` | `whatsapp://send?text=<body>` | Pick the chat and tap Send. The required contact is not placed in the URL. [Code] | Delivery. This pass did not re-fetch WhatsApp's current click-to-chat parameter page, so the contact-less template is a code fact. |

`instagram_autoreply` is not a handoff and not an automation. It writes `autoreply_rule` into memory with provenance `user_stated` and tells the user that iMessage automations are the closest system feature. [Code] `IOSSkillRunner.runNative`. Instagram is not answered.

### Shortcuts the user must install

Apple documents these as user-built actions, not as APIs the app can embed: Create Alarm, Start Timer, Open App, Create Note, Set Flashlight, Set Focus, Set Low Power Mode, Get Current Weather, Send Message, and whatever TV actions exist on that device. The iOS 27 guide also says some personal automations can run without asking after the user turns on Allow Running When Locked. The listed triggers include Time of Day, Alarm, Sleep, Arrive, Leave, CarPlay, Email, Message, Wi-Fi, Bluetooth, App, Airplane Mode, Do Not Disturb, Low Power Mode, Battery Level, and Charger. The same page says individual actions may still need to be allowed to run automatically. [Doc](https://support.apple.com/en-om/guide/shortcuts/apdfbdbd7123/10.0/ios/27).

The app cannot create, list, or silently import those shortcuts. `shortcuts://create-shortcut` opens an editor. Sharing an iCloud shortcut still requires the recipient to add it. [Doc](https://support.apple.com/guide/shortcuts/share-shortcuts-apdf01f8c054/ios). There is no documented API to enumerate the user's shortcut library.

`ProactiveTriggerIntent` is the hook a user-authored automation can call. `openAppWhenRun` is false. It boots the app model if needed, runs `Proactive.handle`, and posts a local notification. Onboarding requests notification authorization. [Code] `Intents.swift`, `AppModel.handleTrigger`, `OnboardingView`. **Device:** loading the 808 MB model from an automation may be killed. Apple tells developers to return from intents promptly and to prefer background execution. [Doc](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent). No `UIBackgroundModes` are declared.

`openAppWhenRun` is deprecated in the current App Intents docs. The replacement is `supportedModes`. The deprecated property remains for compatibility inside the app. [Doc](https://developer.apple.com/documentation/appintents/appintent/openappwhenrun), [Doc](https://developer.apple.com/documentation/appintents/configuring-the-runtime-behavior-of-your-app-intents). Migrating is housekeeping. It does not add Siri AI.

## Domain notes for 27.0.1

**Communications.** Supported compose path is MessageUI and `mailto`. Supported lookup is Contacts, which on iOS 18 and later can be limited to selected contacts, so "Mom" can be missing even when Mom is on the phone. **Device:** confirm the limited-access prompt on 27.0.1. The App Intents messages schema dated 3 Nov 2026 lets a messaging app expose its own send action to Apple Intelligence. [Doc](https://developer.apple.com/documentation/appintents/app-schema-domain-messages). It does not let this app read Messages. Siri AI invoking third-party intents is the 27.3 beta, not 27.0.1.

**Calendar and reminders.** EventKit full access is the right public API and is already requested. Shared calendars that already appear in the user's EventKit store can be read and written with the same API. That is the family-coordination path. Family Controls, Managed Settings, and Device Activity are a different, entitlement-restricted parental-control surface and are not a general assistant feature.

**Files and documents.** The app can open a user-picked PDF or text file, summarize it, and chart numbers. UIFileSharing is on, so the user can copy files into the app's Documents, including `Skills/*.json`. Word is unsupported. A summary saved into Documents would be a new verifiable file. It is not there now.

**Photos.** Camera and library usage strings exist for the glimpse flow. The image leaves the phone only after the local sensitivity path, and only if the user uses that cloud feature. [Code] `docs/PROJECT_STATUS.md`, `MetaMultimodal.swift`. `photos_open` does not read the library. There is no skill that searches the photo library.

**Navigation and travel.** Maps and Uber are handoffs. A ride that spends money stays behind confirm. No booking, ticket, or transit API is integrated.

**Media.** Music and Spotify open apps. Apple TV is a user Shortcut plus a search-page fallback. iOS 27.2's Apple TV profiles are out of scope. Playback APIs worth a later slice are MusicKit `ApplicationMusicPlayer` or MediaPlayer, both of which can expose playback state after authorization. [Doc](https://developer.apple.com/documentation/musickit/applicationmusicplayer). They need an account or a library, a usage string, and a device test. They are not in this tree.

**Settings and Focus.** Third-party code can read Low Power Mode (`ProcessInfo`) and, with a separate Focus status entitlement and user permission, Focus state. This app does neither for the toggle skills. Setting Focus, Low Power, or the flashlight from a third-party process is a Shortcut action the user installed. Deep-linking to this app's own Settings page is public (`UIApplication.openSettingsURLString`) and only opens Settings.

**Accessibility, voice, and language.** iOS 27 system features include richer VoiceOver image descriptions, Magnifier conversation, Accessibility Reader summaries and translation, and Voice Control phrases such as describing a control. [Doc](https://support.apple.com/en-us/149076). Those belong to the system. This app does not implement them and should not claim them. The app's microphone path sends audio to Muse Voice Transcribe before the sensitivity check can see the transcript. [Code] `project.yml` microphone string, `docs/PROJECT_STATUS.md`. People who need speech to stay on device should leave voice off. Extra Siri AI languages listed under iOS 27.2 are not 27.0.1 behavior.

**Productivity, study, and household coordination.** Local memory, reminders, calendar, charts, and shared-text summaries cover personal lists and study notes the user pastes or picks. They do not cover a school information system. ClassKit is for apps distributed through school management, not a general skill. Household use is shared calendars and shared reminder lists already visible to EventKit, plus the user tapping Send on a message.

**Service APIs that fit.** Meta Model API, Standard mode, model id `muse-spark-1.3`, base `https://api.meta.ai/v1/`, is the configured cloud brain. Contributor-mode ids are refused before a request. Fireworks, Baseten, and Modal presets exist in `CloudPresets` and are not the Settings path. [Code] `CloudBrain.swift`, `MetaAPI.requireStandardMode`, `AppModel.CloudSettings.chain`. A key lives in the Keychain. Muse can draft text or a proposed plan. It cannot grant a permission, install a Shortcut, or observe another app. Do not call the API from this research line.

## Learning a workflow without a new preset skill

What already works:

- A JSON file in Files, On My iPhone, Pocket Glimmer, Skills, is merged at boot (`SkillSetup.registry`). Same id replaces a built-in. Invocation must be `url`, `shortcut`, `native` (known handlers only), or `cloud`. Unknown native handlers return "isn't available on this build". [Code] `SkillRunner.runNative` default.
- The user can describe a Shortcut in the Shortcuts app on an Apple Intelligence device. iOS 27 documents natural-language creation and the Use Model action (On-Device, Cloud, Cloud Pro, Extension Model). [Doc](https://support.apple.com/en-us/149076), [Doc](https://support.apple.com/en-om/guide/shortcuts/tpg3vrvwmclv/10.0/ios/27), [Doc](https://support.apple.com/en-nz/149045). Pocket Glimmer has no API to drive that generator. The useful integration is: show the description, open `shortcuts://create-shortcut`, and later run the named shortcut.
- The user can point a Shortcut at `AskPocketGlimmerIntent`, `HandleTextIntent`, `RunSkillIntent`, or `ProactiveTriggerIntent`. That is how a new multi-app workflow calls back into the app. The app then does only what those intents already do.

What a new in-app workflow may do:

1. The user describes a repeated task in text.
2. The local model, or Muse Spark 1.3 in Standard mode after the sensitivity check, returns a plan whose steps are ids from the allowlist below. The model does not pick new URL schemes or new native handlers.
3. The app shows every step, its handoff, and its postcondition. The user saves it. Nothing irreversible runs during the draft.
4. A saved workflow is a JSON skill or a short list of existing skills. Messages, social, email, calls, and Uber still confirm on every run.
5. Each run writes an idempotency key and a postcondition. A second run with the same key asks instead of writing another event.

Allowlist for a learned workflow: `reminder_create`, `calendar_create`, `calendar_find`, `memory_recall`, `device_status`, `html_viz`, `notes_create` (handoff), `alarm_create` (handoff), `timer_start` (handoff), `run_shortcut` (named shortcut the user already has), `web_search`, `open_url`, `maps_directions`. Exclude anything that messages a person until the existing confirm card is shown again.

Describe a Shortcut remains a user step on a capable device. If the device is not Apple Intelligence capable, the same screen should say so and offer the manual editor only.

## Ranked additions

Scores are judgment from the evidence above: user benefit, effort in this repo, reliability of the public API, and whether the app can check completion. 5 is the favorable end.

| Rank | Addition | Benefit | Effort | Reliability | Can verify | Why this rank |
|---:|---|---:|---:|---:|---:|---|
| 1 | EventKit ledger: re-read by identifier, refuse a guessed time, store an idempotency key, undo by deleting that id | 5 | 4 | 5 | 5 | Turns the two real writes into contracts. No new dependency. |
| 2 | x-callback adapter for Shortcut skills, plus a URL scheme and `onOpenURL` | 5 | 3 | 4 | 4 | Distinguishes finished, cancelled, and missing shortcuts. `result` is still only text. |
| 3 | Message path: keep MessageUI as the only prefilled send; stop treating `sms:&body=` as a filled message | 4 | 5 | 5 | 4 | Matches Apple's current `sms` rule and the compose-sheet result the code already has. |
| 4 | Saved workflows: draft on the allowlist, user saves, per-run confirm for people and money | 5 | 3 | 4 | 4 | This is the learning path that does not pretend to be a GUI agent. |
| 5 | Say what email digest actually summarized (shared text length), and ignore a fake "last N" | 4 | 5 | 5 | 5 | Removes a false outcome with a copy and test change. |
| 6 | Write the chart or summary into Documents and return the filename | 4 | 4 | 5 | 5 | File existence is a postcondition. File sharing is already on. |
| 7 | `TranslationSession` for `translate` when the language pair is installed; otherwise say it is not installed | 4 | 3 | 4 | 4 | System framework, no new package. [Doc](https://developer.apple.com/documentation/translation/translationsession). Quality still depends on Apple's languages. |
| 8 | In-app timer that posts a local notification at the end, used only when the Clock Shortcut does not return success | 4 | 3 | 4 | 4 | The app can prove it scheduled its own timer. It must not claim the Clock timer. |
| 9 | Phone-number choice when a contact has several numbers, before call, FaceTime, or Messages | 4 | 4 | 4 | 3 | Uses the same confirm style as "Which Sam?". The call itself stays a handoff. |
| 10 | Guided Describe a Shortcut: copy the user's sentence and open the editor | 3 | 4 | 3 | 2 | Right integration for iOS 27, and honest about who creates the shortcut. Apple Intelligence device required. |
| 11 | Maps handoff through `MKMapItem.openInMaps` or the unified `https://maps.apple.com` URL | 3 | 4 | 3 | 2 | Cleaner handoff. Still not navigation. Confirm the 27.0.1 URL on a device. |
| 12 | Read Focus and Low Power, and pass `on` or `off` into the Shortcut input | 3 | 3 | 3 | 3 | The read can be true. The set remains a Shortcut. Focus read needs the status entitlement and a permission prompt. |
| 13 | Music library playback through MediaPlayer or MusicKit, with `playbackState` | 3 | 2 | 3 | 4 | Verifiable only after authorization and only for items the API actually queued. Leave `music://` as the fallback that claims "opened". |
| 14 | Pick a calendar or reminder list when more than one is writable, including shared household lists | 3 | 3 | 4 | 4 | Uses EventKit the user already granted. No Family Controls entitlement. |
| 15 | Move intents from deprecated `openAppWhenRun` to `supportedModes`, and keep the check-in intent background-only | 2 | 4 | 4 | 3 | Matches current docs. Does not add 27.3 Siri AI. |

Do not rank these as near-term: Instagram or X send APIs, Mail inbox reads, screen tapping, private frameworks, WeatherKit as a hidden dependency, Family Controls, ClassKit, or calling Muse to invent permissions.

## Near-term set for this repository

Ship these in order. Each slice is testable without a phone except where marked Device. No new packages, no threshold change, no gold run, no paid call, Meta Standard only if a test double is used.

### Slice A. EventKit contract

Files: `core/Sources/PocketCore/ActionPlanner.swift` (`execute`), `app/PocketGlimmer/Actions/SystemActions.swift` (`perform`, `date(from:)`).

- If `when` does not parse, ask "What time?" and write nothing. Remove the now-plus-one-hour default.
- After a successful save, fetch by `calendarItemIdentifier` and return that id in the status string.
- Key a write by skill id, normalized title, and the parsed minute. If that key exists and the item is still in the store, ask before creating another.
- Add undo that deletes only the stored identifier.
- Keep confirm false only when the time parsed and the key is new. Otherwise confirm.

Acceptance, core tests with a fake store:

- "lunch Friday at 1pm" saves once and a second identical request does not save.
- "put lunch on my calendar" with no parseable time saves nothing.
- Undo removes the fetched id and a following find does not return it.
- Denied access returns a permission string and a zero save count.

Device: grant full access, create one reminder, find it in Reminders, undo it, and confirm the system list matches.

### Slice B. Shortcut observation

Files: `SkillTemplate.shortcutURL`, `IOSSkillRunner.runShortcut`, `project.yml` Info.plist, a small `onOpenURL` handler.

- Build `shortcuts://x-callback-url/run-shortcut` with percent-encoded name and text, and an `x-success`, `x-cancel`, and `x-error` on a new app scheme.
- Register that scheme. Do not put secret data in the callback.
- Show returned text as a Shortcut report. Cancellation or an error can occur after earlier actions already ran; stop subsequent steps and say completion is unconfirmed. A missing callback is ambiguous. Do not conclude that nothing happened, or replay the Shortcut automatically.
- Never change the status to "alarm set" or "playing" unless a later, device-proven recipe returns a specific token and the product copy still says the token came from the user's Shortcut.

Acceptance, Linux-side:

- The URL matches Apple's parameter names and encodes spaces.
- A callback for the matching pending attempt yields the decoded `result`; unknown, expired and duplicate attempt tokens are rejected.
- A matching error callback yields `errorMessage` and does not count as success. A custom-scheme callback is not an authenticated external-service receipt.
- The current `shortcuts://run-shortcut` builder stays available for the case where the user has no callback scheme yet, and its copy stays "handed to".

Device: install a one-action shortcut that shows the input text, run it from the app, and see the text come back. Rename it and see `x-error` or the Shortcuts error, not a success row.

### Slice C. Honest messaging and mail digest

Files: `SystemActions.smsURL`, `ComposeSheets`, `Assistant.execute` email branch.

- Prefill a message only through `MFMessageComposeViewController`. If `canSendText()` is false, say the sheet is unavailable. Do not advertise `sms:&body=` as prefilled text.
- For digest, if the inbox was not shared, keep the current Mail share instructions. If text was shared, summarize that text and report its character count. Do not say "last 5 emails" unless five separate items were actually passed in.

Acceptance:

- A unit test of the fallback string does not contain "tap Send" for the sms URL path.
- Digest with an empty inbox returns the share instruction and performs no model call.
- Digest with a fixture of 40 characters reports that length and does not claim a message count.

Device: send one iMessage to yourself and accept only `MessageComposeResult.sent` as the in-app success. Airplane mode after queueing is still not a delivery test.

### Slice D. Draft a workflow

Files: new decoder next to `Skill`, `SkillSetup.userSkillsDir`, no change to `DecisionType` or τ.

- Parse a proposed workflow of allowlisted skill ids and string arguments.
- Reject unknown ids, unknown URL schemes, and native handlers outside `ActionPlanner.executorTools` plus the runner handlers that already exist.
- Show the draft. Save only after the user taps Save. The first run uses the existing confirm rules.
- Muse may fill the draft only through the existing Standard-mode client. Tests use a stub `CloudBrain`. No live key.

Acceptance:

- A draft that contains `instagram_dm` as an auto-run step is rejected.
- A draft of reminder plus calendar find round-trips through JSON.
- Saving does not call `execute`.
- Two saves of the same id replace, they do not duplicate, matching today's registry replace rule.

### Slice E. File postcondition for chart and summary

- After `html_viz` or a document summary, write the HTML or text under Documents and include the filename in the reply.
- If the write fails, say the sheet is on screen and the file was not saved.

Acceptance: a temp-directory test writes the file and a second call with the same content overwrites rather than creating an endless series.

Leave slices 7 through 15 until A through E are in and a device pass exists. Translation and the in-app timer are the first follow-ons because they add checkable outcomes. MusicKit and Focus entitlement wait on an Apple Developer account decision.

## What a real iPhone on 27.0.1 still has to prove

- Signed Release build of this tree with the shipping GGUF and calibration. The last recorded simulator success is an older source commit. [Code] `docs/PROJECT_STATUS.md`.
- The Mom, Sam, and Severance utterances on Metal, against the same τ. CPU letter scores are not phone letter scores.
- Permission prompts: Contacts limited access, full calendar, full reminders, notifications, microphone, camera, photos.
- MessageUI `.sent` versus the sms fallback on a phone with and without SMS.
- Whether `maps://?daddr=` and `photos-redirect://` still open.
- A user-built alarm Shortcut, then x-callback, then the Clock app.
- Apple TV shortcut actions actually present on that tvOS account. Do not film playback from an opened URL.
- Time and memory to load the 808 MB model from a cold start and from `ProactiveTriggerIntent`.
- Apple Intelligence availability for Describe a Shortcut on that model, language, and region.
- That a 27.2 or 27.3 phone was not used if the claim is 27.0.1.

XCUITest, developer device agents, private APIs, and tapping another app's screen are not features of the shipping app. They can be lab tools later. They are not outcomes this product can promise.

## Evidence limits

- Primary pages were fetched for the iOS 27 and 27.0.1 support notes, the versioned iOS 27 Shortcuts user guide (x-callback, run-shortcut, create-shortcut, automations, Use Model), App Intents runtime docs, EventKit access, MessageUI results, UIApplication open, the custom-URL page, the archived Map Links page, Meta's Instagram professional messaging docs, and the 3 Nov 2026 Siri AI developer note.
- Not re-verified in this pass: Uber's current deep-link query, WhatsApp's current click-to-chat page, a 27.0.1-specific `photos-redirect` document, and on-device behavior of every Shortcut action named in `docs/SKILLS.md`.
- Developer documentation updated in late October and early November 2026 describes current SDKs. Where a page does not pin 27.0.1, the map treats it as the public API contract and marks device behavior unverified.
- No secrets, no model calls, no threshold edits, no product edits.

## Verdict

On iOS 27.0.1, Pocket Glimmer can be an honest preparer and a local record-keeper. Six skills can complete a local outcome, two communication skills can see the user's Send tap when the system sheet is available, and the rest are handoffs or text. None of the handoffs are end-to-end until a callback or a system result says so. Describe a Shortcut is the right way for a person to invent a workflow on a capable iPhone, and x-callback plus an allowlisted in-app recipe is the right way for the app to learn it. Siri AI's developer App Intents preview is a 27.3 beta. Muse Spark 1.3 can propose a plan in Standard mode and cannot create the missing iOS access.

**Ranked work:** EventKit ledger, Shortcut x-callback, honest MessageUI, allowlisted workflow drafts, digest honesty, then file output. Translation and an in-app timer are next. Music, Focus write, Maps URL cleanup, and household calendar picking wait on a device.

**Delivered path:** `docs/research/IOS27_CAPABILITY_MAP.md` in the worktree of `d782b81`.

**Evidence limit:** documentation and this commit's source. No iPhone 27.0.1 run.

**Blocker:** the current app still needs a Mac build and a physical iPhone before any skill is called recovered on device. There is no API blocker for slices A through E.
