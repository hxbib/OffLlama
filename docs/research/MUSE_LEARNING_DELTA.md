# Pocket Glimmer — Learned workflows: independent Muse second investigation (delta vs Grok)

## Provenance and protocol

- Investigator: Muse Wonder 1.0 (`muse-wonder-1.0`, reasoning effort max), running as the
  user-assigned research sub-agent in Muse Code ACP / T3 Code. No delegation was used.
  Provider/model/effort are exactly the user assignment in `/home/habib/.agents/MODEL_SELECTION.md`;
  nothing was substituted.
- Date: 2026-11-04. Repository: `/home/habib/pocket-glimmer`. Baseline: commit `009430f`
  ("docs: preserve reviewed action recovery implementation contract").
- Method, in order: (1) independent inspection of baseline source and official documentation,
  recorded in a separate scratch note (`/tmp/pocket-glimmer-takeover/muse-learning-independent-notes.md`)
  **before** opening the Grok report; (2) full read of `docs/research/LEARNED_WORKFLOWS.md` (Grok,
  base `d782b81`), `docs/research/WORKFLOW_DELIVERY_PLAN.md`, and
  `docs/research/EFFECT_RECOVERY_CONTRACT.md` (base `7b8d014`); (3) claim-by-claim comparison.
- Baseline drift check: `git diff d782b81..009430f -- core app` touches 10 files, 31 insertions,
  and is comment removals plus added `TakeoverRegressionTests` assertions. No behavior relevant
  to this question changed. Every Grok code claim re-checked below still holds at `009430f`.
- Constraints honored: no product source edited, no paid API call (no Meta request was sent),
  no credentials read, no training/evaluation artifact touched, no device interaction, no push/PR.
- Evidence limits that apply to everything below: there is no Xcode or iOS 27.0.1 build of this
  tree in this environment. Linux Swift tests were not re-run for this note. Nothing here is an
  iPhone result. API behavior claims are documentation claims, retrieved 2026-11-04, not live calls.

## Verdict

Grok's core design is sound and the reviewed contract (`EFFECT_RECOVERY_CONTRACT.md`) already
corrects its weakest parts. Pocket Glimmer can learn useful flows beyond the 36 preset skills,
but only in the shape Grok identified: user-approved, versioned compositions of capabilities the
app already executes, with compiled effect rules, durable attempt claims, and honest receipts.
Muse (Spark 1.3 by default) is a viable *untrusted proposer* of such compositions because the
Meta Model API documents schema-constrained structured output on the endpoint the app already
calls. It is not viable as an authority over permissions, effects, or bindings.

This second pass found five material things Grok missed or got imprecise, ranked in the next
section. None overturns the delivery plan. Two adjust it at the edges: the slice-4 planner should
honor the user's configured Standard-mode model instead of hard-coding `muse-spark-1.3`, and the
privacy-repair acceptance needs a demonstration-specific masking test. One adds a future slice:
approved workflows surfaced to Shortcuts/Siri as a dynamic `AppEntity`, which is the only public-API
path by which a *learned* flow becomes composable inside user automations.

## Ranked material differences vs Grok

### NEW-1. The correction-learning loop is implemented, tested, and never called in production

Grok never mentions it. Baseline facts:

- `MemoryStore.recordCorrection(type:context:wrongID:correctID:)` and
  `MemoryStore.reflexContext(for:context:)` exist at
  [Memory.swift](/home/habib/pocket-glimmer/core/Sources/PocketCore/Memory.swift:208) and are
  unit-tested (`CuratorMemoryTests.testCorrectionsRetrievedIntoReflexContext`).
- A repository-wide search at `009430f` shows **no production caller**. `Assistant` builds every
  decision context directly (`Assistant.handle`, `toolPath`, `planSkillCore`); `AppModel.confirm` /
  `AppModel.cancel` ([AppModel.swift](/home/habib/pocket-glimmer/app/PocketGlimmer/AppModel.swift:233))
  discard the user's verdict; the chat UI offers only Confirm/Cancel buttons
  ([ChatView.swift](/home/habib/pocket-glimmer/app/PocketGlimmer/Views/ChatView.swift)), and a
  below-τ clarification ("Did you mean: …?") is plain text the user must answer by restating.
- Consequence: the only "learning from the user" that actually happens today is memory-fact
  upsert (`RuleFactExtractor` + `rememberOrNot`). Decision corrections can only be created by
  tests or the CLI, yet `profileOnePager` already replays `decisionCorrections()` as autonomy
  text ([MemoryProfile.swift](/home/habib/pocket-glimmer/core/Sources/PocketCore/MemoryProfile.swift:80)) —
  a display path waiting on a writer that does not exist.
- Why it matters for this question: Confirm taps, Cancel taps, clarification picks, and
  post-run "that was wrong" marks are the cheapest trustworthy demonstration stream the app has.
  They are user actions on concrete `PlannedAction`s, observable entirely inside the process —
  unlike screen demonstrations, which are impossible. Any "learn from demonstrations" design
  should mine these first; Grok's demonstration definition ("user completes a real run and then
  saves that run", LEARNED_WORKFLOWS line 53) silently assumes a run record that today is only
  the proposed ledger.
- Guardrail Grok's framing would have missed: wiring `reflexContext` into `Reflex.decide` would
  change frozen decision prompts and invalidate the shipped calibration posture. Record signals
  into the effect ledger / profile only. Do not inject them into Reflex contexts without a new
  calibration round (out of scope; τ, priors, prompts stay frozen per delivery plan item 10).
- Plan impact: **future work**, after contract slices 1–2. No plan reordering.

### NEW-2. Approved workflows can surface in Shortcuts/Siri as a dynamic AppEntity — Grok's matcher is app-only

Grok's invocation surface for a learned flow is (a) exact phrase match inside `AppModel.send`,
(b) picking by title in-app. The current intent surface cannot do better: `QuickSkill` is a
compile-time `AppEnum` with 7 cases ([SkillIntents.swift](/home/habib/pocket-glimmer/app/PocketGlimmer/Intents/SkillIntents.swift:80)),
and there is exactly one `AppShortcutsProvider` with 4 shortcuts
([Intents.swift](/home/habib/pocket-glimmer/app/PocketGlimmer/Intents/Intents.swift:48)).
A learned workflow therefore can never appear in the Shortcuts editor, an automation, or Siri.

Public-API alternative, verified against Apple's documentation JSON endpoint
(`https://developer.apple.com/tutorials/data/documentation/appintents/appentity.json`,
retrieved 2026-11-04): `AppEntity` was introduced in iOS 16.0, and an entity query can be backed
by dynamic data. The app's deployment target is iOS 18.0 (`app/project.yml`), so this needs no
iOS 27 feature. Concrete shape:

- `WorkflowEntity: AppEntity` whose query lists **approved, non-disabled** definitions from the
  ledger (id + title). Disabled or draft definitions are not exposed.
- `StageWorkflowIntent: AppIntent` with a `WorkflowEntity` parameter, `openAppWhenRun = true`,
  whose `perform()` only *stages* the definition (contract `stageSaved`: one `awaitingUser`
  row per step, zero effects) and returns "Review in Pocket Glimmer to run …".
- Personal automations (Arrive, Time of Day, Charger…) built by the user in Shortcuts can then
  call this intent. Irreversible steps still wait for the in-app confirm, exactly as
  `EFFECT_RECOVERY_CONTRACT.md` requires for `ProactiveTriggerIntent` and as Grok also concluded
  for automations. The intent must never call `PhoneEffects.perform` for a person/money effect.

This is composition *by the user, in Shortcuts, over learned definitions* — the one place
composition already legally happens — and Grok's "Where composition can actually happen" table
credits user Shortcuts only with sequencing the app's fixed skills, not learned definitions.
Plan impact: **future slice after contract slice 2** (needs approved definitions to exist).
Device acceptance required; see verification section. Not a substitute for the in-app matcher.

### CORRECTION-3. "Planner = muse-spark-1.3 only" is a cost policy, not an API limit; the user's configured Standard model is ignored by that design

Grok (ranked finding 6; also line 142) and the contract (Screened planner, line 741) hard-code
the proposer to `muse-spark-1.3` only. Official Meta documentation fetched 2026-11-04 says more:

- `https://dev.meta.ai/docs/models`: `muse-wonder-1.0` is "Available (Standard mode only)" on
  pay-as-you-go; `muse-spark-1.3` is Standard, `muse-spark-1.3-contributor` is Contributor.
- `https://dev.meta.ai/docs/overview`: "Muse Wonder and Muse Spark take the same requests, so
  any example in these docs that uses Muse Spark also runs on Muse Wonder."
- `https://dev.meta.ai/docs/pricing-rate-limits` and `/docs/models`: in Standard mode content is
  not used to train Meta models; Contributor mode content may be, at a discount. Grok stated
  this correctly, and the code already enforces it: `MetaAPI.requireStandardMode`
  ([MetaMultimodal.swift](/home/habib/pocket-glimmer/core/Sources/PocketCore/MetaMultimodal.swift:38))
  is called in `OpenAICompatibleBrain.makeRequest` before transport, with a transport-counting
  test (`CloudBrainTests.testContributorModeIsRefusedBeforeTransport`).

Meanwhile the app already lets the user pick `muse-wonder-1.0`: it is in
`CloudPresets.metaModels` ([CloudBrain.swift](/home/habib/pocket-glimmer/core/Sources/PocketCore/CloudBrain.swift:73)),
pretty-printed in `AppModel.prettyProvider`, and free-typed in Settings
([SettingsView.swift](/home/habib/pocket-glimmer/app/PocketGlimmer/Views/SettingsView.swift:25)).
A planner that silently substitutes Spark for the user's configured Wonder inverts the user's
model choice (and this investigation's own assignment history shows why that substitution is
not the implementer's call). Correct slice-4 wording: proposer uses the user's configured
Meta model **if** it is a Standard-mode id; default remains `muse-spark-1.3` (cheaper, and the
structured-output pages exemplify it); any `*-contributor` id is refused by the existing guard.
Caveat: no live call was made, so Wonder's `response_format` behavior is documentation-claimed,
not observed. Keep the proposer behind the same fixture tests either way.
Plan impact: **small change to contract slice 4 text**; no reordering.

### NEW-4. Today's user-skill JSON path silently fails to route for novel app vocabulary

Grok analyzed user JSON as a trust problem (compiled registry fixes it). He did not trace its
routing ceiling, which is the practical limit on "discover useful flows" by dropping in a skill:

- `ActionPlanner.shouldUseSkills` enters the skill path only when `toolChoice` is `none`
  (or a `search_memory` + explicit-request special case)
  ([ActionPlanner.swift](/home/habib/pocket-glimmer/core/Sources/PocketCore/ActionPlanner.swift:64)).
- `explicitSkill` can override a trained tool only when the utterance contains a word from the
  hard-coded `overridable` table **and** a skill alias exactly equals that normalized word
  (ActionPlanner.swift:26–40). The tables list instagram/twitter/whatsapp/facetime/alarm/timer…
  and nothing else.
- Worked failure at baseline: user adds the documented `threads_dm` JSON (docs/SKILLS.md
  example). "DM Sam on Threads saying congrats" — if `toolChoice` picks `send_message` (its
  trained job), `overridable["send_message"]` has no "threads", the skill path never runs, and
  the user gets an iMessage plan to Sam instead of the Threads handoff. Retrieval would have
  found `threads_dm` first; it is never consulted. Only if `toolChoice` happens to say `none`
  does the new skill get picked.
- Consequence: "adding an ability is 10 lines of JSON" (docs/SKILLS.md) is true for retrieval
  and execution, false for routing whenever the trained tools claim the utterance first. This is
  a second, independent reason the exact-trigger / `stageSaved` path (contract slice 2) is the
  real learning mechanism, and it deserves an acceptance test Grok did not list:
  an approved definition whose vocabulary appears in no `overridable` table must still stage
  on exact trigger, and a near-miss must not.
Plan impact: **no change** — slice 2 already builds this; add the test.

### CORRECTION-5 (vs Grok, already corrected by the shared contract). Runtime output bindings, auto-disable, and content hash must not be implemented as Grok wrote them

Independent evidence strengthens the contract's corrections; implementers should follow
`EFFECT_RECOVERY_CONTRACT.md`, not LEARNED_WORKFLOWS, on these three points:

- Grok flow 3 binds `"$digest.deadline"` / `"$digest.when"` at run time (lines 366–367). There
  is nothing typed to bind from: `SkillRunner.run` returns a human status `String`
  ([ActionPlanner.swift](/home/habib/pocket-glimmer/core/Sources/PocketCore/ActionPlanner.swift:4)),
  `email_digest` returns prose bullets from `Assistant.reason`, and `Assistant.execute` returns
  display sentences. String-scraping a deadline out of a summary is exactly the unverifiable
  binding the delivery plan rejects (item 9). Bindings must materialize as concrete,
  user-visible title/date values on the review card before approval — which the contract's
  `BoundArgument` / `UserPause.outputBinding` already encodes.
- Grok auto-disables a definition after three failed/ambiguous runs (lines 256–261, test 10).
  The contract explicitly rejects automatic disable (lines 52, 762): a false-ambiguous cluster
  (e.g. three process kills) would silently kill a good workflow. User-only disable stands.
- Grok versions definitions by SHA-256 `content_hash` (line 254). The contract rejects a custom
  hash as a second identity mechanism (lines 51, 134): identity is `(definitionID, version)`
  plus stored canonical body bytes. Also, Grok's `testReadCanRetryAndHandoffCannot` lets a
  `started` read resume; the contract's rule is cleaner — reads are not attempts (line 754).
Plan impact: **none**; this delta confirms the governing document is the contract.

### NEW-6. Demonstration-specific masking gap: new names in shared text are not scrubbed by name

Grok and the contract agree the planner must wait for complete text-privacy screening
(delivery plan unit 1; contract Screened planner). The specific mechanism worth adding to the
privacy repair's acceptance list:

- `PrivacyScrubber.scrub` masks by regex patterns (email, SSN, card, phone, address) plus
  `knownNames` ([Scrubber.swift](/home/habib/pocket-glimmer/core/Sources/PocketCore/Scrubber.swift:11)).
- `knownNames` comes from Contacts only when authorization is `.authorized`/`.limited`
  (`AppModel.contactNames`) plus `MemoryStore.entityNames()`, which returns memory *subjects*
  only ([MemoryProfile.swift](/home/habib/pocket-glimmer/core/Sources/PocketCore/MemoryProfile.swift:54)).
- A demonstration is precisely where new people appear: "when Priya emails about the lease,
  remind me…" shared from Mail introduces a person who is in neither Contacts (yet) nor memory
  subjects. Her name leaves the device unmasked even after chunk-complete screening, unless the
  screening pass also extracts candidate names from the demonstration itself and feeds them to
  the scrubber (on-device only). The sensitivity decision can still say `ok` — it judges topic,
  not name coverage.
Plan impact: **one added regression case for the existing privacy-first unit** ("benign
demonstration naming a non-contact, non-memory person is name-masked in the captured request,
and still works"). No reordering; planner stays blocked until that unit ships.

## Independent findings (pre-Grok record, condensed)

These were recorded before reading LEARNED_WORKFLOWS. Each cites baseline evidence.

1. **No composition type exists.** `Skill` is one `SkillInvocation`
   ([Skills.swift](/home/habib/pocket-glimmer/core/Sources/PocketCore/Skills.swift:80));
   `PlannedAction` is one tool + `[String: String]`; `Assistant.execute` dispatches exactly one
   (ActionPlanner.swift:145–183). No steps, bindings, branches, or failure policy. Composition
   today happens only inside user-built Shortcuts or in unexecuted cloud prose.
2. **Registry shape at baseline:** 36 built-in skills — 14 URL, 9 Shortcut, 11 native,
   2 cloudReason (counted from `app/PocketGlimmer/Resources/Skills/builtin.json`). Retrieval is
   BM25 + alias-phrase bonus + trigram cosine, top ≤7, `skillPick` is zero-shot (no few-shot
   exemplars; `SkillsTests.testDynamicSkillPickSet` asserts one "Answer:"), τ = 0.90 guarded at
   boot ([AppModel.swift](/home/habib/pocket-glimmer/app/PocketGlimmer/AppModel.swift:130)).
   Every learned peer skill dilutes this 8-letter decision — hence exact triggers, not more peers.
3. **User skills load but are file-drop only.** `SkillSetup.registry()` merges
   `Documents/Skills/*.json` over the bundle (SkillIntents.swift:16–22); a later id silently
   replaces; one malformed file makes the whole user merge throw and vanish (`try?`); there is
   no version, author, provenance, or in-app authoring UI. `Skill` decode forces `confirm` only
   via `category.reachesOtherPeople` (message/social/email) — the hole Grok and the contract
   both close with the compiled catalog.
4. **Arguments are regex-per-(name, kind)** (`SkillArgs.extract`, ActionPlanner.swift:259–295),
   with hard-coded name cases; `.document` extracts nothing. New learned argument names degrade
   silently. Contact disambiguation via trained `contactPick` is the only typed binding.
5. **Memory cannot hold a workflow.** `MemoryStore` tables are `facts`, `corrections`,
   `memory_meta` (Memory.swift:110–120). The one learned behavior today, `instagram_autoreply`,
   is smuggled as a fact (`attribute: autoreply_rule`, SkillRunner.swift:106–107) and is inert:
   `ProactiveRules.defaults` matches only `needs_to_buy` / `promise` / `birthday` /
   `upcoming_trip` ([Proactive.swift](/home/habib/pocket-glimmer/core/Sources/PocketCore/Proactive.swift)).
   It can be recalled, never triggered. Grok noted the honest message; he did not note that no
   proactive rule ever reads the saved rule back.
6. **Cloud interface cannot carry a proposal today.** `CloudBrain.complete` is text-in/text-out;
   `OpenAICompatibleBrain.makeRequest` sends only model/max_tokens/messages and its response
   type decodes only `choices[0].message.content` (CloudBrain.swift:39–63). A `tool_calls`
   response (`finish_reason: "tool_calls"`, content null) becomes `CloudError.decode`. A
   structured proposer is a new request shape on the same endpoint, not a prompt trick — Grok
   reached the same conclusion.
7. **Privacy screening is prefix-sampled** (the reason the planner must wait): `Assistant.reason`
   shows sensitivity `text.prefix(400)` and scrubs `text.prefix(24_000)`; multimodal
   sensitivity context truncates photo OCR to 240 chars. Other workers own this repair; nothing
   in this report designs on current prefix behavior.
8. **Triggers are compile-time enums** (`TriggerKind`, `TriggerKindEntity`, `QuickSkill`);
   automations live in the user's Shortcuts, and the app cannot enumerate Shortcuts or verify a
   named `PG …` Shortcut exists — `IOSSkillRunner.runShortcut` knows only the `UIApplication.open`
   Bool (SkillRunner.swift:81–87). Entitlements are an empty dict; no `CFBundleURLTypes`, so no
   x-callback can be received today. Grok covered all of this accurately.
9. **Offline shape constraint:** definition-time cloud, execution-time local is the only model
   consistent with `offlineCapable` semantics and an empty `CloudSettings.chain()` when no key
   is stored. A workflow needing cloud per step dies in airplane mode; a workflow whose
   *definition* was cloud-proposed but whose steps are local skills runs fine offline.

## Official-document verification (retrieved 2026-11-04, no live API call)

| Claim | Official source | Status |
|---|---|---|
| Schema-constrained structured output: `response_format = {type: "json_schema", json_schema: {…}}`; decoding constrained, shape guaranteed, semantics not | https://dev.meta.ai/docs/structured-output | Verified from page body |
| Schema limits: depth 10; 5,000 properties; 120,000 chars of names/enum/const; 1,000 enum values default; no cyclic `$ref`; `strict` defaults false, `strict: true` validates the strict subset (HTTP 400 only then) | https://dev.meta.ai/docs/structured-output | Verified; Grok's numbers match, plus the >250-value single-enum 15,000-char cap he omitted (immaterial for a capability-id enum) |
| Tool calling: developer `tools[]`, model returns `tool_calls[]`, **the app executes locally**; `tool_choice` must be `"auto"` (`"none"`/`"required"`/named → HTTP 400); `parallel_tool_calls` defaults true; `max_tool_calls` caps built-ins only | https://dev.meta.ai/docs/tool-calling | Verified from page body; Grok accurate |
| Standard mode: content not used to train; Contributor (`*-contributor` ids): may be used to train, discounted | https://dev.meta.ai/docs/pricing-rate-limits , https://dev.meta.ai/docs/models | Verified |
| `muse-wonder-1.0` Standard-mode only (pay-as-you-go); Wonder and Spark "take the same requests" | https://dev.meta.ai/docs/models , https://dev.meta.ai/docs/overview | Verified; basis of CORRECTION-3 |
| Shortcuts URL scheme runs a saved shortcut by name: `shortcuts://run-shortcut?name=&input=text&text=`; no result channel on this URL | https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/ios | Verified from page body |
| x-callback: `shortcuts://x-callback-url/run-shortcut?…&x-success=&x-error=&x-cancel=`; success appends `result`, error appends `errorMessage`, cancel carries no output | https://support.apple.com/guide/shortcuts/use-x-callback-url-apdcd7f20a6f/ios | Verified from page body; **current code does not use it** and has no scheme to receive it |
| `AppEntity` for custom app types discoverable by Siri/Shortcuts; introduced iOS 16.0 | https://developer.apple.com/tutorials/data/documentation/appintents/appentity.json | Verified from Apple's documentation JSON; basis of NEW-2 |
| App Intents conceptual documentation body | https://developer.apple.com/documentation/appintents | **Unresolved**: page is JS-rendered and returned no extractable body in this pass; only the JSON endpoint above was readable |
| iOS 27 / 27.0.1 Shortcuts behavior (Describe a Shortcut, automation lists, Siri AI gates) | Grok cites https://support.apple.com/en-us/149076 and the versioned iOS 27 Shortcuts User Guide | **Not independently re-fetched in full.** My fetch of the Shortcuts User Guide confirms an iOS 27 guide exists; per-version feature claims remain Grok-sourced and, per the task constraints, no iOS 27.0.1 claim is device-substantiated. The delivery plan's warning stands: Siri AI developer preview is 27.3 beta, not 27.0.1, and must not be counted as available |
| Responses API `store: true` default | Grok cites https://dev.meta.ai/docs/protocols/responses | Not re-fetched; corroborated only by the in-repo comment and explicit `"store": false` in `MetaVision.makeSegmentRequest` (MetaMultimodal.swift:303–310). Contract already avoids Responses for the planner, so nothing depends on it |

No claim is made that any Meta model was called, that x-callback behaves as documented on a
current OS build, or that any App Intent was compiled — there is no Xcode here.

## Comparison matrix (Grok vs this pass)

| Topic | Grok | This pass | Class |
|---|---|---|---|
| Compiled capability registry; model/user JSON cannot set effect/confirm/compensation | Proposed | Agree; contract refines it | Already covered |
| Durable definitions/runs/steps, claim-before-perform, no replay of `started` irreversible steps | Proposed | Agree; contract's attempt model supersedes details | Already covered |
| Exact user-approved trigger bypasses skillPick and τ | Proposed | Agree, plus NEW-4 routing evidence and a missing acceptance test | Already covered + new detail |
| Correction learning (`recordCorrection`/`reflexContext`) | Absent | Dead code in production; cheapest demonstration stream; must not be wired into frozen prompts | **NEW-1** |
| Learned flows inside Shortcuts automations | Fixed intents only | Dynamic `WorkflowEntity` + stage-only intent | **NEW-2** |
| Planner model | `muse-spark-1.3` only | Honor user's configured Standard model; Spark default; Wonder is Standard-only and request-compatible per Meta docs | **CORRECTION-3** |
| Runtime `$digest.*` output binding | Flow 3 uses it | Impossible over `String` status returns; materialize concrete values at review (contract agrees) | Correction, already in shared contract |
| Auto-disable after 3 ambiguous runs; SHA-256 content hash; `started`-read resume | Proposed | Rejected by contract; confirmed rejected here | Correction, already in shared contract |
| Demonstration name masking | Generic "scrubber + sensitivity" | New-person-in-demonstration gap in `knownNames` construction | **NEW-6** (detail) |
| Muse structured output / tool-calling limits | Detailed | Re-verified against official pages; all numbers match | Already covered, verified |
| x-callback, Describe a Shortcut, automations, no-other-app-intents | Detailed | Re-verified URL/x-callback from Apple Support; iOS 27 specifics left Grok-sourced, device-unverified | Already covered, partially verified |
| `calendar_find` "today" mismatch; identifier-discarding EventKit saves; in-memory `ChatItem.pending` | Detailed | Agree (read in source) | Already covered |
| Autoreply rule saved but inert | Honest-message note | Stronger: no `ProactiveRule` ever matches `autoreply_rule`; saved rules cannot fire | New detail on covered ground |
| Fireworks key "ignored" | Stated | At `009430f` there is no Fireworks key storage in the app at all (comment removed); statement is vestigial, behavior unchanged | Minor correction, immaterial |

## Concrete end-to-end flows (incorporating the deltas)

**A. Save from a real run (demonstration = your own confirmed action).**
"Text Mom I'll be home by 8" → trained path clarifies at τ on the rehearsal engine, or plans
`imessage_send` → user confirms → Messages sheet → `.sent`. User: "Save that as Running late to
Mom." The draft definition is built from the *ledger attempt* (capability `imessage_send`, bound
contact identifier, body) — not from re-parsing the sentence. Review card shows the compiled
sentence ("I can tell you that you tapped Send in Messages. I cannot tell you it was delivered.").
Approve → version 1. Later, exact utterance "running late to mom" stages a fresh card via
`stageSaved`; nothing sends until Confirm. Failure cases: contact renamed/deleted → token
re-resolve fails → `needsUser`, never "first Sam". Process killed after claim → attempt stays
unresolved; no second sheet. This flow needs NEW-1's signal capture only for the *offer*
("Save that?"), not for correctness.

**B. Learned flow inside a user automation (NEW-2).**
User approves "Wind down tonight" (calendar read + reminder). In Shortcuts, the definition now
appears as a `WorkflowEntity`; the user builds "When I arrive home → Stage Pocket Glimmer
workflow: Wind down tonight". The automation fires with the phone locked: the intent stages
awaitingUser rows and posts a notification; no reminder is written yet. User opens the app,
reviews the staged card (concrete time, not "tomorrow-ish"), confirms; EventKit save + read-back
commits. Failure cases: definition disabled after staging → staging refuses and says so;
automation fires twice → two distinct `UserRequestID`s, duplicate hint shown, no dedupe by
title/time (contract rejects title/minute identity).

**C. Muse-proposed flow (after privacy repair only).**
Online, Meta key in Keychain, user asks "Make me a flow: when I share an email, pull the deadline
and remind me." The full shared text is chunk-screened (`ScreenedPrompt` from the privacy unit;
NEW-6 name extraction included); `sensitive` → no request, local explanation. Otherwise one
Chat Completions call (user's configured Standard model, Spark by default;
`response_format` json_schema, `strict: true`; no `tools`, no built-in search) returns a
proposal. Local `validate` drops any effect/confirm/permission keys, rejects unknown capability
ids, and — per CORRECTION-5 — rejects `$…` bindings: if the proposal wants a reminder from the
digest, the *user* supplies or confirms concrete title/date on the card (possibly pre-filled by
a separately validated extraction the user edits). Approve stores an immutable version.
Execution thereafter is fully local and works offline. Failure cases: prose instead of JSON →
"no plan", nothing stored; unknown id `tap_send` → validation error shown, nothing stored;
contributor model id configured → refused before transport by the existing guard (existing test).

**D. Novel-vocabulary user skill (NEW-4, today's failure).**
User drops `threads_dm` JSON in Files. Today "DM Sam on Threads" can be hijacked by trained
`send_message`. After slice 2, the user instead approves trigger "dm on threads" bound to the
user-handoff capability (floor `always`, evidence `systemAcceptedURL` only); exact trigger
stages the handoff card regardless of `toolChoice`. The status copy still says "opened profile;
message on clipboard" — never "sent".

## Failure and recovery cases (delta-relevant only; contract owns the full state machine)

- Clarification pick as signal: user taps "Instagram DM" in a future tappable clarify UI →
  record (decision type, utterance hash/context, wrongID, correctID) in the ledger. Never feed
  into `Reflex.decide` context (frozen prompts). Use it only to offer "Always use Instagram DM
  for 'dm … on instagram'?" → an approved exact/pattern binding the user creates, not a silent
  prior change.
- Trigger collision: `SkillRegistry.norm` lowercases and strips punctuation, so "Running late,
  Mom!" and "running late mom" are the same trigger. `matchExact` staging is safe (cards, not
  effects), but two definitions sharing a `triggerNorm` must be rejected at `approve` — the
  contract's schema has no unique index on `trigger_norm`; add that validation explicitly.
- Entity staleness (NEW-2): definition disabled or superseded between Shortcuts listing and
  intent perform → intent re-reads the ledger at perform time and stages only an approved,
  enabled, exact version; otherwise returns a plain failure string to Shortcuts.
- Model substitution (CORRECTION-3): Settings model id edited to a contributor id → planner
  refuses (existing guard); edited to a non-Meta BYOK id → planner does not follow
  `CloudBrainChain` (Grok and contract agree); planner is Meta-endpoint-only.
- SharedInbox expiry mid-flow: unchanged from Grok — copy shared text into the run at staging
  or pause `needsUser`; never `take()` later.

## Smallest implementable changes (ordered; this report implements none)

1. Nothing new before contract slice 1 and the privacy unit — the plan's ordering is right.
2. Slice 2 additions (small): reject duplicate `triggerNorm` at `approve`; add NEW-4 acceptance
   test (novel-vocabulary approved definition stages on exact trigger).
3. Slice 4 wording change (CORRECTION-3): proposer model = user's configured Standard-mode
   Meta model, default `muse-spark-1.3`; document Spark-only as cost choice if the implementer
   prefers, not as an API constraint.
4. Privacy unit addition (NEW-6): on-device candidate-name extraction from demonstration text
   into the scrubber's name set, with a captured-request regression.
5. Future slices: (a) NEW-1 signal capture on Confirm/Cancel/clarify-pick into the ledger,
   powering "Save that run?" offers and per-definition failure counts — ledger/profile only,
   never Reflex prompt injection; (b) NEW-2 `WorkflowEntity` + stage-only intent, after slice 2.
6. Explicitly do **not** implement from Grok: runtime `$digest.*` bindings, three-strike
   auto-disable, SHA-256 identity, `started`-read auto-resume, Fireworks/BYOK planners,
   built-in web search or computer use in the planner.

## Verification and device acceptance still needed

Linux/PocketCore (no device): file-backed reopen tests from the contract; duplicate-trigger
rejection; NEW-4 routing test with a recording executor; proposer fixture tests (prose → no
plan, unknown id → rejected, effect key dropped, contributor id → zero transport, sensitive
screen → zero transport) using a fake transport — never a paid call in CI.
Device (iOS 27.0.1, signed build — none exists yet): x-callback return to a declared scheme
including lock-mid-run; Describe a Shortcut paste-and-name round trip; NEW-2 entity visibility
in the Shortcuts editor and an Arrive automation staging without opening the app; Email/Message
automation delivery of sender/body into `ProactiveTriggerIntent`; EventKit identifier read-back
and kill-between-claim-and-receipt behavior. A Simulator or XCUITest pass closes none of these.

## Disconfirming evidence and what could not be established

- Disconfirming "learning already works": the corrections writer has no production caller
  (grep at `009430f`); the autoreply rule has no proactive reader; `ChatItem.pending` is
  process memory. Any claim that the app currently learns workflows is false.
- Disconfirming "just add JSON skills": NEW-4's routing tables show retrieval is not routing.
- Disconfirming "structured output makes proposals safe": Meta's own page guarantees shape,
  not semantics; `strict` defaults to false and only validates schema form. Local capability
  validation remains the authority (Grok said this too).
- Not established: any iOS 27.0.1 runtime behavior; Wonder's live structured-output behavior;
  x-callback delivery on a current OS; AppEntity query performance/limits with many definitions
  (Apple's readable JSON confirms the protocol and iOS 16 introduction, nothing about scale);
  whether Shortcuts on the target OS hands intent return values onward as Grok describes. The
  App Intents conceptual pages could not be read in body form here (JS-rendered), so AppEntity
  is verified at symbol level, not guide level.
- Not re-run: the PocketCore test suite at `009430f` (research-only pass; other workers have
  the tree). Grok's cited rehearsal numbers were read, not reproduced.

## Bottom line for the delivery plan

Keep the plan's order (privacy → attempt journal → reviewed definitions → screened Muse →
callbacks). Amend slice 4's model rule (CORRECTION-3), add two acceptance details
(duplicate `triggerNorm`; NEW-4 routing test; NEW-6 masking regression counts as the third),
and queue NEW-1/NEW-2 as post-slice-2 future work. Everything else in Grok's report that this
pass could check, checked out.
