# Learned workflows

Research note, 2026-11-04. Base commit `d782b81`. No product code in this pass. No paid Meta call. No iPhone build. The current tree’s deployment target is iOS 18.0 (`app/project.yml`). iOS 27.0.1 behavior below is from Apple’s documents, not from a run of this app.

Pocket Glimmer can learn a workflow only as a reviewed, versioned list of capabilities it already knows how to call and how to receipt. Muse Spark can propose that list. It cannot add an iOS permission, see another app’s screen, or turn a URL open into proof that a message was sent, a Shortcut ran, or playback began.

## Verdict

Build a small PocketCore workflow store whose effect rules are compiled, whose runs survive process death, and whose irreversible steps are never replayed after an ambiguous start. Keep the frozen 1B model, τ = 0.90, and the 36-skill registry as the single-step path. Promote a multi-step flow only after the user reviews a concrete card. Use Muse Spark 1.3 Standard solely as an untrusted planner when the local matcher cannot bind a request. Leave Describe a Shortcut, x-callback results, and personal automations as user-owned Shortcuts, with textual callbacks recorded as handoffs.

The smallest implementable slice is `Workflow.swift` plus Linux tests. It does not need the phone, a new model decision, or a network call.

## What the code does on one request

`Assistant.handle` (`core/Sources/PocketCore/Assistant.swift`) is one utterance in, one reply out. It may remember a fact, pick `route`, and either answer, escalate, or plan a single tool. `ActionPlanner.planSkillCore` retrieves at most seven skills, asks one `skillPick` letter pass, fills arguments with regexes, optionally disambiguates a contact, and returns one `PlannedAction` or a clarification. There is no step list, no run id, and no stored outcome.

Confirmation lives on a `ChatItem.pending` value in `AppModel.chat` (`app/PocketGlimmer/AppModel.swift`). That array is process memory. `confirm` clears `pending` and calls `Assistant.confirm`, which calls `execute` immediately. `cancel` drops `pending` and appends “Cancelled.” Killing the app drops the card. A second `send` while `busy` returns “I'm working on another request” and does not queue work.

Receipts that exist today:

| Call | What the code records | What that proves |
|---|---|---|
| `EKEventStore.save` for a reminder or event (`SystemActions.perform`) | Success string, or a thrown error. The calendar item identifier is not stored. | A local write was attempted. Undo is not possible from the stored result, because the identifier was discarded. |
| `MFMessageComposeViewController` delegate (`ComposeSheets.message`) | `.sent`, `.cancelled`, or the default branch. | The user finished the system sheet. `.sent` means Messages accepted the compose action. It is not a delivery receipt. The sheet is in-process; death before the delegate leaves no row. |
| `MFMailComposeViewController` delegate | `.sent`, `.saved`, `.cancelled`, or failure. | Same shape for Mail. A saved draft is not a sent message. |
| `UIApplication.shared.open` (`ComposeSheets.open`) | `Bool`. `IOSSkillRunner` turns `true` into “Opened …”, “Handed to Shortcut …”, or “iOS is asking to call/FaceTime …”. | The system accepted the URL. Instagram, X, WhatsApp, Uber, Maps, Music, and `shortcuts://run-shortcut` stop here. |
| `appletv_play` (`IOSSkillRunner.run`) | The Shortcut handoff string, or a TV search URL if Shortcuts itself did not open. | A handoff was attempted. The skill note in `BuiltinSkills` says playback is unverified. |
| `SharedInbox` | In-memory text, 15-minute expiry, consumed by `take()`. | Text the user shared into this process. It is gone after expiry, after a reader takes it, or after the process dies. |
| `TelemetryLog` | Decision type, choice, confidence, context, option ids. | The letter decision. Not argument quality, not execution, not delivery. |
| `MemoryStore` | Facts the rule extractor pulled from the utterance, plus an autoreply sentence. | What the user said, in a narrow grammar. Not a trace of other apps. |

`skill.confirm` is forced for categories `message`, `social`, and `email` (`SkillCategory.reachesOtherPeople`, reapplied in `SkillRegistry.init`). Call, FaceTime, and Uber set `confirm: true` in `BuiltinSkills`, but that flag is data. A user JSON file in Documents/Skills that reuses an id replaces the built-in (`SkillRegistry.merge`). A replacement whose category is `web`, `phone`, `shortcuts`, or `device` can set `confirm` false. `planSkillCore` then confirms only when `confirmBeforeAct` chooses `confirm`. `TakeoverRegressionTests.testAppleTVNonToolRouteReachesRegisteredSkill` scripts that decision to `act` and expects `.acted` with no confirmation. The real CPU rehearsal asked for confirmation on Apple TV because that run’s `confirmBeforeAct` chose `confirm` (`docs/ENGINE_REHEARSAL_NOV4.md`). The hard rule and the model are different gates. A learned flow needs the hard rule.

The real CPU rehearsal, same model and τ = 0.90, did not execute “Text Mom I'll be home by 8” (route 0.826, skill 0.810, clarification). “Text Sam I'm running late” asked “Which Sam?”. “Open the latest episode of Severance on Apple TV” planned `appletv_play` and asked for confirmation. Those are Linux CPU results with fixture contacts and a recorder. They are not phone measurements. A saved workflow must not depend on that message clearing τ, and must not lower τ.

`CloudBrain.complete` posts `chat/completions` and reads `choices[0].message.content`. A `tool_calls` payload with null content becomes `CloudError.decode`. `MetaAPI.requireStandardMode` rejects model ids containing `contributor`. `CloudSettings.chain` builds Meta first and ignores a stored Fireworks key. A custom BYOK brain is still appended when the user configured one. Workflow planning must not follow that chain.

There is no background-task identifier, no background mode, and no `CFBundleURLTypes` entry. Entitlements are an empty dictionary. The app cannot resume itself, and it cannot receive an `x-success` URL until a scheme is declared.

## What this process can observe

These are inputs the current types already accept:

- The utterance string passed to `Assistant.handle`, including text from `AskPocketGlimmerIntent`, `RunSkillIntent` (a fixed `QuickSkill` phrase plus an optional details string), and `HandleTextIntent`.
- Share-sheet or Shortcut file bytes that `HandleTextIntent` turns into a string: PDF via PDFKit, or UTF-8. The source string is whatever the Shortcut author passed (`"share"` by default, `"mail"` in the documented PG Share Emails recipe).
- `ProactiveTriggerIntent` fields: trigger kind, place, sender, and text. `openAppWhenRun` is false. The engine posts a local notification. It does not perform a skill.
- The string those intents return to Shortcuts. That is an output from this app. A later action in the user’s Shortcut can pass it somewhere else. This app is not called back unless the Shortcut invokes an intent again.
- Contact and event candidate strings from `CNContactStore` and `EKEventStore`, after the user has granted access. `searchContacts` returns display names, not `CNContact.identifier`.
- The user’s Confirm or Cancel tap, while the process still holds the `ChatItem`.
- Decision rows and memory facts already written to `pocket.sqlite`.
- Skill JSON the user put in Files. Treat it as untrusted capability data. See the registry rules below.

An explicit demonstration, in this design, means the user completes a real run and then saves that run’s capability ids and bound arguments. The trace is the run record, not a screen recording.

## What this process cannot observe

- Pixels, view hierarchies, or controls of another app. XCUITest, private accessibility automation, and agent-device tapping are development tools. They are not a shipping capability of this prototype.
- Whether a Shortcut’s internal actions ran, unless Shortcuts calls back. The current runner does not request that callback.
- The action graph of a Shortcut, including one the user just created with Describe a Shortcut.
- The list of installed Shortcuts. No such query exists in the app, and the iOS 27 URL-scheme pages document open, create, and run by name, not enumeration.
- Mail, Messages, Instagram, X, or WhatsApp contents, except bytes the user shares or parameters the user wires into an intent.
- Siri’s on-screen awareness. Apple lists that under Siri AI for Apple Intelligence devices (`https://support.apple.com/en-us/149076`, section iOS 27). It is system software.
- Notification text, unless a Shortcut the user built passes that text into `ProactiveTriggerIntent` or `HandleTextIntent`.
- Carrier delivery, Uber trip acceptance, Apple TV playback, or music playback.

Cloud text cannot widen this set. A plan that names `tap_send` or `read_instagram` fails validation because those ids are not in the compiled registry.

## iOS 27.0.1, from Apple’s documents

`https://support.apple.com/en-us/149076` (published 2026-10-26; the en-gb URL for the same article number did not return a body in this pass) splits releases:

- **iOS 27.0.1** is bug fixes: iPhone 18 Pro Face ID restart, a 2x photo artifact on some of those phones, and a touchscreen stall if Notification Center and Control Center open together. No Shortcuts change is listed.
- **iOS 27** is the feature release underneath that bug-fix update. Describe a Shortcut, Siri AI, and the Shortcuts changes below are documented there, with device, language, and region gates.
- **iOS 27.2** is a later section on the same page, and on `https://support.apple.com/en-nz/149045` (published 2026-10-30). It adds Siri conversation memory, Suggestions in Messages, an iPhone Duo open/close automation, more Use Model web languages, and a macOS menu item named “Show Describe a Shortcut”. None of that is 27.0.1 behavior.

The versioned Shortcuts User Guide used here is iOS 27, guide version 10.0:

- `https://support.apple.com/en-euro/guide/shortcuts/apdfbdbd7123/10.0/ios/27`
- `https://support.apple.com/en-om/guide/shortcuts/apdfbdbd7123/10.0/ios/27`

The iPhone guide URL `https://support.apple.com/guide/iphone/shortcuts-iph47e1c9d7d/27/ios/27` returned a shell without the article body. Shortcuts conclusions use the versioned Shortcuts guide, which did load.

### Describe a Shortcut

`https://support.apple.com/en-euro/guide/shortcuts/apd84c576f8c/10.0/ios/27` tells the user, on an Apple Intelligence-enabled iPhone 15 Pro, 15 Pro Max, or iPhone 16 or later, to tap Add in Shortcuts and describe the shortcut in ordinary language. Shortcuts creates and names it. The user can describe a change or edit the actions. The same page says Apple Intelligence is not available in all languages or regions and that usage limits may apply. The iOS 27 notes at `https://support.apple.com/en-nz/149045` put the same editor feature under iOS 27, not under 27.2, and point at Apple Intelligence terms (`https://support.apple.com/148587` redirects to the usage terms, which allow Apple to throttle unreasonable or automated use).

`shortcuts://create-shortcut` is documented as opening a new editor (`https://support.apple.com/en-euro/guide/shortcuts/apda283236d7/10.0/ios/27`). The page documents no description query parameter. This app can open that URL and can copy a suggested description to the pasteboard, which it already does for Instagram. It cannot submit the description, read the generated actions, or know the name Shortcuts chose. Running the result still requires the user to tell Pocket Glimmer the exact name, then a separate handoff. Do not auto-run a Shortcut that Describe just created.

### Running a Shortcut and hearing back

`https://support.apple.com/en-euro/guide/shortcuts/apd624386f42/10.0/ios/27` documents:

`shortcuts://run-shortcut?name=[name]&input=text|clipboard&text=[text]`

`UIApplication.open` completing `true` means the URL opened. The page does not define a result channel on this URL.

`https://support.apple.com/en-euro/guide/shortcuts/apdcd7f20a6f/10.0/ios/27` documents x-callback-url:

`shortcuts://x-callback-url/run-shortcut?name=…&input=text&text=…&x-success=…&x-cancel=…&x-error=…`

On success, Shortcuts opens `x-success` and appends a `result` parameter with the shortcut’s textual output. Cancel opens `x-cancel` and includes no output. Error opens `x-error` and appends `errorMessage`. The app has no URL scheme, so it cannot receive those opens today. Even after one is added, `result` is text the shortcut produced. It satisfies a contract whose postcondition is “textual output arrived”. It does not satisfy “message delivered” or “playback started” unless the trusted capability says the only acceptable receipt is that text, and the user has accepted that limit on the review card.

If the app is killed, or Shortcuts never calls back, the step stays ambiguous. Cancellation or an error may follow partial work inside the Shortcut. None of these outcomes proves that no side effect occurred. The design below does not open the same irreversible Shortcut again.

### Automations

On iOS 27, automations are attached to a shortcut (Edit, then Automation) rather than living only as a separate object. The guide lists triggers that can run with “Allow Running When Locked”: Time of Day, Alarm, Sleep, Arrive, Leave, CarPlay, Email, Message, Transaction, Wi-Fi, Bluetooth, Apple Watch Workout, NFC, App, Airplane Mode, Do Not Disturb, Low Power Mode, Battery Level, Charger, and Sound Recognition. It also says individual actions may still need their own permission to run automatically. That sentence matters: a trigger allowed to start is not a promise that Send Message, a payment, or playback proceeds with no prompt. This has not been tried on a phone.

iOS 27’s Shortcuts notes add Notification, Keyboard, and Screenshot automations, plus actions such as “Get What’s On Screen” (more structured output), “Get Selected Text”, Messages actions including delete, and Shortcuts Storage. Those actions belong to the Shortcuts app. Pocket Glimmer cannot call them. A user can put one in a shortcut and pass its output into `AskPocketGlimmerIntent` or `HandleTextIntent`. That is voluntary sharing. Text that arrives this way is still user content: the existing sensitivity decision runs before any Muse call, and the workflow store must not put it in the distillation export.

`https://support.apple.com/en-euro/guide/shortcuts/apd350ce757a/10.0/ios/27` describes “Receive What’s On Screen” as a shortcut detail toggle. Supported examples named on the page are Safari, Maps, and Photos. Items are passed into the shortcut. They are not passed into a third-party process unless the shortcut does so.

### App Intents

`https://developer.apple.com/documentation/appintents` (documentation set current as of the 2026-11-03 index) exposes an app’s own actions to Siri, Shortcuts, Spotlight, widgets, and hardware buttons. `perform()` returns a value, dialog, or snippet to the system, which a shortcut can pass to a later action (`https://developer.apple.com/documentation/appintents/creating-your-first-app-intent`). That is the direction this app already implements.

Apple DTS, March 2025, on thread 776820: “One application cannot invoke an app intent of another.” That sentence predates iOS 27. The current public App Intents reference describes no type that runs another app’s `perform()`. `callAsFunction` runs the intent you already have. Pocket Glimmer’s composition path is therefore: call its own executor, or hand off to a Shortcut the user installed. It does not discover or invoke Instagram’s intents.

`AppIntentError` values such as permission required and user action required are for the system when *our* intent fails. They do not let us satisfy another app’s permission.

Personal automations that need a decision from this app should keep today’s shape: call `ProactiveTriggerIntent`, store a pending run, and post a notification. Irreversible work waits until the user opens the app and confirms. `openAppWhenRun = false` is the wrong place to present MessageUI.

## Muse Spark as a planner

Official pages, read 2026-11-04, no request sent:

- Tool calling: `https://dev.meta.ai/docs/tool-calling`
- Structured output: `https://dev.meta.ai/docs/structured-output`
- Chat completions are stateless: `https://dev.meta.ai/docs/protocols/chat-completions`
- Responses API stores by default (`store: true`): `https://dev.meta.ai/docs/protocols/responses`
- Standard mode does not train on content; Contributor mode is a different model id: `https://dev.meta.ai/docs/pricing-rate-limits` and `https://dev.meta.ai/docs/models`
- The current client already uses `https://api.meta.ai/v1/` and `muse-spark-1.3` (`CloudPresets.metaModelAPI`, `MetaAPI.requireStandardMode`).

Documented constraints that the planner has to respect:

- The model does not execute developer-defined tools. The client does. Built-in `web_search` runs on Meta’s servers. Do not offer it. It sends the query off the phone and still cannot touch iOS.
- `tool_choice` accepts only `"auto"`. `"required"`, `"none"`, and a named tool return HTTP 400. The model may answer with prose. The client treats prose as “no plan”, not as permission to improvise.
- The tool-calling page says `strict: true` validates the tool schema's supported subset. The structured-output page separately documents schema-constrained decoding through `response_format`. These are distinct contracts. Parse responses locally and validate capability IDs, arguments and approval requirements regardless of format guarantees.
- Schema limits that return HTTP 400: depth 10, 5,000 properties, 120,000 characters of names and enum values, 1,000 enum values by default, no cyclic `$ref`. A proposal schema that enums the compiled capability ids stays far inside this.
- Parallel tool calls default to on. A planner that did use tools would set `parallel_tool_calls` false and would expose only read capabilities (`calendar_find`, `lookup_contact`, `search_memory`, `device_status`). Side effects are not tools.
- Chat Completions has no server conversation. Prefer that endpoint, which the app already calls, over Responses. If a later change uses Responses, send `store: false`. The default stores the conversation for retrieval by id.
- Standard mode is “content is not used to train Meta models”. It is not a promise of zero retention. `docs/META_MULTIMODAL.md` already says that. Planning text goes through `PrivacyScrubber` and the `sensitivity` decision first. A `sensitive` result skips the network. Contributor ids stay rejected. Fireworks and BYOK are not planners.
- Meta’s cookbook also documents computer use on a desktop. That is out of scope. It is not an iOS API, and this product will not drive a GUI from screenshots.

The 1B model is the wrong planner. It answers letter logits for a frozen set. `skillPick` has no calibration guarantee (`docs/EVALUATION_CLAIMS.md`). Asking it to emit workflow JSON would be free generation, which this app uses only for short local answers and chart titles. Do not add a decision type and do not retrain.

## Trusted registry and untrusted proposals

Two tables:

1. **`CapabilityRegistry`**, compiled in Swift next to `BuiltinSkills`. User JSON and model JSON cannot add a row or change `effect`, `confirm`, `compensation`, or `satisfies`. A Documents/Skills file may add a new URL or Shortcut handoff. Those enter as `effect: handoff`, `compensation: none`, `confirm: always`, and `satisfies: [urlOpened]` or `[shortcutText]` only. They cannot register a native handler. Replacing `imessage_send` or `uber_ride` in JSON does not change the compiled row the workflow runner uses.
2. **`WorkflowProposal`**, JSON from the user, from a saved trace, or from Muse. The only fields honored are `title`, `trigger`, and `steps[].capabilityId` plus `steps[].args`. Keys such as `effect`, `confirm`, `permission`, or `idempotent` are dropped.

Effect is looked up, never parsed from the proposal:

| Effect | Examples in today’s registry | Confirm | Auto-retry after `started` with no receipt |
|---|---|---|---|
| `read` | `calendar_find`, `lookup_contact`, `search_memory`, `device_status`, `email_digest` (only after shared text exists) | No extra confirm | Yes |
| `localWrite` | `reminder_create`, `calendar_create`, memory upsert of an autoreply rule | Once on the run card | No. Ask the user whether the write is already there. |
| `handoff` | URL skills, Shortcut skills, `appletv_play`, `uber_ride`, `music_play`, `spotify_play` | Always | No |
| `irreversible` | `imessage_send`, `email_compose`, `call`, `facetime`, Instagram/X/WhatsApp handoffs, any user skill in `message` / `social` / `email` | Always, and a persisted attempt before the call | Never |

`email_digest` stays `read` because it only summarizes text already handed over. It still confirms today because its category is `email`. Keep that confirm on the run card so the digest does not silently upload long text. The cloud summarize path inside `Assistant.reason` already runs `sensitivity` before Muse.

Argument binding uses the existing `ArgSpec` kinds. A contact argument on an approved definition stores an opaque token the app resolved at approval time (`CNContact.identifier` once `searchContacts` is extended; until then the slice’s tests use fixture tokens). At run time the token is re-resolved. A missing or renamed contact pauses at `needsUser`. The flow does not fall through to “first Sam”.

## Completion contract

Every compiled capability carries this contract. The run record stores the contract id and version, not a model paraphrase.

| Field | Meaning |
|---|---|
| Requested outcome | One sentence the review card shows. |
| Preconditions | Permission, bound arguments, online bit, installed Shortcut name, shared-text present. |
| Available actions | The one executor call. A workflow is a list of these, not a new action. |
| Observable postconditions | The receipt kinds that count as success for this capability. |
| Permission | Contacts, Reminders, Calendars, Notifications, or none. The OS sheet is the grant. A cloud plan cannot grant it. |
| User handoff | What the user must do in another UI, or empty. |
| Failure classes | `validationRejected`, `permissionDenied`, `needsUser`, `sensitivityBlocked`, `unavailable`, `cancelled`, `failed`, `ambiguous`. |
| Retry / resume / undo | From the effect table. |
| Duplicate prevention | One `attemptId` per step. Unique in SQLite. A second confirm returns the existing receipt. |

Receipt kinds: `eventKitSaved`, `messageComposeSent`, `messageComposeCancelled`, `messageComposeFailed`, `mailComposeSaved`, `urlOpened`, `urlRefused`, `shortcutText`, `shortcutCancelled`, `shortcutError`, `textProduced`, `userCancelled`, `ambiguous`.

`urlOpened` satisfies only a contract that lists `urlOpened`. It does not satisfy a contract that lists `messageComposeSent` or a playback receipt. There is no playback receipt.

## Run states

Persist in the same `pocket.sqlite` the app already opens (`AppModel` data directory). New tables, no change to `facts` or `decisions`.

```sql
CREATE TABLE workflow_definitions (
  id TEXT NOT NULL, version INTEGER NOT NULL,
  status TEXT NOT NULL,            -- draft, approved, disabled
  title TEXT NOT NULL, trigger_norm TEXT NOT NULL,
  body TEXT NOT NULL, content_hash TEXT NOT NULL,
  failure_count INTEGER NOT NULL DEFAULT 0,
  ambiguous_count INTEGER NOT NULL DEFAULT 0,
  created REAL NOT NULL, updated REAL NOT NULL,
  PRIMARY KEY (id, version));
CREATE TABLE workflow_runs (
  id TEXT PRIMARY KEY, definition_id TEXT NOT NULL,
  definition_version INTEGER NOT NULL, state TEXT NOT NULL,
  created REAL NOT NULL, updated REAL NOT NULL);
CREATE TABLE workflow_steps (
  run_id TEXT NOT NULL, step_index INTEGER NOT NULL,
  capability_id TEXT NOT NULL, attempt_id TEXT NOT NULL,
  state TEXT NOT NULL, args_json TEXT NOT NULL,
  receipt_kind TEXT, receipt_json TEXT, updated REAL NOT NULL,
  PRIMARY KEY (run_id, step_index), UNIQUE (attempt_id));
```

Definition status moves `draft → approved → disabled`. A disabled row stays in the database. Approval of a new version does not delete the old one. Runs point at the version they started with.

Run states: `awaitingConfirm`, `running`, `paused`, `completed`, `partial`, `cancelled`, `failed`, `ambiguous`.

Step states: `pending`, `needsUser`, `started`, `committed`, `handedOff`, `failed`, `cancelled`, `ambiguous`, `skipped`.

Transitions that matter:

1. Validation produces a draft definition. Nothing runs.
2. The user approves a version. The card lists every step’s title, bound arguments, effect, and the receipt the app will be able to show.
3. A later “Run …” creates a run in `awaitingConfirm` and one `pending` row per step, each with an `attemptId`. No executor call yet.
4. Confirm moves the run to `running`. For each step, in order: if the effect is not `read`, a SQLite transaction sets `started` and commits **before** `perform`. Then the executor is called.
5. A receipt moves the step to `committed` (`eventKitSaved`, `messageComposeSent`, `textProduced`) or `handedOff` (`urlOpened`, `shortcutText`). `messageComposeCancelled` and `userCancelled` are `cancelled` and stop later steps. `messageComposeFailed`, thrown errors, and `urlRefused` are `failed`.
6. Process death after `started` and before a receipt leaves `started`. On next launch `WorkflowEngine.resume` rewrites that step to `ambiguous`, sets the run to `ambiguous`, and returns `doNotReplay`. It does not present the compose sheet again and does not open the URL again.
7. Death while still `awaitingConfirm` shows the same card. No side effect has started, so this is safe.
8. A second confirm for an `attemptId` that is already `started`, `committed`, `handedOff`, or `ambiguous` performs zero executor calls.
9. Cancel before `started` marks the step and the run `cancelled`.
10. Partial success: at least one `committed` or `handedOff` step, then a later failure. Compensation runs only for a `localWrite` whose receipt JSON contains an identifier, and only after another user confirm. Messages, calls, URL handoffs, and Uber have `compensation: none`.

Reads may run again on resume. Everything else in `started` or `ambiguous` may not.

Shortcut x-callback, once the app has a URL scheme, uses the same rows. The `attemptId` is a query item on `x-success`, `x-cancel`, and `x-error`. A callback whose attempt is unknown is ignored. A callback that never arrives is the same ambiguous timeout as process death. The user can explicitly say “it did not run” and only then may they confirm a **new** attempt id. The old row stays `ambiguous` so logs do not forget the gap.

`email_digest` and any step that needs shared text copy the text into `args_json` at run creation (or record `needsUser` if the inbox is empty). They do not call `SharedInbox.take()` later, because that value expires and is not durable.

## Matching, review, version, disable

Matching does not call the 1B and does not change τ.

- Approved flows run when the normalized utterance equals the saved trigger, or when the user picks the flow by its title (“Run Running late”).
- A near match returns a clarification that names the flow. It does not execute.
- The ordinary `skillPick` path is unchanged when nothing matches. “Text Mom I'll be home by 8” continues to clarify on the shipping engine unless the user has approved a flow whose trigger is exactly that normalized sentence. Approving that sentence is a user action. It is not a claim that the model became sure.

Review card, before `approved`:

- Title, version, content hash.
- Each step: capability title, arguments with contacts shown as the name resolved at approval, effect, and the sentence “I will be able to tell you: …”.
- For `imessage_send`: “I can tell you that you tapped Send in Messages. I cannot tell you it was delivered.”
- For `appletv_play`: “I can tell you Shortcuts was asked to open. I cannot tell you the show played.”
- A toggle only if a step needs Muse. Default off when the sensitivity decision is `sensitive` or the device is offline.

Versioning: canonical JSON is the steps in order with capability ids and args, sorted keys, no whitespace. `content_hash` is SHA-256 of that bytes. Any edit writes `version + 1` as a new draft. In-flight runs keep their version.

Disable, all local:

- The user marks “This did the wrong thing”, or
- three runs of that version end `failed` or `ambiguous`.

The definition status becomes `disabled`. Matcher skips it. The user can approve a new version later. The app does not rewrite steps because an OS version changed.

OS and app change:

- Each capability has a `probe` that does no side effect: URL syntax, required argument present, Shortcut name non-empty, permission state if the API exposes it without prompting.
- `unavailable` on a required step pauses the run and disables further automatic matching until the user reviews that version.
- Do not infer that a Shortcut gained or lost actions. Describe a Shortcut and iOS 27 action lists are user-facing. After an OS update, handoff capabilities stay handoffs.

Distillation export (`TelemetryLog.exportDistillationQueue`, `AppModel.exportDistillation`) stays on decision rows. Workflow bodies that contain message text are not added to that export.

Credentials stay in Keychain under the existing `meta_key` item (`Keychain`, `CloudSettings`). The planner receives a bearer token only inside the request that already exists for chat completions. Workflow JSON stores no key, no Authorization header, and no phone number when a contact token is available. Scrubber placeholders are restored only in the on-device result, as `Assistant` already does for answers.

## Three flows

Triggers are exact normalized phrases. Arguments shown are what the validator stored, after the registry filled effect and confirm.

### 1. Evening wind-down (read, then one local write)

User: “Wind down tonight”. Offline. No Muse.

```json
{
  "id": "wind-down",
  "version": 1,
  "status": "approved",
  "title": "Wind down tonight",
  "trigger": "wind down tonight",
  "steps": [
    {
      "capabilityId": "calendar_find",
      "args": { "query": "today" },
      "effect": "read",
      "satisfies": ["textProduced"]
    },
    {
      "capabilityId": "reminder_create",
      "args": { "title": "Pack bag", "when": "tomorrow 7:30am" },
      "effect": "localWrite",
      "satisfies": ["eventKitSaved"]
    }
  ]
}
```

Preconditions: Reminders and Calendars permission, both already requested by `SystemActions.requestAccess`. Postcondition: a reminder identifier in the receipt, plus the calendar lines shown in the reply. The calendar read can be repeated. The reminder is not created twice: resume sees `committed` and skips, or sees `started` and asks. Undo, after a second confirm: delete that identifier. Failure if the permission is denied: `permissionDenied`, run `failed`, definition failure count increments. This flow does not message anyone.

`calendar_find` today searches 30 days by title tokens (`SystemActions.searchEvents`). “today” does not query today’s events. The morning-brief helper `eventsOn(_:)` does. The slice’s capability implementation for this step calls that day-bounded read, not `searchEvents`.

### 2. Running late (irreversible message, no replay)

This flow is a saved definition. It does not ask `skillPick`, so the CPU rehearsal’s 0.810 score does not apply. The user approved the contact token while looking at one person.

```json
{
  "id": "running-late",
  "version": 3,
  "status": "approved",
  "title": "Running late",
  "trigger": "running late to mom",
  "steps": [
    {
      "capabilityId": "imessage_send",
      "args": {
        "contactToken": "contact:approved:mom",
        "contactDisplay": "Mom",
        "body": "I'll be home by 8"
      },
      "effect": "irreversible",
      "satisfies": ["messageComposeSent"]
    }
  ]
}
```

A Muse proposal that added `"effect": "read", "confirm": false` is stored only in the audit blob of the draft. The approved row above has `effect` from the compiled `imessage_send` capability. The review card says the user still taps Send.

Run, after the user confirms:

1. Insert step `started` with `attemptId` `8f0c…`.
2. Present MessageUI.
3. `.sent` → receipt `messageComposeSent`, step `committed`, run `completed`. Reply uses the existing sentence “Sent to Mom via Messages”, and the card adds “Messages accepted the send. Delivery is not confirmed.”
4. `.cancelled` → `cancelled`. A later explicit retry allocates a new attempt id.
5. Kill between 1 and 3 → next launch `doNotReplay`. The reply is “A message to Mom may already be in Messages. I will not send it again.” The user can open Messages. If they say it is not there, a new attempt requires a new confirm.

“Text Sam …” is not this flow. Two Sams remain `needsUser` until approval binds one token. The flow does not pick argmax.

### 3. Shared email to a reminder (share sheet, optional cloud)

User shares from Mail through the documented “PG Share Emails” shortcut into `HandleTextIntent` with source `mail`, then says “Turn this email into a reminder”.

```json
{
  "id": "email-to-reminder",
  "version": 1,
  "status": "approved",
  "title": "Email to a reminder",
  "trigger": "turn this email into a reminder",
  "steps": [
    {
      "capabilityId": "email_digest",
      "args": { "source": "mail" },
      "effect": "read",
      "satisfies": ["textProduced"]
    },
    {
      "capabilityId": "reminder_create",
      "args": { "title": "$digest.deadline", "when": "$digest.when" },
      "effect": "localWrite",
      "satisfies": ["eventKitSaved"]
    }
  ]
}
```

Preconditions: non-empty shared text copied onto the run before `SharedInbox` can expire; Reminders permission. The digest step calls the existing `reason` path: on device under 2,500 characters; above that, only if online, a key exists, and `sensitivity` is `ok`, scrubbed, `muse-spark-1.3` only. If sensitivity is `sensitive`, the step is `sensitivityBlocked` and the reminder is not created from a cloud guess. The local 1B may still summarize the truncated window, and the reminder arguments stay blank until the user types them (`needsUser`).

The deadline and when-phrase are taken from a structured proposal whose schema is `{deadline: string, when: string}` with `strict: true`, or from the user editing the card. They are not executed because the model named them. `reminder_create` runs only after the run confirm, with `eventKitSaved` as the success receipt.

Observable postcondition: bullets in the chat, and a reminder identifier if the user confirmed one. The app still has not read the Mail inbox. Opening Mail is not part of the flow.

### Handoff that must stay a handoff

`appletv_play` is a legal step and a poor success story. Contract: precondition is the user-configured Shortcut name `PG Play on Apple TV`; action is the documented run URL; postcondition is `urlOpened` until x-callback exists, then `shortcutText` if a callback arrives; handoff copy stays the skill note. A run that only got `urlOpened` completes as `handedOff`, which the UI renders as partial relative to “play Severance”. It does not increment a playback success. Describe a Shortcut can help the user write that Shortcut on an Apple Intelligence phone. Pocket Glimmer’s contribution is the show-name string and the handoff. The playback recipe remains unverified, as `BuiltinSkills` already says.

## Where composition can actually happen

| Path | Who sequences the steps | What Pocket Glimmer learns | Completion evidence |
|---|---|---|---|
| Native registry | This app, one compiled capability per step | The approved definition and the run rows | EventKit identifier, MessageUI/Mail result, on-device text |
| User Shortcut | The user, in Shortcuts, including Describe a Shortcut and Use Model (On-Device, Cloud, Cloud Pro, or the Extension Model, which the iOS 27 guide identifies as ChatGPT) | The name the user typed, plus callback text after a URL scheme exists | `urlOpened`, then `shortcutText` / `shortcutError` / `shortcutCancelled`. Use Model inside Shortcuts is the user’s Apple Intelligence session. It is not this app’s planner and is not a Meta-only path. |
| Approved service API | Muse proposes JSON. The phone validates and executes. | The proposal blob and the edited definition | Same native receipts. The model’s prose is not a receipt. |
| Restricted web and URL schemes | The destination app, after `open` | That the URL was accepted | `urlOpened` or `urlRefused` |

Use Model’s “Broad World Knowledge” toggle and ChatGPT extension are documented Shortcuts features (`https://support.apple.com/en-euro/guide/shortcuts/tpg3vrvwmclv/10.0/ios/27`). They are available to the user while authoring. Pocket Glimmer does not call them.

JavaScript in a Safari webpage is a Shortcuts action in that same guide. This app’s chart web view disables JavaScript (`HTMLWebView`). Do not add page scripting as a learned step.

## Smallest PocketCore slice

No UIKit, no URL scheme, no Meta request, no change to `DecisionType` or τ. Linux `swift test` can run it the same way the current PocketCore tests run.

New files:

- `core/Sources/PocketCore/Workflow.swift`
- `core/Tests/PocketCoreTests/WorkflowTests.swift`

Types and functions:

```swift
public enum EffectClass: String, Codable, Sendable { case read, localWrite, handoff, irreversible }
public enum Compensation: String, Codable, Sendable { case none, deleteEventKitID }
public enum ReceiptKind: String, Codable, Sendable {
    case eventKitSaved, messageComposeSent, messageComposeCancelled, messageComposeFailed
    case mailComposeSaved, urlOpened, urlRefused, shortcutText, shortcutCancelled, shortcutError
    case textProduced, userCancelled, ambiguous
}
public struct Capability: Sendable, Equatable {
    public var id: String
    public var effect: EffectClass
    public var confirm: Bool
    public var compensation: Compensation
    public var satisfies: Set<ReceiptKind>
}
public struct CapabilityRegistry: Sendable {
    public static let compiled: CapabilityRegistry
    public func capability(id: String) -> Capability?   // nil if unknown; ignores user-JSON effect
}
public struct WorkflowProposal: Codable, Sendable {
    public var title: String
    public var trigger: String
    public var steps: [ProposedStep]   // capabilityId + args only
}
public struct WorkflowDefinition: Codable, Sendable, Equatable {
    public var id: String
    public var version: Int
    public var status: String
    public var title: String
    public var triggerNorm: String
    public var steps: [BoundStep]      // effect copied from the registry
    public var contentHash: String
}
public enum WorkflowError: Error, Equatable {
    case unknownCapability(String), empty, effectMismatch(String)
}
public enum ResumeAction: Equatable {
    case showConfirmation
    case doNotReplay(String)
    case continueAt(Int)
    case alreadyTerminal
}
public enum WorkflowEngine {
    public static func validate(_ proposal: WorkflowProposal, registry: CapabilityRegistry) -> Result<WorkflowDefinition, WorkflowError>
    public static func resume(_ run: WorkflowRun) -> ResumeAction
    public static func beginAttempt(_ store: WorkflowStore, runId: String, stepIndex: Int) throws -> String
    // beginAttempt commits state=started and returns the attempt id, or throws if the row is not pending.
}
public final class WorkflowStore {
    public init(db: SQLiteDB) throws
    public func save(_ definition: WorkflowDefinition) throws
    public func startRun(_ definition: WorkflowDefinition, now: Date) throws -> WorkflowRun
    public func record(runId: String, stepIndex: Int, receipt: ReceiptKind, payload: String) throws
    public func disable(id: String, version: Int, reason: String) throws
}
```

`BoundStep.effect` is assigned inside `validate`. A test feeds a proposal whose raw JSON contains `"effect":"read"` on `imessage_send` and asserts the bound step’s effect is `irreversible` and `confirm` is true.

Acceptance tests, all with a recorder executor and an in-memory `SQLiteDB`:

1. `testUnknownCapabilityRejected` — id `tap_send` yields `unknownCapability`.
2. `testModelEffectIsIgnored` — extra JSON keys do not change `imessage_send`.
3. `testUserJsonCannotRegisterNativeHandler` — a handoff-shaped extra skill is accepted only as `handoff`; `native("send_message")` from outside `compiled` is rejected.
4. `testUrlOpenedDoesNotSatisfySend` — `urlOpened` does not meet `imessage_send.satisfies`.
5. `testStartedMessageIsNotReplayed` — step `started`, no receipt, `resume` is `doNotReplay`, recorder call count stays 0.
6. `testSecondConfirmIsANoop` — two `beginAttempt` calls, one recorder invocation.
7. `testDeathBeforeStartShowsTheCard` — run `awaitingConfirm`, `resume` is `showConfirmation`, recorder still 0.
8. `testPartialCompensationIsLimited` — reminder `committed` with an identifier, message `failed`; compensation offered is `deleteEventKitID` for the reminder only.
9. `testReadCanRetryAndHandoffCannot` — `calendar_find` in `started` may `continueAt`; `uber_ride` in `started` is `doNotReplay`.
10. `testThreeAmbiguousRunsDisable` — matcher returns no hit after the third ambiguous run of that version.
11. `testExactTriggerDoesNotFuzzyExecute` — “text mom ill be home by 8” does not start `running-late` when the trigger is “running late to mom”; it returns a clarification string.
12. `testSensitiveDigestSkipsPlannerNetwork` — a fake planner records zero requests when the sensitivity flag is `sensitive`.

Out of the slice, on purpose: SwiftUI review card, `CNContact.identifier` lookup, URL scheme, x-callback parsing, and the real Muse HTTP call. The planner protocol can be a test double that returns a fixture proposal. Shipping that double as `MusePlanner` waits until the slice’s validator tests are green, and then still requires the privacy gates above. No threshold change, no gold inference, no new dependency.

App integration, after the slice, is a thin call in `AppModel.send`: try `WorkflowMatcher` first; on an exact hit, start a run and show the existing confirmation bubble with the run id; on confirm, call `beginAttempt` then the current `Assistant.execute` for that one capability. `ChatItem.pending` remains a view of the SQLite row, not the source of truth.

## Ranked findings

1. There is no durable attempt record. `ChatItem.pending` dies with the process, and `execute` runs as soon as confirm is tapped. Irreversible replay protection has nowhere to live until `beginAttempt` commits first.
2. The observable surface is already defined by the code: utterance, share/intent parameters, EventKit save, MessageUI/Mail result, URL-open bool, decision rows, memory facts. Screen contents of other apps are outside it.
3. URL-open and Shortcut handoff are the status strings for Instagram, X, WhatsApp, Uber, music, and Apple TV. `appletv_play` also runs with no skill-level confirm when `confirmBeforeAct` returns `act` (`TakeoverRegressionTests`). Learned flows need a compiled confirm bit for every handoff and irreversible capability.
4. User JSON can replace a built-in id. Category force-confirm covers only message, social, and email. Uber, call, and FaceTime confirms are data. The workflow registry has to be compiled.
5. iOS 27 Describe a Shortcut is a real, device-gated editor feature on the iOS 27 guide, present on 27.0.1 because 27.0.1 does not remove iOS 27 features. The app can open a blank editor. It cannot see or trust the shortcut that comes out. x-callback text is the best public callback and is unused. 27.2 notes are a different release.
6. Muse Spark 1.3 can return a schema-shaped proposal on the endpoint the app already calls. `tool_choice` cannot force a tool. Arguments are untrusted. Responses storage defaults on. The current decoder drops tool calls. Standard mode stays `muse-spark-1.3` only.
7. A promoted phrase match is how a below-threshold utterance becomes reliable. It is a user-approved binding. It is not a new score and not a reason to edit τ, priors, or the GGUF.

## Ranked proposals

1. Land the PocketCore slice and the twelve tests. No app change required for the tests.
2. Point `AppModel.confirm` at `beginAttempt`, store EventKit identifiers, and classify MessageUI results as receipts. Keep the existing compose sheet.
3. Add a URL scheme solely for Shortcut x-callback, and record timeout as `ambiguous`. Still no automatic second open.
4. Add `MusePlanner` behind `validate`, Standard mode, scrubber, sensitivity, `parallel_tool_calls: false`, no built-in tools, chat completions. Read capabilities only if a tool loop is added later.
5. For a missing Shortcut, copy a plain-language description and open `shortcuts://create-shortcut`. Ask the user for the exact name before any run. Do this on an Apple Intelligence device; on other iPhones, the manual editor path on the same help page is the one that exists.
6. Leave personal automations as enqueue-and-notify. Do not send, pay, or hand off from `ProactiveTriggerIntent`.

## Evidence limits

- Code and tests were read at `d782b81`. The integrated core run cited by the product status (108 tests, one opt-in API test skipped, zero failures) was not re-executed for this note.
- The CPU rehearsal numbers are the saved Linux run in `docs/ENGINE_REHEARSAL_NOV4.md`. They are not iPhone latency or memory.
- iOS 27.0.1 behavior is from Apple Support and the versioned Shortcuts User Guide. The en-gb copy of article 149076 and the iPhone Shortcuts guide URL did not return article text here. The en-us article 149076 and the euro/om Shortcuts guide did.
- No claim is made that Email or Message automations actually run a send with no prompt. The guide says some triggers can start without asking and that individual actions may still require it.
- The DTS sentence that one app cannot invoke another app’s intent is from March 2025. The current App Intents reference still shows no public invoker. That absence is the iOS 27 evidence used here.
- Muse behavior is from official docs. No completion was requested, so tool-call JSON from `muse-spark-1.3` was not observed in this pass. The app’s earlier live multimodal smoke is a different client path and is not a planning result.
- MessageUI `.sent` is implemented in this repo’s delegate. Apple’s result enum is the API that delegate switches on (`https://developer.apple.com/documentation/messageui/messagecomposeresult`). This pass did not re-fetch a populated body for that page. The shipping strings are the code in `ComposeSheets`.

## What a device still has to show

- A signed build of this tree on iOS 27.0.1: first launch, permission sheets, the MessageUI result strings, and a Shortcut that is missing versus installed.
- Whether `shortcuts://x-callback-url/run-shortcut` returns to a declared scheme with `result`, `errorMessage`, or neither, including when the user locks the phone mid-run.
- Whether Describe a Shortcut will accept a pasted description, which devices in the user’s hands are Apple Intelligence-capable, and which language the phone is set to.
- Whether an Email or Message automation that calls `ProactiveTriggerIntent` delivers sender and body, and whether “Allow Running When Locked” suppresses action prompts.
- EventKit identifier round-trip and the user’s actual confirm/cancel/kill timing.
- Nothing on that list can be settled from a URL-open callback or from a correct local letter decision.

## Blocker

No Mac and no iPhone are available, and this tree has not been built for iOS 27.0.1. That blocks every runtime claim. It does not block the PocketCore slice. The product blocker for “recovered end to end” on arbitrary apps remains the public API surface: this app cannot see or drive those apps, and Muse cannot invent that access.
