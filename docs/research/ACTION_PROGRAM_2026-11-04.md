# iPhone action reliability program

The user confirmed the installed diagnostic build answered `4` to `What is 2 + 2?`
with Airplane Mode enabled and Wi-Fi disabled. This is a manual runtime observation,
not a latency, Metal, thermal, or action test. The original calibration mismatch is
not explained by the successful reinstall.

The user then reported that a request to message someone produced a conversational
reply without opening a composer. They require reliable single and multi-step phone
actions, keyboard dismissal, inline HTML visuals, a polished native interface, an
original icon, and useful diagnostics. The exact original message request was not
provided. Common grammatical variants must be tested, not assumed equivalent.

## Grounded current shape

`Assistant.handle` creates one `UserRequestID`, gathers memory and makes calibrated
route/tool decisions. `AssistantTurn` contains one optional `PlannedAction` and one
`Reply`. `ActionPlanner.skillOverride` gives explicit requests a registry path before
the generic reply. Its current message detector recognizes `text Dana` and `send a
message to Dana`, but misses `send Dana a message` and polite prefixes. This is a
reachable route to an ordinary answer when the route model misses the action.

The compiled capability catalog defines argument kinds, confirmation floors,
executors and observable outcomes. `EffectSession` binds a request, inserts an
awaiting attempt, and claims it before invoking `PhoneEffects`. The ledger has
`request_id` and `step_index` columns, but insertion always uses step zero and the
claim does not enforce successful predecessors. Existing terminal states distinguish
verified local writes, Messages acceptance, Mail queueing, handoff opening, failure,
cancellation and uncertainty. None implies universal delivery or task completion.

`AppModel` projects one turn into chat. `ComposeSheets` in `SystemActions.swift`
owns Messages and Mail continuations. `PocketEffects` owns the native effect
boundary. Contacts permission currently depends on onboarding. The native boundary,
foreground presentation, callback identity and permission recovery need a Mac build
and real interaction evidence. A fake effects adapter only proves core contracts.

The user approved native build, signing, installation and testing on the linked Mac
and iPhone. Device-panel automation failed twice earlier; do not bypass that failure
with command-line launch or UI scripts. Builds, installs, logs and project test
runners remain available. Manual phone observations must be labeled as such.

## Units and ownership

1. Repair explicit single-action routing and native messaging presentation. A request
   for an action must produce a draft, a clarification, a supported execution result,
   or a concrete unsupported explanation. It must never fabricate execution in prose.
   Test polite and recipient-first message requests, missing recipient/body, contact
   ambiguity, cancellation, unavailable compose, duplicate taps and late callbacks.
2. Preserve inputs with the selected admission store before busy/model-readiness
   decisions. See `REQUEST_INPUT_SYNTHESIS.md`. Input storage remains separate from
   the effect journal and must not become an automatic execution queue.
3. Compare two complete multi-step designs against this existing journal. One design
   should concentrate a bounded ordered plan in the journal; the other should test a
   small dependency-aware plan controller. Both must reuse the existing effect
   authority, stop at uncertainty, and show partial progress honestly. No production
   multi-step implementation is selected yet.
4. Complete UI and HTML behavior on Mac, then build and install for phone verification.
   Parent owns AppModel/privacy integration. UI worker owns Views, native HTML display,
   shared appearance and icon packaging. Messaging worker owns native compose/contacts
   adapter fixes. Separate checkouts prevent simultaneous source writes.
5. Recheck combined action and privacy fixes, then run the actual installed acceptance
   flows. Linux checks, Xcode build, installation and phone outcomes are separate gates.

## Multi-step acceptance constraints

- Plan only compiled capabilities and reviewed user-defined handoffs. Unknown actions
  are visible unsupported steps. Do not infer arbitrary control over third-party UIs.
- Preserve the user's requirements, names, dates, quoted text and requested order.
  Plan proposals are untrusted until typed validation and concrete binding succeed.
- Maintain one ingress ID, stable step identities and an atomic predecessor condition
  at claim. A cancelled, failed, unknown or merely opened predecessor is not verified
  success. Declare explicitly which boundary a dependent step requires.
- Confirm communication and external handoffs. A tap authorizes the displayed step;
  a vague approval cannot authorize a new recipient, changed body, or extra effect.
- Propagate bounded typed results, not instruction text from documents, web pages or
  external callbacks. Never feed such text back as privileged instructions.
- Persist the plan and per-step receipts before showing saved/completed state.
  Restart projects state and offers explicit recovery; it never runs the next step.
- Do not replay effects after an ambiguous result, a lost receipt write, a crash after
  dispatch or a callback timeout. Stop with partial progress and destination checks.
- Keep the frozen classifier prompts, shipping model and calibration unchanged.
  Runtime reasoning stays Meta-only and honors the user's configured cloud provider.
  Coding agents are not runtime models and their prose is not training data.
- Test at least independent steps, a true result dependency, rejection of a missing
  capability, edits invalidating downstream bindings, cancellation at each boundary,
  concurrent confirmation, process interruption and receipt-write failure.

## Evidence still required

The first real messaging draft/composer/send-or-cancel observation is outstanding.
The core date/recipient repair `b3a2618` is integrated as `759fce5`; its author ran 203
tests with one skip and zero failures. The parent independently reran the integrated
core suite with the same result; see `action-time-parent-core-tests.txt`. Calendar is
still fixed to one hour with no invitations or location. Named zones and unsupported
options are refused; expanded typed support remains future work. These limitations
must not be represented as complete support for all actions.

The shared-read review at `5912cd7` passes ordinary C1/C2 fallback paths but leaves
ambiguous-read badge/payload projection, launch recovery, immediate cloud-error
disclosure and edit error copy open. Attempted provider attribution also remains open.

Training is independent of these app changes. The existing Muse owners retain their
budgets and immutable data splits. The user raised matched Spark Open labeling to
99–100 RPM. Expansion has drained traffic and retained uncertain-call reservations;
the parent relayed its acknowledgment so the matched owner can apply 99 RPM under
the shared 100 RPM cap. This is an instruction and handoff, not measured throughput.
