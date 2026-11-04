# INDEPENDENT NOTES — recorded BEFORE reading docs/research/LEARNED_WORKFLOWS.md
# Investigator: Muse Wonder 1.0 (muse-wonder-1.0, max), 2026-11-04
# Baseline: 009430f. Sources read directly: Skills.swift, ActionPlanner.swift, Assistant.swift,
# CloudBrain.swift, MetaMultimodal.swift, Memory.swift, MemoryProfile.swift, Scrubber.swift,
# Decision.swift, Reflex.swift, Telemetry.swift, Proactive.swift, SkillRunner.swift, SystemActions.swift,
# SkillIntents.swift, Intents.swift, AppModel.swift, SettingsView.swift, SkillsTests, CloudBrainTests,
# project.yml, entitlements, builtin.json (36 skills: 14 url, 11 native, 9 shortcut, 2 cloud).
# Official docs fetched 2026-11-04: dev.meta.ai/docs/structured-output, /docs/tool-calling,
# /docs/models, /docs/pricing-rate-limits; support.apple.com Shortcuts URL scheme + x-callback-url;
# developer.apple.com/documentation/appintents (JS-rendered, body not extractable — treat as unresolved).

## I-1 No composition type exists
Skill (Skills.swift:80-126) = ONE SkillInvocation (url|shortcut|native|cloudReason). PlannedAction
(Assistant.swift:10-14) = one tool + [String:String]. Assistant.execute (ActionPlanner.swift:145-183)
dispatches exactly one. No steps[], no $prev binding, no branch/loop, no onFailure. Composition today
can only happen inside a user-built Shortcut (outside app) or in cloud free text (unexecuted).

## I-2 User skills exist but are file-drop only, unversioned, trust-by-location
SkillSetup.registry() (SkillIntents.swift:16-22) loads bundle builtin.json + merges Documents/Skills/*.json.
SkillRegistry.merge/add (Skills.swift:198-204): later id silently replaces. Skill has NO version, author,
provenance, signature, minAppVersion. decodeSkills (208-222): one bad file throws whole merge (caught try?
in registry() -> user skills silently absent). confirm forced only via category.reachesOtherPeople
(Skills.swift:11-12,183) — a user JSON with category=device + invocation=url tel:{phone} or uber URL would
NOT inherit spend/call confirm unless JSON sets confirm:true. Native handler string is free-form: unknown
handler falls to "isn't available" (SkillRunner.swift:111-112) but executorTools routing
(ActionPlanner.swift:19-20,151-152) means a user skill claiming native send_message/create_reminder etc.
gets real EventKit/MessageUI execution with ITS argSchema/examples driving skillPick — trust boundary is
"user dropped file in own Files app", acceptable for sideload, NOT for discovered/shared/imported skills.

## I-3 Routing ceiling makes naive learned-skill growth self-defeating
OptionSet letters A-H max 8 options (Decision.swift:33,36). skillPick = top<=7 candidates + ask
(Decision.swift:139-144), zero-shot: no FewShot for skillPick (shots list has none; SkillsTests:71-84
asserts exactly one "Answer:"). Retrieval = BM25 field-weighted + alias phrase + trigram cosine, filter
score>0.6 then >=0.3*top (Skills.swift:262-279, ActionPlanner.swift:69-73). tau=0.90 bundled
(AppModel.swift:130-139 guards). optionLabel <=72 chars (Skills.swift:120-125). Every learned workflow
added as a peer skill dilutes retrieval + pick. Learned flows therefore need EXACT-KEY invocation
(user-approved trigger phrase -> id, bypassing skillPick) or namespace/hierarchy, not more peers.
Also ActionPlanner.explicitSkill/overridable + explicitRequest are hard-coded word tables
(ActionPlanner.swift:26-56) — learned skills with new app words won't override trained tools unless
their alias exactly matches overridable word for that tool (explicitSkill requires alias==word).

## I-4 Argument binding is regex-per-(name,kind), no typed outputs to bind
SkillArgs.extract (ActionPlanner.swift:259-295): switch on (spec.name, spec.kind), hard-coded cases
(reply/trigger/name/n/subject/data/show...). New arg names fall to kind defaults; .document -> nil always.
SkillRunner returns String status only (Skills: ActionPlanner.swift:4-6 protocol returns String) — there
is no typed step output to feed step N+1, only human-readable status text ("Opened...", "Handed to
Shortcut..."). Any $step.output binding over these strings would be string-scraping. Honest binding
sources today: args dict, SharedInbox text (single slot, 15min, Skills.swift:286-302), memory facts.

## I-5 Memory cannot store a workflow; corrections learning loop is dead code in production
MemoryStore schema (Memory.swift:110-120): facts, corrections, memory_meta only. ExtractedFact is
(subject,attribute,value,text) — a workflow could only be smuggled as value string (autoreply_rule does
exactly this, SkillRunner.swift:106-107). MemoryStore.recordCorrection + reflexContext
(Memory.swift:208-242) are implemented + unit-tested (CuratorMemoryTests:31-46) but grep shows NO
production caller: Assistant.decide calls never wrap context with reflexContext, App UI never calls
recordCorrection (ChatView confirm/cancel in AppModel.swift:233-260 discards outcome). So "learns from
your corrections" is presently false at app level; only profileOnePager replays decisionCorrections
as text (MemoryProfile.swift:80-89) IF rows existed — they can only be created by tests/pg-cli.
ProactiveRules.defaults (Proactive.swift) match needs_to_buy/promise/birthday/upcoming_trip ONLY:
a saved autoreply_rule fact is never matched -> saved-but-inert (matches SkillRunner's honest message).

## I-6 Cloud interface cannot carry a structured proposal today
CloudBrain protocol (CloudBrain.swift:14-18): complete([ChatMessage],maxTokens)->CloudAnswer{text}.
OpenAICompatibleBrain.makeRequest (41-53) sends only model/max_tokens/messages; Resp (39) decodes only
choices[0].message.content: tool_calls + finish_reason="tool_calls" would decode as missing content ->
CloudError.decode. requireStandardMode (MetaMultimodal.swift:38-40) refuses *-contributor BEFORE
transport (CloudBrainTests:6). OFFICIAL (fetched 2026-11-04): dev.meta.ai/docs/structured-output —
response_format={type:json_schema,json_schema:{...}} constrains decoding, shape guaranteed not semantics;
strict defaults false, strict:true validates schema subset else HTTP400 only then. /docs/tool-calling —
tools[] function defs, model returns tool_calls[], APP executes locally, parallel_tool_calls default true,
max_tool_calls caps built-ins only. /docs/models — muse-spark-1.3 Standard, muse-spark-1.3-contributor
Contributor, muse-wonder-1.0 "Available (Standard mode only)" pay-as-you-go; /docs/pricing-rate-limits —
Standard: content not used to train; Contributor: may be used to train, discounted. Current code's
metaModels list (CloudBrain.swift:73) = spark-1.3, wonder-1.0, spark-1.3-contributor — and Settings lets
user type ANY model id (SettingsView.swift:25) — requireStandardMode is the only guard, and it lives in
makeRequest so BYOK custom endpoint (CloudPresets.custom, no MetaAPI check path? makeRequest calls
requireStandardMode regardless of provider — yes line 42, so contributor refused even on custom endpoint
whose model naming may legitimately contain "contributor" substring -> false positive, minor).

## I-7 Privacy screening is prefix-sampled; a demonstration-ingesting planner cannot reuse it
Assistant.handle escalate (Assistant.swift:155-182): sensitivity decision context = "User: \(utterance)"
only; scrub applies to profile+mem+utterance. ActionPlanner.reason (187-202): sensitivity sees
instruction + text.prefix(400); scrub sends text.prefix(24000); beyond-24k never screened NOR sent
(local window 2500). MultimodalGate.sensitivityContext truncates photo OCR to 240 chars
(MetaMultimodal.swift:~600). => Any "learn from this document / these messages" planner MUST wait for
complete-text screening (chunked sensitivity+scrub over full input) before any cloud call; reusing
reason() for demonstrations would ship unscreened tails if limits change. (Task notes other workers are
repairing privacy — flag dependency, do not design on current prefix behaviour.)
Also cloudScrubber knownNames = contacts (authorized/limited only) + memory entityNames (subjects only,
MemoryProfile.swift:54-56) — a demonstration naming a NEW person not in Contacts/memory is not masked
by name, only by EMAIL/PHONE/CARD/SSN/ADDRESS patterns (Scrubber.swift:11-18).

## I-8 Triggers: fixed enums in code, user automations live outside the app
TriggerKind (Proactive.swift:5-8) + TriggerKindEntity (Intents.swift:6-11) fixed; ProactiveTriggerIntent
openAppWhenRun=false. Users create automations in Shortcuts app pointing at this intent — app cannot
create/edit automations, cannot enumerate user's Shortcuts, cannot verify a named PG Shortcut exists:
IOSSkillRunner.runShortcut (SkillRunner.swift:81-87) knows only UIApplication.open(url) Bool.
Apple official (support.apple.com, fetched 2026-11-04): shortcuts://run-shortcut?name=&input=text&text=
runs a saved shortcut; shortcuts://x-callback-url/run-shortcut?...&x-success=&x-error=&x-cancel= exists
in Shortcuts User Guide — CURRENT code does NOT use x-callback, so no completion/output callback is
received today. Even x-success only proves Shortcuts handed control back per callback contract, not
that inner actions succeeded — must verify on device. create-shortcut URL opens editor (Skills.swift:437);
no public API writes a Shortcut definition (docs/SKILLS.md:438 note agrees). AppShortcutsProvider:
exactly ONE provider, 4 shortcuts currently (Intents.swift:48-56); QuickSkill enum fixed 7 cases
(SkillIntents.swift:80-98) — learned workflows CANNOT become Siri phrases dynamically; AppEnum is
compile-time. Dynamic surfacing would need AppEntity for learned workflows (not present).

## I-9 Capability discovery is self-declared; no ground truth, no entitlement surface
Entitlements file = empty <dict/> (PocketGlimmer.entitlements). project.yml deploymentTarget iOS 18.0,
no LSApplicationQueriesSchemes generated (Support/ has no Info.plist; project.yml info.properties lacks
it) -> canOpenURL-based probing of arbitrary schemes is not available as written; code only uses
UIApplication.open (ComposeSheets.open, SystemActions.swift) whose Bool = "system accepted URL", used
honestly in status strings. Weather skill note itself says WeatherKit needs paid entitlement and routes
via Shortcut instead (Skills.swift:476-478). Discovery sources that ARE trustworthy today: (a) registry
JSON on disk, (b) Contacts/EventKit authorization-gated queries, (c) user naming a Shortcut (unverifiable),
(d) App Intents the app itself ships. No OS API lists user's installed Shortcuts or other apps' intents
to this app (by design; cannot cite Apple page body — developer.apple.com JS-rendered, UNRESOLVED).

## I-10 What "demonstration" can mean within public APIs (no GUI automation)
Available demonstration channels, all already partially present: (1) typed/voiced utterance (Assistant.handle;
voice via MultimodalGate.transcribe -> handle, transcript unscreened until handle's own gates);
(2) share-sheet text/file via HandleTextIntent -> SharedInbox single-slot 15-min (SkillIntents.swift:43-77);
(3) document picker PDF/txt/md (SkillRunner.swift:137-166); (4) user-authored Shortcut + named PG recipe;
(5) Files-dropped skill JSON; (6) confirm/cancel taps on PlannedAction (AppModel.confirm/cancel) — currently
discarded signals, the cheapest real demonstration stream; (7) telemetry decisions table (Telemetry.swift)
logs decision contexts on device, export is user-initiated file only. NOT available: observing taps in
other apps, reading Mail/Instagram, recording a macro, importing a .shortcut definition programmatically.

## I-11 Local-first usefulness constraint
skillPick/retrieval/args/confirm all run offline on 1B + regex; cloudReason skills degrade: reason()
falls back to local truncated window + disclosure (ActionPlanner.swift:199-201). A learned workflow whose
DEFINITION was authored by cloud is fine offline IF definition is data (steps of local skills); a workflow
whose EXECUTION needs cloud per-step dies offline. Definition-time cloud, execution-time local is the
only shape consistent with offlineCapable flags (Skill.swift:88-89) and CloudSettings.chain() empty when
no key (AppModel.swift:282-291).

## I-12 Versioning/migration precedent exists for memory, not skills
MemoryStore init does PRAGMA table_info migrations (Memory.swift:121-125); TelemetryLog same
(Telemetry.swift:52-55). Skill/SkillRegistry have no schemaVersion; SkillRegistry.json() (Skills.swift:225-228)
exports {skills:[...]} sortedKeys — a round-trip exists (SkillsTests:30-48). Calibration guard in
AppModel.boot (130-139) hard-fails on mismatched calibration — precedent for fail-closed version checks.

UNRESOLVED at independent stage: Apple App Intents entity/dynamic-phrase limits from primary body text;
iOS 27.0.1 specifics (no Xcode/device here; project targets iOS 18.0); whether x-callback-url still
behaved as documented on current OS; Meta structured-output schema size/depth limits detail;
whether muse-wonder-1.0 supports response_format/tools identically to spark-1.3 (models page lists
availability, capability pages use spark-1.3 examples).
