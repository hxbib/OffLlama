# iOS 27.0.1 end-to-end journeys

Research date: 2026-11-04. Audited tree: `d782b8124011b1dd8940053a206566995e33b1bd`. No product code was changed. No iPhone was available, so nothing below is a device pass.

This report says what Pocket Glimmer can finish on an iPhone running iOS 27.0.1, what it can only hand off, and the smallest slices that make everyday outcomes recoverable. A core unit test, a letter probability, or `UIApplication.open` returning true is not a completed phone task.

## Verdict

Pocket Glimmer is a single-request decision chain with public handoffs. On the current source, the fully closed outcomes are: a local clarification or answer, a memory read or write, a battery and storage reading, an on-device chart from numbers already in the text, and a document or email summary after the user has shared that text. Messages, calls, rides, social DMs, Shortcuts, alarms, timers, Focus, Notes, Music, Spotify, Maps, and Apple TV stop at a system sheet or another app. The app cannot see the outcome after that point.

The Linux CPU rehearsal is not iPhone behavior. At τ = 0.90 it left "Text Mom I'll be home by 8" in clarification (route 0.826, skill 0.810) and stopped "Text Sam I'm running late" on "Which Sam?" (contact choice 0.573). Those scores must be remeasured on the phone. They are not a certificate, and they must not be repaired by lowering τ, editing priors, or retraining.

Three near-term slices close the largest holes without a new model: a durable action journal, an editable draft for an explicit message the model would not accept, and AlarmKit alarms the app can list and cancel. Three longer flows learn workflows as data: a validated user skill, a user-built Shortcut with a callback, and a personal automation the user owns. Muse Spark can draft those instructions. It cannot grant an iOS permission or press Send.

## Evidence classes

| Class | What it may support | What it must not support |
|---|---|---|
| Documented API | Behavior described by Apple or by the vendor's own docs, including availability, permission, and the meaning of a callback | A claim that this app has been seen doing it on iOS 27.0.1 |
| Code | A branch in this commit, with file and symbol | A claim the branch was built, signed, or run on a phone |
| Inference | A conclusion that follows from the API plus the code | A measured latency, a permission-dialog result, or a delivery |
| Device-unverified | A check that needs the later Mac and iPhone session | Any statement that the journey already passes |

Primary platform pages used here:

- [About iOS 27 Updates (UK)](https://support.apple.com/en-gb/149076), published 27 October 2026. iOS 27.0.1 is the bug-fix section (Face ID restart, a 2x photo artifact, Notification Center plus Control Center). The feature list under the heading "iOS 27" is the feature set those fixes sit on. Features listed only under "iOS 27.2", including Siri recall of earlier conversations and Suggestions in Messages, are not 27.0.1 behavior.
- [iOS 27 feature availability](https://www.apple.com/uk/ios/feature-availability/) and the same release note: some features are limited by region, language, and model. Apple Intelligence in the iOS 27 section is described for iPhone 15 Pro, iPhone 15 Pro Max, and iPhone 16 and later. The EU and mainland China sentence on that page is in the 27.2 section. Do not copy it back onto 27.0.1 without the availability page on the day of the device test.
- [Run a shortcut from a URL, iOS 27](https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/10.0/ios/27): `shortcuts://run-shortcut?name=&input=&text=` runs a shortcut already in the user's collection. There is no result parameter.
- [x-callback-url, iOS 27](https://support.apple.com/guide/shortcuts/use-x-callback-url-apdcd7f20a6f/10.0/ios/27): `x-success` appends `result` with the shortcut's textual output; `x-cancel` means the shortcut stopped; `x-error` appends `errorMessage`. Textual output is not proof of a side effect unless that text was produced by the side effect.
- [Open or create a shortcut, iOS 27](https://support.apple.com/guide/shortcuts/open-create-and-run-a-shortcut-apda283236d7/10.0/ios/27): `shortcuts://create-shortcut` opens the editor for a new shortcut. No documented parameter opens "Describe a Shortcut".
- [Add automations, iOS 27](https://support.apple.com/guide/shortcuts/add-automations-apdfbdbd7123/10.0/ios/27): Time of Day, Alarm, Sleep, Arrive, Leave, CarPlay, Email, Message, and the other listed triggers can be set to run without asking, including while locked. Individual actions may still ask. The app cannot create that automation.
- [Use Apple Intelligence in Shortcuts, iOS 27](https://support.apple.com/guide/shortcuts/use-apple-intelligence-in-shortcuts-tpg3vrvwmclv/10.0/ios/27): Use Model is an action inside Shortcuts (On-Device, Private Cloud Compute, or an extension model). It is not an API Pocket Glimmer calls, and it is not a Meta model.
- [AlarmKit](https://developer.apple.com/documentation/alarmkit) is available from iOS 26.0, so it is present on 27.0.1. [Scheduling an alarm](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit) requires `AlarmManager.requestAuthorization()`, and a missing or empty [`NSAlarmKitUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsalarmkitusagedescription) means the app cannot schedule. The sample describes an alarm as able to override Focus and silent mode when necessary. That override is not yet observed on a Pocket Glimmer phone. `schedule(id:configuration:)` returns an `Alarm`. `cancel` removes one. This is an alarm owned by this app, not a Clock app alarm.
- [Accessing the event store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store): full access reads and writes; write-only access creates events and cannot read them back, including events the app created. iOS 17 and later require the matching usage string. This app requests full access for events and reminders.
- [Accessing the contact store](https://developer.apple.com/documentation/contacts/accessing-the-contact-store) and [`CNAuthorizationStatus.limited`](https://developer.apple.com/documentation/contacts/cnauthorizationstatus/limited): the person can share all contacts, a chosen subset, or none. Limited access is changed later in Settings. [`ContactAccessButton`](https://developer.apple.com/documentation/contactsui/contactaccessbutton) can add contacts to that subset. This app does not show that button.
- [Message compose delegate](https://developer.apple.com/documentation/messageui/mfmessagecomposeviewcontrollerdelegate/messagecomposeviewcontroller(_:didfinishwith:)): the callback reports how the person completed the composition interface (cancel, send, or failure). [`canSendText()`](https://developer.apple.com/documentation/messageui/mfmessagecomposeviewcontroller/cansendtext()) is false when the device is not configured to send iMessage, SMS, or MMS. Neither call is a delivery receipt.
- [App Intents runtime](https://developer.apple.com/documentation/appintents/configuring-the-runtime-behavior-of-your-app-intents): `supportedModes` is a preference. `openAppWhenRun` is deprecated in favor of it. An intent's actual foreground or background state comes from `systemContext`. [`requestConfirmation()`](https://developer.apple.com/documentation/appintents/appintent/requestconfirmation()) asks before destructive work and throws if the person cancels.
- [Meta pricing and modes](https://dev.meta.ai/docs/pricing-rate-limits): Standard mode (`muse-spark-1.3`) does not use content to train Meta models. Contributor mode is the separate id `muse-spark-1.3-contributor`. [Models](https://dev.meta.ai/docs/models) say the same. Base URL `https://api.meta.ai/v1`. Muse computer-use recipes are Linux desktop recipes, not iOS control.

`app/project.yml` sets `deploymentTarget` iOS 18.0, `TARGETED_DEVICE_FAMILY` iPhone, and an empty entitlements file. There is no `CFBundleURLTypes`, no `LSApplicationQueriesSchemes`, no AlarmKit usage string, and no background-mode array. The current app tree has not been built on a Mac. The last recorded Simulator success is an older source (`docs/PROJECT_STATUS.md`).

## Request path, as the code does it

`AppModel.send` (`app/PocketGlimmer/AppModel.swift`) refuses a second request while `busy` is true, puts shared text in `SharedInbox` for at most 900 seconds, then calls `Assistant.handle`. The chat array, `busy`, and the pending card live in memory. Killing the app drops them. SQLite keeps facts and telemetry only.

`Assistant.handle` (`core/Sources/PocketCore/Assistant.swift`) does, in order:

1. `rememberOrNot`. A lasting or temporary choice runs `RuleFactExtractor` only. The extractor's patterns are English ("I live in", "I owe", "I'm out of", birthdays, a trip). Other sentences are not stored. `recordCorrection` and `reflexContext` exist on `MemoryStore` and are not called from `handle` or `Reflex.decide`.
2. `route`. Below τ = 0.90 the choice becomes `escalate_cloud` (`OptionSets.route.fallbackID` in `Decision.swift`).
3. `skillOverride` only when a registry exists, the route is not `tool`, and `ActionPlanner.isExplicitRequest` matches. An explicit "text / message / send a message to …" request that the skill chooser rejects does not fall through. Other explicit requests do fall through to the original route when `skillPick` is below τ.
4. On the tool route, `toolChoice`. `shouldUseSkills` runs when the tool is `none`, when `overridable` matches an app word the six tools cannot do, or when `search_memory` was chosen for an explicit non-memory request. A plain "Text Mom …" does not match `overridable`. If route and `send_message` are both at or above 0.90, it stays on the trained tool path.
5. `skillPick` or the trained tool then fills arguments with regular expressions (`SkillArgs.extract`, `ArgumentExtractor.heuristic`). Contacts use `contactPick`, whose below-τ fallback is `ask`.
6. `confirmBeforeAct`. Below τ the fallback is `confirm`. Messages also confirm because `action.tool == "send_message"`. Registry skills confirm when the model says confirm or when `skill.confirm` is true. Load forces `confirm` for categories `message`, `social`, and `email` (`Skill.init` in `Skills.swift`). Reminders, events, alarms, Apple TV, Focus, and notes do not get that force.
7. `execute` / `SystemActions.perform` / `IOSSkillRunner.run`. There is no planner loop, no `timing` decision, and no `notificationTriage` decision on this path. Both decision types exist only for evaluation and the CLI probe.

`offlineCapable` is stored on each skill and is not read by `ActionPlanner` or `IOSSkillRunner`. An offline phone can still be told a shortcut was handed off.

`AppModel.confirm` clears `pending` and sets `busy` before `Assistant.confirm`. A second tap on the same card does not run again. Any thrown error becomes the literal reply "Failed" (`try?` in `confirm`). Cancel only clears the card and appends "Cancelled." Nothing is undone, because nothing was given an identifier.

`ProactiveTriggerIntent.openAppWhenRun` is false and its `perform` calls `AppModel.boot`, which loads the shipping GGUF. `AskPocketGlimmerIntent`, `HandleTextIntent`, and `RunSkillIntent` open the app. `supportedModes` is not set. Whether a locked-iPhone automation can finish an 808 MB load is device-unverified and should be treated as unlikely until measured.

Voice (`VoiceCapture.swift`) uploads audio before the transcript can be checked, then calls `AppModel.send` with no edit step. The transcriber's default `languageBias` is English (`MetaVoiceTranscriber`). Camera and SAM draw an answer or a mask. They do not create a reminder per object (`docs/META_MULTIMODAL.md`).

## Root gaps

1. No dialogue state. A clarification is a string. The next utterance starts at `handle` again, so "yes" does not keep the recipient or the body.
2. No action journal. EventKit saves are not keyed. App death after `commit: true` and before the status line can be followed by a second save.
3. Handoff is reported as the action. `ComposeSheets.open` treats the open callback as success. `shortcuts://run-shortcut` has no callback in the current URL (`SkillTemplate.shortcutURL`). The app registers no scheme that could receive `x-success`.
4. Learned corrections are not applied, and they must not be pasted into the Reflex prompt. That prompt is part of the frozen calibration. Learning has to be a new skill, a stored draft, or a Shortcut the user installs.
5. `timing` never runs, so "every Monday" and "when I leave" become a one-shot reminder phrase or nothing. Recurrence and location stay in Shortcuts, which the app cannot write.
6. Permissions are requested once with `try?` (`SystemActions.requestAccess`) and not checked before a save. Denied, restricted, write-only, and limited access all look like a thrown error or an empty contact list.
7. One in-memory share slot. A newer share replaces the older one. `email_digest` consumes it. Death drops it.
8. Argument parsing is English and brittle. "text mom" does not match the capital-letter name pattern in `ArgumentExtractor`. The skill parser can capitalize a name the tool parser missed. Dates are raw phrases passed to `NSDataDetector` (`SystemActions.date`). Apple does not define how "Friday" or "at 8" resolves. That resolution is device-unverified.
9. The background check-in intent boots the decision model. A morning brief does not need that model to read SQLite and today's events.
10. Cloud drafting cannot add an entitlement, a contact, a Mail inbox, or a tap in Instagram. Meta's computer-use cookbook is a Linux desktop, not this phone.

## Journeys

Sixteen journeys. "Supported now" means the code can reach that state. It does not mean a phone has done so.

### J1. Commuter texts one saved contact

Example: "Text Mom I'll be home by 8".

Supported now: a clarification, or, if both route and `send_message` are at or above 0.90, a confirmation card. The CPU rehearsal took the clarification branch. A phone may take either branch. Do not film a compose sheet until the device reaches it.

Success evidence: for the low-confidence branch, an assistant bubble whose text starts with "Did you mean:" and no present of `MFMessageComposeViewController`. For the high-confidence branch, a card with contact and body, then `ComposeSheets.message` returning "Sent to Mom via Messages", "Cancelled · nothing sent to Mom", or "Messages couldn't send to Mom". "Sent" means the person tapped Send in the system sheet (`messageComposeViewController(_:didFinishWith:)`). It does not mean the message left the phone or was delivered.

Handoff: the system compose sheet. If `canSendText()` is false, `sms:` and then the Shortcut "PG Send Message". Those two report "Opened Messages" or "not confirmed sent".

Missing: the first branch does not keep "Mom" and "I'll be home by 8" for the reply "yes". No delivery observer. No idempotency key if the sheet is abandoned and the user tries again.

Recovery: denied Contacts explains that the lookup cannot run and offers Settings. Limited access that omits Mom says she is not in the contacts this app can see, and the screen offers `ContactAccessButton` or the Settings path. No phone number skips the sheet only when `canSendText()` is false; with a configured Messages account the sheet can still open with an empty recipient, which the user must fix. Ambiguous or lower-case "mom" asks who, and the draft stays editable. Offline still opens the sheet; the status must say the send itself needs the network. App death during the sheet does not auto-present it again; the restored card says to check Messages first. A second tap on the same card is ignored because `pending` is cleared. Two separate requests may send twice; that is a new confirmation, not a silent retry.

### J2. Commuter, two people named Sam

Example: "Text Sam I'm running late". CPU rehearsal: skill confidence 0.989, then contact choice 0.573, reply "Which Sam?".

Supported now: the question "Which Sam?" plus the labels `SystemActions.searchContacts` returns (name, and job or organization when present). No message sheet.

Success evidence: the clarify string lists the candidate labels and `PlannedAction` is not confirmed. After the user replies with one full label, a new turn must resolve that label. Today that reply is a fresh `handle`, so success of the second turn is device-unverified and the code does not special-case it.

Handoff: none until a unique contact is chosen and the user confirms.

Missing: a pending disambiguation record. `contactPick` below τ always asks, even when the argmax was one of the Sams. That is the intended gate. Do not skip it.

Recovery: one of the Sams outside a limited-access set simply does not appear. Say that the list is the set this app can see. Zero matches: "I couldn't find Sam". Renamed contact: the old label fails the next lookup; ask again. Stale label from a card left open overnight: resolve the contact again at confirm time, and stop if the name now matches zero or several people. Duplicate confirm is the same as J1.

### J3. Commuter leave-work message, repeated

Example: "When I leave the office, text Sam that I'm on the train."

Supported now: at most a saved fact if the wording hits `RuleFactExtractor`, plus a one-shot tool or skill plan. `timing` is never consulted. The app cannot arm a Leave automation.

Success evidence for a future version: a visible memory row the user can delete, plus instructions that name the Shortcuts Leave trigger and the Send Message action. Evidence of a sent text remains the Messages sheet or the Messages app, not this app.

Handoff: the user builds or accepts the automation in Shortcuts. iOS 27 documents Leave as a trigger that can run without asking. Send Message may still ask. Both are device checks.

Missing: a background agent. `ProactiveTriggerIntent` must not be the sender. Loading the 1B model in the background is the wrong process, and the app still could not press Send.

Recovery: if the user renames the automation, this app cannot detect it. The stored rule stays until the user deletes it. If they deny Location to Shortcuts, the automation does not run; the app can only say so in the recipe. Duplicate sends are prevented by leaving "ask before running" on for any message action, and by not retrying from Pocket Glimmer.

### J4. Student sets a study alarm

Example: "Wake me at 6" or "Set an alarm for 7:30am".

Supported now: if `skillPick` clears τ and required `time` parses, either an immediate Shortcut handoff or a confirmation card when `confirmBeforeAct` says confirm. `alarm_create.confirm` is false, so a confident "act" opens `shortcuts://run-shortcut` named "PG Create Alarm" with no card. The status is "Handed to Shortcut". A missing shortcut is something the Shortcuts app may say. This app does not receive that sentence.

Success evidence to add: `AlarmManager.schedule` returns, and a later `AlarmManager` query lists that id. Cancelling removes it from that list. That is an AlarmKit alarm. It is not proof that a Clock app alarm exists.

Handoff: until AlarmKit is wired, the user-installed Shortcut. `shortcuts://create-shortcut` only opens a blank editor.

Missing: `NSAlarmKitUsageDescription`, authorization, a countdown or weekly schedule, and a stable id. The deployment target can stay iOS 18 if the call is inside `if #available(iOS 26, *)`.

Recovery: denied AlarmKit authorization leaves no alarm and offers Settings; the Shortcut path is then an explicit fallback with the unconfirmed status. Unparseable "at six" asks "What time?" (`SkillArgs.question`). "at 8" without am or pm must be shown and confirmed, not guessed. Offline AlarmKit scheduling does not need a network. App death after a returned `Alarm` is safe if the id was written to SQLite before the function returned; if the write did not happen, list alarms on next launch and ask before creating another at the same time. A second confirm of the same journal row returns the existing id and does not schedule again.

### J5. Student starts a 25-minute timer

Example: "Start a 25 minute pomodoro".

Supported now: the same Shortcut handoff as J4, name "PG Start Timer", input the duration phrase. No proof the Clock timer is running.

Success evidence to add: an AlarmKit countdown whose remaining state is visible in this app, with pause and cancel. Tell the user it is this app's timer, not the Clock timer, unless a device test shows otherwise.

Handoff: Shortcut fallback only after AlarmKit is denied or unavailable.

Missing: the same authorization and journal as J4. `SkillArgs` duration regex requires a unit ("25 minutes"). "25" alone asks "How long?".

Recovery: a second request while one countdown is running asks to restart or keep the current one. App death resumes from `AlarmManager`'s list, not from the chat. No silent restart.

### J6. Student reminder and calendar

Examples: "Remind me to submit the problem set tomorrow at 5pm". "Put office hours on my calendar Friday at 1pm". "When is my dentist appointment?"

Supported now: `create_reminder` and `create_event` save through EventKit when access allows and `confirmBeforeAct` does not demand a card. `find_event` searches the next 30 days with a word overlap test (`SystemActions.searchEvents`). Several hits go through `eventPick`.

Success evidence: the reminder or event identifier stored by this app, then a read-back of the same title and due date or start date. The status string "Reminder set" is only the return value of `perform`. It is not evidence after a crash. A lookup's evidence is the title and time string returned from EventKit, or the explicit empty sentence.

Handoff: none when full access is granted. Write-only access, if the person somehow has it, can create an event and cannot read it back. This app asks for full access and does not handle write-only as its own state.

Missing: the journal and a confirm step when the date is incomplete. Default duration is one hour (`create_event`). No recurrence. `defaultCalendarForNewReminders()` can be nil; the save then throws and the UI says "Failed".

Recovery: denied or restricted access: do not save; say which Settings row (Calendars or Reminders) and leave the card in place. Revoked after onboarding: the next save fails the same way. "Friday" with no clock time is shown as unresolved and not passed to `NSDataDetector` until the user picks a time. A second identical title and time within the journal asks before adding another. App death uses the "committing" row rule in slice 1. Stale calendar: `EKEventStoreChanged` is not observed; the next lookup reads EventKit again. An event edited in Calendar after the card was built is re-read at confirm time.

### J7. Student summarizes a lecture PDF or a few emails

Examples: "Summarize this PDF". "Summarize my last 5 emails".

Supported now: Mail is not readable. `email_digest` returns the Share instructions unless `SharedInbox.take` has text. A PDF comes from `HandleTextIntent` (the app opens) or from `DocumentPicker` (PDF, plain text, UTF-8). `reason` uses the local model up to 2,500 characters and, above that, Muse Spark only when online, a key exists, and `sensitivity` is `ok`. The text is scrubbed. Contributor model ids are refused.

Required success evidence: the summary bubble and the outgoing payload for a cloud call. The audited `reason` path returns plain text through `execute`, so the chat does not receive the cloud-prompt record that ordinary text escalation provides. That transparency gap remains to fix. Absence of a network request is the evidence for a sensitive or offline document. An empty picker cancellation returns no summary.

Handoff: Mail's share sheet and the user-built Shortcut "PG Share Emails", which must call `HandleTextIntent`. The app cannot check that the Shortcut exists.

Missing: no inbox grant will appear. Word files are unsupported. The share slot holds one item.

Recovery: cancelled picker says nothing was opened. A share older than 15 minutes is ignored. A second share replaces the first; the summary names the source and length so the user can see which one was used. Offline or no key: local window plus the sentence that the rest was not read. Sensitivity "sensitive", or the photo lexical floor for a pictured page: no upload. App death drops the share; the user shares again. The summary is not an action, so duplicate taps only repeat a read.

### J8. Caregiver morning brief

Example: a Time of Day automation calls "Pocket Glimmer check in" with kind `morning`.

Supported now: `ProactiveEngine.morningBrief` reads the task board and `SystemActions.eventsOn`, then `nudgeNow`. One brief per local day is stored in `memory_meta`. The intent posts a local notification. `nudgeNow` below τ skips, and a later trigger may retry because the day key is set only after a "nudge" choice.

Success evidence: a notification whose body matches the events and tasks read that morning, plus the meta key. No notification when the board and the calendar are empty.

Handoff: the user creates the automation. The app does not.

Missing: a path that does not load the GGUF. Notification authorization is requested with `try?` and a failed `add` is ignored.

Recovery: denied notifications: still return the brief text to Shortcuts, and say notifications are off. Denied calendar: the brief omits events and says calendar is unavailable, rather than failing the whole trigger. Model load failure: post the SQLite and EventKit lines without a nudge decision, or skip quietly and record the error. Do not retry in a loop. Stale "already briefed" after a timezone change: key by the local calendar day, which the code already does via `MemoryStore.day`. Duplicate automations the same day return no second brief.

### J9. Caregiver shopping nudge

Example: the user says "I'm out of bread", later a Shortcuts Arrive automation at a grocery store calls the trigger with the place name.

Supported now: the extractor can store `needs_to_buy` for "I'm out of …". `ProactiveRules` matches a place against a fixed English list (store, market, grocery, and a few shop names) and then asks `nudgeNow`. The result is a notification draft, not a reminder and not a message.

Success evidence: the notification text contains the stored item and the place string Shortcuts passed. A place that does not match the list produces no nudge.

Handoff: Arrive is the user's automation. Location permission belongs to Shortcuts, not to this app. This app has no location usage string.

Missing: the shop list will miss a local market whose name is not in the regex. No "I bought it" action clears the fact automatically.

Recovery: the user can forget the fact in Memory. A revoked notification permission follows J8. If the automation runs twice at the same store, two nudges can post today; slice 1 should suppress the same fact id and place for the rest of the local day. App death is fine because the fact is in SQLite. The model is not required to remember the item if the extractor stored it.

### J10. Working person emails a colleague

Example: "Email Dana the slides are ready".

Supported now: confirmation is forced by the email category. `SystemActions.perform` case `send_email` uses `MFMailComposeViewController` when `canSendMail()` is true. The delegate maps sent, saved draft, cancelled, and failure. Otherwise `mailto:`.

Success evidence: one of the four Mail delegate strings. "Saved as a draft" is not sent. `mailto:` opened is not sent.

Handoff: the Mail sheet. There is no Gmail API. "gmail" is only an alias that still opens Mail.

Missing: a subject line unless the utterance contains "subject …". The body parser may swallow the subject into the body. No attachment.

Recovery: no Mail account: say Mail is not configured and do not claim a send. Several Danas: same as J2. Denied contacts: ask for an address, do not invent one. Offline: the sheet can still open and queue in Mail; the status should not say "sent" until the delegate says so. App death follows J1. Duplicate: the same card cannot send twice; a second request requires a new confirm.

### J11. Working person checks the day, then silences the phone

Examples: "What's on my calendar today?" "Turn on Do Not Disturb." "Turn on Low Power Mode."

Supported now: calendar lookup as in J6, but only through the next-30-days search, not a dedicated "today" query, unless the morning brief path is used. Focus and Low Power are Shortcuts "PG Toggle Focus" and "PG Toggle Low Power". `device_status` can read `ProcessInfo.processInfo.isLowPowerModeEnabled`. Nothing in this process can set Focus or Low Power. There is no public third-party setter in the APIs reviewed. Shortcuts is the system-owned place for those actions.

Success evidence: for calendar, the event lines. For Low Power, a later `device_status` read that changed. For Focus, no evidence is available to this app. The Shortcut open callback is not evidence.

Handoff: the named Shortcut, which the user must have built with the system action. A missing Shortcut is unobservable here.

Recovery: denied calendar as in J6. A renamed Shortcut needs the x-callback error in slice 3 before the app can say it is missing. Toggling twice is two handoffs; the app must not claim the final on or off state for Focus. Low Power can be re-read. Offline does not matter for the toggle. App death leaves the system setting as it was; do not toggle again on launch.

### J12. Working person charts numbers they typed

Example: "Make a chart of these numbers: rent 1200, food 400, transit 130".

Supported now: `HTMLViz.pairs` parses label and number pairs, `IOSSkillRunner` presents a `WKWebView` with JavaScript disabled, and the status says how many bars. The 1B may write a short title. No network.

Success evidence: the sheet is on screen and the bar count matches the parsed pairs. Dismissing the sheet does not delete the numbers. Sharing the HTML is optional and is not a send to another person.

Handoff: none.

Missing: no general spreadsheet, no axes the user edits, no chart from a photo unless a share or OCR text was already placed in the inbox. A pictured chart is a vision question, not this renderer.

Recovery: no numbers: "No numbers to chart" and no sheet. A stale share is used only when the utterance itself has no pairs (`execute` peeks the inbox). Show the source line in the sheet title so a stale share is visible. App death drops the sheet; the utterance can be repeated because the chart is pure and has no side effect. Duplicate presents are harmless.

### J13. Creator or traveler plays something

Examples: "Open the latest episode of Severance on Apple TV". "Play lofi on Spotify". "Play some music".

Supported now: Apple TV is the Shortcut "PG Play on Apple TV" with the show name, or, if Shortcuts will not open, `https://tv.apple.com/search?term=`. Spotify is `spotify:search:{query}`. Music is `music://`, and the query is ignored. None of these report playback. The CPU rehearsal planned `appletv_play` and asked for confirmation. `appletv_play.confirm` is false, so a later run whose `confirmBeforeAct` says "act" above τ will open the Shortcut without a card.

Success evidence: there is none for playback. The honest status is the handoff sentence already in `IOSSkillRunner`. A search page is not an episode.

Handoff: Shortcuts, the TV app, Spotify, or Music. The user finishes.

Missing: a documented public playback callback. Do not add one by tapping the screen. MusicKit could play a library item after a separate authorization; that is a different project and still would not cover an arbitrary show.

Recovery: missing Shortcut: keep the search-page fallback and say playback was not started. Spotify or Music not installed: the open callback is false and the current copy says the app is not installed or the link was refused. Wrong show name: the user sees the search field, which is the recovery. Offline: do not say the Shortcut ran. Duplicate: a second confirm opens the app again; it must not be described as "still playing". App death needs no undo.

### J14. Traveler directions and a ride

Examples: "Directions to Hunter College". "Get me an Uber to JFK".

Supported now: Maps opens `maps://?daddr=`. Uber opens `uber://?action=setPickup&pickup=my_location&dropoff[formatted_address]=` after a forced confirm. Neither is navigation started or a ride booked. Uber spends money only after the user confirms inside Uber.

Success evidence: the open callback plus the status "Opened …". For Uber the confirmation card must show the drop-off string before the open.

Handoff: Maps or Uber. If Uber is absent, the open fails and nothing is booked.

Missing: a place disambiguation. "Springfield" is sent as typed. No price quote. The Uber parameter contract in `builtin.json` was not re-verified against Uber's current docs in this pass; the device test must confirm the app still accepts it.

Recovery: empty place asks "Where to?". Denied network: Maps may open offline maps or fail; report only the open result. A second Uber confirm is a second open, never a background retry. App death after the open does not reopen Uber on launch. The user checks the Uber app before requesting again.

### J15. Traveler or language learner translates

Example: "Translate good morning to Spanish". A spoken version uses the mic.

Supported now: `translate` is `cloudReason(.generation)`. Short text stays on the 1B. Longer text can escalate under the sensitivity rule. Voice never reaches this path until Muse Voice Transcribe returns text, and that audio has already left the phone. The transcript is not shown for editing. `languageBias` defaults to English.

Success evidence: the translation text in the bubble, marked on-device or with the provider line. For voice, the system line with duration and "recording deleted" or "kept". A wrong transcript that is then translated is still a completed pipeline and a failed user outcome.

Handoff: none for typed text. Voice hands audio to Meta.

Missing: an edit-before-decide step. No on-device speech recognizer. Skill arguments remain English even if the translation skill can emit another language. "Envíale a Mamá que llego a las 8" will not reliably hit `imessage_send`.

Recovery: offline voice records nothing and says so (`MicButton.begin`). Denied microphone says Settings. `voice_stays_on_device` blocks upload. A failed transcribe says nothing else was sent. The user can type the corrected line. Do not retry the audio automatically. A sensitive sentence takes the local answer path and is not a translation excuse to upload.

### J16. Accessibility: ask without a precise tap, and keep a photo private

Examples: VoiceOver user activates "Hold to talk". Switch Control or a motor user cannot hold. "What's on this whiteboard?" with photos set to stay on device. Voice Control and VoiceOver image descriptions in iOS 27 are system features ([release note](https://support.apple.com/en-gb/149076)); they are not this app's model.

Supported now: Confirm and Cancel are SwiftUI buttons with visible titles. The mic control has an accessibility label, and the gesture is press-and-hold (`DragGesture`). A photos-stay-on-device choice refuses the upload before the network. SAM masks stay on screen. They are not actions.

Success evidence: VoiceOver can activate Confirm, Cancel, and a typed send without a drag. The mic, as written, requires a hold, so a user who cannot hold does not have a supported voice path. The photo path's evidence is the kept-on-device badge and no payload.

Handoff: system VoiceOver, Voice Control, and Zoom. This app does not need to reimplement them. It does need controls they can activate.

Missing: a tap-to-talk toggle, a typed equivalent that is focused by default, Dynamic Type audit, and a transcript editor. No evidence in this pass of contrast or caption behavior.

Recovery: denied camera or photos: the glimpse does not upload and says why. Denied microphone: J15. A photo of a receipt or an id hits the lexical floor even if the model says ok. App death discards the in-memory glimpse; the photo in the library is untouched. Duplicate "Find" only redraws.

### Social DMs, calls, and charts of private inboxes

Instagram (`https://ig.me/m/{handle}` plus clipboard), X (profile URL plus clipboard), and WhatsApp (`whatsapp://send?text=`) are confirmed handoffs. The status strings in `IOSSkillRunner.openURLSkill` are the contract. Paste-and-send, a chosen chat, and a tapped Send are the user's. Opening the URL does not prove any of those. `instagram_autoreply` stores a memory and tells the user that no app can answer Instagram. A call uses `tel:` after confirm and a contact phone lookup; iOS shows its own prompt. FaceTime uses `facetime:`. Those prompts are the handoff. The app does not receive a connected-call callback.

## Acceptance matrix

Run this on a signed Release build of this tree, with the shipping GGUF and calibration, on iOS 27.0.1. Record the build, the phone model, the region, and whether Apple Intelligence is available. A Simulator pass is not a substitute for the sheet, the alarm, or the Shortcut callback.

| ID | Setup | Steps | Pass |
|---|---|---|---|
| A1 | Contacts has one Mom. Messages configured. | Send "Text Mom I'll be home by 8". | Either a "Did you mean" bubble and no sheet, or a confirm card. Record which, and the decision scores. Do not mark a send. |
| A2 | Continue A1 if it clarified. | Reply "yes". | Today this may forget the body. After slice 2, an editable card shows Mom and the body, and nothing opens before Confirm. |
| A3 | Two Sams. | "Text Sam I'm running late", then pick one, then Cancel. | The question lists both labels. Cancel sends nothing. |
| A4 | Limited contacts, Mom excluded. | Same as A1. | No sheet. The copy says Mom is outside the shared set. |
| A5 | Contacts denied. | Same as A1. | No lookup crash. A Settings path. No invented number. |
| A6 | Full contacts, one Mom. | Confirm, tap Send, then repeat the request and Cancel. | Delegate string is the sent variant. The second card does not send. Messages shows one thread action from the first tap. |
| A7 | `canSendText()` false, if a device can be put in that state. | Confirm a text. | Status is the sms or Shortcut fallback, and it does not say sent. |
| A8 | Reminders denied. | "Remind me to submit the problem set tomorrow at 5pm". | No reminder is created. The error names Reminders. The card can be tried again after access is granted. |
| A9 | Reminders allowed. | The same request twice. | After slice 1, the second attempt asks before creating a duplicate. Kill the app on the card and relaunch: the card is still there and still uncommitted. |
| A10 | Calendar has a dentist event. | "When is my dentist appointment?" | The returned line matches Calendar. Rename the event, ask again: the new title appears. |
| A11 | No "PG Create Alarm". | "Wake me at 6:30am". | Today: a handoff sentence, not "alarm set". After slice 3: an AlarmKit row that lists and cancels, or a denial message and no row. |
| A12 | AlarmKit allowed. | Schedule 6:30, kill the app, relaunch, schedule 6:30 again. | One alarm for that journal row. |
| A13 | Mail share of two messages, then a second share. | Summarize. | The summary corresponds to the latest share, and the UI says which. Airplane mode does not upload. |
| A14 | PDF with no text. | Analyze document. | "No text found" or an empty result. No crash. |
| A15 | Morning automation, notifications denied. | Fire the trigger once, then again the same day. | First result explains notifications or posts one brief. Second result does not duplicate the day. |
| A16 | User skill file and a renamed Shortcut. | Run the weather or note shortcut. | Today the app cannot tell rename from success. After the callback slice, `x-error` or a timeout stays unconfirmed, and `x-success` shows the returned text only. |
| A17 | Uber not installed. | Confirm a ride request. | Open failure. No second automatic open. |
| A18 | Voice, English, online. | Hold, speak, release. | Transcript is visible before any tool runs, after the voice slice. A sensitive phrase is not uploaded as a Spark prompt. Audio upload for transcription still happens only if the user left voice upload on. |
| A19 | `photos_stay_on_device`. | Ask about a photo. | Kept on device. No payload. |
| A20 | Apple Intelligence device and a non-Intelligence device, if both exist. | Follow the in-app "describe a shortcut" instructions. | The Intelligence device can complete creation inside Shortcuts. The other device still gets the manual action list. This app never marks the workflow installed until the user types the name and a test callback returns. |

## Near-term slices

No slice changes the GGUF, the priors, τ, the prompt, or test120. No slice adds Fireworks or a contributor model id. No slice uses a private API, a screen tap, or XCUITest as the product.

### Slice 1. Action journal

Outcome: a reminder, event, message sheet, or URL handoff can be killed, relaunched, denied, and repeated without a second irreversible effect.

Work: a SQLite table keyed by a UUID, with states `draft`, `awaiting_user`, `committing`, `sheet_open`, `completed`, `cancelled`, and `failed`. `AppModel` writes `awaiting_user` when it shows a card and restores those rows in `boot`. `confirm` moves to `committing` or `sheet_open` before the side effect. EventKit saves store the UUID in the reminder or event notes, or in the app's row together with `calendarItemExternalIdentifier` after save. If launch finds `committing`, it does not save again; it asks the user to look at Reminders or Calendar. If it finds `sheet_open`, it restores the card and says to check Messages or Mail before sending again. `AppModel.confirm` surfaces the thrown error text instead of "Failed". `SystemActions` checks `EKAuthorizationStatus` and `CNAuthorizationStatus` first and returns a fixed sentence for denied, restricted, write-only, and limited. The same title and time already in `completed` asks before a second save. URL opens are not retried by `boot`.

Expected result: A9 and A6 pass. A8 shows the permission sentence.

Out of scope: changing when the model asks for confirmation, and any new entitlement.

### Slice 2. Editable draft when an explicit message is below τ

Outcome: "Text Mom I'll be home by 8" can become a message only after the user sees and confirms the parsed recipient and body. The model is not treated as having accepted the action.

Work: when `planSkillCore` or `toolPath` returns clarify for `isExplicitMessageRequest`, and `ArgumentExtractor` or `SkillArgs` produced a contact and a body, store a `draft` journal row and render those fields in text fields. The card says the model was not confident enough to choose this and that the user is confirming a draft. Confirm runs the existing `send_message` path, including a fresh contact search. "Which Sam?" stays a required step and writes the chosen label into the draft. Any utterance that is not a choice of the offered skill or a field edit cancels the draft. Do not call `Reflex.decide` again to promote the original utterance. Do not lower τ.

Expected result: A1 followed by an edit and Confirm can reach the Messages sheet on a phone where the model stays below 0.90. A2 passes. A3 still cannot send before a unique person is chosen.

Out of scope: non-message skills, prompt injection of past corrections, and any change to calibration.

### Slice 3. Alarms the app can see, and Shortcut callbacks for everything else

Outcome: "Wake me at 6:30am" creates an alarm this app can list and cancel. A Shortcut handoff reports callback text, cancellation, error, or timeout, and never reports playback or a Clock alarm.

Work: add `NSAlarmKitUsageDescription`. Behind `if #available(iOS 26, *)`, request AlarmKit authorization and schedule a one-shot or weekly alarm, or a countdown, with a UUID. Persist the id in the journal. Cancel uses `AlarmManager`. If authorization is denied, fall back to the existing Shortcut and say the Clock shortcut was not confirmed. Register one custom URL scheme. Build `shortcuts://x-callback-url/run-shortcut` with a per-run nonce in `x-success`, `x-cancel`, and `x-error`. Ignore a callback whose nonce is not the open row. Time out back to "not confirmed". Set `confirm: true` on `appletv_play` so a confident "act" cannot open that Shortcut without a card. Leave τ alone.

Expected result: A11 and A12 pass on a phone that grants AlarmKit. A16 passes for a Shortcut that ends by returning text. An Apple TV callback that returns text still does not pass a playback test.

Out of scope: raising the deployment target, MusicKit, and any claim about Focus or silent-mode override until the device test records it.

## Longer flows

These are user-installed workflows. They are not a new general agent and not a weight update.

### L1. A skill the user accepts

Parent review: the category-based confirmation rule below is insufficient for learned JSON, which can lie about its category or replace a built-in id. Use the compiled capability policy in [LEARNED_WORKFLOWS.md](LEARNED_WORKFLOWS.md); the model cannot choose effects, permissions, confirmation requirements or native handlers.

The user describes a repeated outcome. If the request is not sensitive, the app scrubs it and asks `muse-spark-1.3` in Standard mode for one skill JSON object. `SkillRegistry` decoding and the category confirm rule validate it. Invalid JSON is shown and not written. Valid JSON is written under Files › Pocket Glimmer › Skills only after Confirm, then the registry is reloaded. The new skill is retrieved like any built-in. If the invocation is a URL or a Shortcut, the card repeats the handoff limit. A message, social, or email skill confirms even if the model wrote `"confirm": false`.

Expected result: a sensitive description makes no network call. A good JSON file changes the next `skillPick` candidate list. A bad file leaves the registry unchanged. No GGUF change.

Boundary: Muse is not given contacts, photos, or a tool that opens URLs. One proposal per confirm. No contributor id and no Fireworks.

### L2. Describe a Shortcut, then prove the name

Apple's iOS 27 release note says Describe a Shortcut creates or refines a shortcut in natural language on Apple Intelligence devices. The Shortcuts URL guide does not offer a parameter that opens that interface. `shortcuts://create-shortcut` opens an empty editor. This app should show the sentence to type, open that editor, and say that creation happens in Shortcuts. On a device where the feature is absent, show the manual actions instead. When the user returns, they type the name they saved. The app stores a user skill with that exact name and runs one callback test. Only `x-success` marks the workflow as installed, and the stored result text is the only success evidence.

Expected result: A20. A renamed shortcut fails the next test and the skill is marked unconfirmed. The app never writes a `.shortcut` file, because no reviewed API gives this process that ability.

Boundary: do not send the user's messages or contacts to Muse to invent the Shortcut. A local template is enough for the alarm, note, weather, and leave-work recipes. Muse drafting is optional and uses L1's privacy gate.

### L3. A commute or care routine the user arms

The app stores a plain rule: trigger kind, place or time, contact, and body. It shows the iOS 27 automation steps, including the warning that Leave, Arrive, Time of Day, and Message can be set to run without asking, and that a message action should keep asking. The recommended action inside Shortcuts is the system Send Message or Show Notification action, not `ProactiveTriggerIntent`. A new lightweight intent may read SQLite and post a notification without loading the GGUF. It must not send a message. The user deletes the rule in Memory.

Expected result: J3 and J9 can be followed by a person who has never edited a Shortcut, and Pocket Glimmer's process never places the message. A duplicate Arrive on the same day does not post the same fact twice.

Boundary: no location entitlement, no always-on process, and no model load on the locked-phone path.

## What the device session still has to measure

- Letter scores and wall-clock time for J1 and J2 on the shipping GGUF. The CPU numbers are not expected to match.
- Peak memory of a cold `ProactiveTriggerIntent` and of a foreground `boot`.
- `NSDataDetector` results for "tomorrow at 5pm", "Friday", and "at 8" in the phone's locale.
- Whether a missing Shortcut produces an `x-error` this app can read, and the exact `errorMessage`.
- Whether AlarmKit alerts while Focus and silent mode are on.
- Whether Mail and Messages "sent" can be observed when the phone is offline.
- The live Uber URL, the TV search fallback, and a user-built Apple TV Shortcut. Playback stays unproven.
- Describe a Shortcut's actual screen on 27.0.1, in the test region, on one Intelligence device and one device where the feature is unavailable.
- VoiceOver on the mic hold, and a large Dynamic Type pass on the confirm card.
- Limited-access contacts after the set is edited in Settings while the app is suspended.

## Blocker

There is no signed build of this tree on a Mac, and no iPhone run. The journal, the draft card, and AlarmKit are specified so they can be implemented before that session. They are not implemented in this commit. Until A1 through A20 are run on iOS 27.0.1, the product has no end-to-end phone result to claim.

## Ranked findings

1. The product loop ends at a handoff. URL-open success, Shortcut launch, and a local decision score are not task success.
2. Explicit messages below τ throw away a parse that the user could have confirmed. That is why the Mom rehearsal cannot be completed without a new utterance the model may also reject.
3. Pending work and shares die with the process, and EventKit writes have no identity, so retry duplicates them. Confirmation errors are replaced with "Failed".
4. Alarms, timers, Focus, Notes, weather, and Apple TV depend on Shortcuts the app cannot see. AlarmKit is the public way to close alarms and countdowns on iOS 27.0.1.
5. `x-callback-url` is the public way to observe Shortcut text, cancellation, and errors. The app does not use it and has no callback scheme.
6. `timing`, `notificationTriage`, `recordCorrection`, and `reflexContext` are unwired. Wiring corrections into the Reflex prompt would move the frozen calibration. Learn by storing skills and rules instead.
7. The morning-brief intent loads the full local model in a mode that is allowed to run in the background. Split a no-model notification path before relying on it.
8. Contacts limited access, write-only calendar access, and revoked permissions are not first-class states.
9. Voice and non-English requests have no edit step, and the skill grammar is English. iOS 27 system accessibility features do not remove the hold-to-talk gap.
10. Muse Spark Standard mode is a drafter for L1 and L2. Contributor mode, Fireworks, and Meta computer-use are out of the product. Cloud text does not create iOS access.

Delivered path: `docs/research/IOS27_END_TO_END_JOURNEYS.md`.
