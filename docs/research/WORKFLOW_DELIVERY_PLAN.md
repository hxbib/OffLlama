# Capability and recovery delivery plan

Reviewed 2026-11-04 after the three Grok 4.7 xHigh research reports. This is an implementation
plan, not a list of delivered phone capabilities. The current app has not been built or run
on iOS 27.0.1. See [DEVICE_ACCEPTANCE.md](../../ios/DEVICE_ACCEPTANCE.md) for the device record.

## What the reviews establish

The useful learning path is to save and compose actions the app can actually perform. Muse
can propose a new sequence and fill draft arguments. Public APIs, granted permissions and
the user's review determine what may run. A model cannot add access to another app's screen.

The current source loses pending confirmations when the process dies, discards execution
identifiers, and returns only text from most actions. These are concrete gaps in recovery.
The next work must connect durable records to the actual iPhone executors and UI. A tested
PocketCore store alone is not the completed feature.

The three source reports remain snapshots of `d782b81`:

- [Capability map](IOS27_CAPABILITY_MAP.md) covers all 36 skills and public API boundaries.
- [Journeys](IOS27_END_TO_END_JOURNEYS.md) supplies sixteen user journeys and twenty proposed device checks.
- [Learned workflows](LEARNED_WORKFLOWS.md) supplies the strongest persistence and trusted-capability design.

## Accepted direction

| Unit | User outcome | Evidence required before it is called done |
|---|---|---|
| Text privacy repair | Sensitive stored facts remain local; every transmitted document segment is screened | Captured-request regressions pass, useful benign cloud requests still work, all local facts remain available |
| Durable action and workflow records | A confirmed action survives a restart without being blindly repeated | Persistent-store reopen and concurrent-confirm tests; real executor results tied to the stored attempt |
| Editable message drafts | A low-confidence explicit message can be corrected and approved without losing its recipient/body | No execution on draft creation; unique contact bound before use; MessageUI cancellation and acceptance recorded |
| Verified calendar and reminder writes | Correct dated item, useful permission error, and a recoverable write | No guessed event start; save plus identifier/read-back; duplicate attempts and crash gaps tested |
| Reviewed learned workflows | User saves a new sequence or exact trigger without retraining the 1B model | Compiled capability/effect rules, versioned approval, bounded arguments, visible run and partial-result states |
| Muse planning | User can request a proposed workflow using the configured Meta key | Standard-mode request construction, complete privacy screening, local semantic validation, review before execution; a live test remains separate |
| Shortcut callbacks | User sees returned text, cancellation, error or an unresolved handoff | Matching attempt token, duplicate/unknown callback rejection, restart and timeout behavior; no playback or delivery claim |
| Native alarms and timers | App-owned alarm/countdown can be listed and cancelled on supported iOS | AlarmKit authorization and identity; SDK build and phone tests, including app restart |
| Voice review and accessibility | User edits a transcript before it becomes a request and can record without holding | No action before submission; local-only setting prevents upload; tap controls, VoiceOver and large text tested |

The ordering is intentional. Privacy comes before new cloud planning. The attempt journal
comes before new effects. Native and Shortcut adapters follow the shared result contract.
App integration and device acceptance follow each working unit rather than being deferred
behind a finished-looking headless library.

## Corrections to the candidate designs

1. A category and `confirm` flag supplied by JSON are not authority. Learned plans use a
   compiled capability registry. External JSON cannot replace a native implementation or
   downgrade an effect. Validation also checks allowed arguments and result contracts.
2. Save immutable approved versions. Runs bind the exact definition and capability contract
   version reviewed by the user. Replacing JSON must not silently change a pending run.
3. Atomic attempt claims prevent two callers from executing one step. There is no atomic
   transaction across SQLite and EventKit or another app. A crash after a side effect starts
   is unresolved until a real read-back or the user resolves it. Do not claim exactly-once execution.
4. A matching Shortcut callback reports text from that Shortcut. Custom URL schemes do not
   authenticate the sender. Cancellation and errors may follow partial side effects. A timeout
   means unconfirmed, not that nothing ran. Unknown, expired or duplicate callbacks do nothing.
5. A repeated title and time are a possible duplicate, not necessarily the same user intent.
   Prevent replay by attempt identity; offer a duplicate check for a genuinely new request.
6. Compensation applies only to an identifiable reversible write, after explicit confirmation
   and a check that the object still matches the receipt. Never delete an independently edited
   calendar item or imply that a message/ride/Shortcut can be undone.
7. Source labels such as "completed" describe the narrow contract. MessageUI acceptance,
   Mail queueing, URL opening, text generation and message delivery are different outcomes.
   Apple documents [Messages acceptance](https://developer.apple.com/documentation/messageui/messagecomposeresult)
   and [Mail queueing](https://developer.apple.com/documentation/messageui/mfmailcomposeresult).
8. Use a typed data model with a small public surface. Do not persist model-supplied effect
   flags, expose string state transitions, or add a new framework solely to name a Boolean.
   Tests need a real file-backed restart, not only an in-memory database.
9. A summary-to-reminder flow must bind a concrete title and date on the user's review card.
   A model-generated deadline or an unresolved `$digest.when` expression is not executable authority.
10. The 1B model, priors, τ=0.90, prompt format and gold evaluation artifacts remain frozen.
    Exact user-approved triggers are explicit bindings, not new model confidence or training.

## Platform checks and limits

Apple's [Siri AI developer preview](https://developer.apple.com/news/?id=gdk2umrf) starts on
the 27.3 betas. It must not be counted as an integration available on the requested 27.0.1
phone. Describe a Shortcut is a separate user-facing Shortcuts feature. Its existence does
not give this app an API to inspect or run arbitrary app interfaces.

Meta's [structured-output contract](https://dev.meta.ai/docs/structured-output) supports a
schema-shaped proposal. Its [tool-calling documentation](https://dev.meta.ai/docs/tool-calling)
separately defines tool schema validation and execution by the client. The initial planner
needs only a proposal response, not a general tool loop. Validate the response locally and
do not request built-in web or computer-use tools.

Native iOS API adapters remain unverified until Xcode builds them and the phone exercises
them. No accepted proposal changes the evidence status of the current app. The public
API boundary also means arbitrary third-party task recovery cannot be promised.

## Current status

- Research reports integrated and reviewed; the corrections above govern implementation.
- Two text privacy regressions are committed and failing before repair at `a4e100f`.
- Messages and Mail status copy now describes acceptance/queueing rather than delivery.
- Capability/run type contract, implementation and independent review are still pending.
- Mac build, signed install, phone measurements, demo video and submission remain open.
