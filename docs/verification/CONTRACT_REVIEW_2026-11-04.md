# Independent review — action contracts, recovery, packaging

Reviewer: DeepSeek V4.1 Flash 1017 through River 08 / OpenCode at max.
Checkout: `/home/habib/.t3/worktrees/pocket-glimmer/t3-fecb781d` at `b41ffae` (working tree clean).
Scope: `git diff 4bf72c9..b41ffae -- core app ios`, with the recovery (`1507e36`), validation
(`8c990e4`), and packaging (`11c07cf`) commits treated as the focus.
No repository edits, commits, pushes, PRs, paid services, or subagents. Repros live in a
scratch copy of `core` under `/tmp/pocket-glimmer-takeover/contracts-review-v1/core`; the
tracked checkout remains clean.
No Mac, Xcode, iPhone, or live Meta API request was available to this session. Every Mac
statement is Linux/mock-fixture level. Fake executors are contract tests, not phone proof.

## Verdict

- **Action/privacy correctness: FAIL (not release-ready).** Four reachable defects remain:
  an immediate read hides the exact cloud payload after a provider failure; shared documents
  are ignored by the default share intent whenever the route is not `tool`; calendar writes silently
  drop duration/attendee/location constraints and act without a card; and common time phrases
  are rewritten to a different day/time or reduce multiple times to the first one.
- **Linux core verification: PASS.** 183 Swift tests executed, 1 opt-in live test skipped, 0
  failures; 22 Python tests pass; the compiled contract manifest and bundled skill registry
  regenerate identically; app syntax parsing passes for 18 files. Syntax only, not typecheck.
- **Mac packaging gates: PASS at shell/mock level.** All 84 fixtures pass, including the
  prior false passes (zero-byte executable, no bundled model, symlinked framework). No Xcode
  build, Mach-O proof, install, or device run exists.
- **Prior repair scorecard:**
  - Partner-name cloud masking: **PASS** for the reported partner-value path (`entityNames`
    now adds `partner`/`name` values; regression test passes). This is a deterministic masking
    path with a scripted classifier, not a detection-quality guarantee.
  - Provider cancellation: **PASS** (`CloudBrainChain` checks cancellation before each provider
    and rethrows `CancellationError`/`URLError(.cancelled)`; two-provider test passes).
  - Invalid cloud settings: **PARTIAL.** Empty/malformed values no longer create a brain, but
    Settings shows no visible error and an arbitrary nonempty Meta model id is still accepted.
  - Local fallback: **PARTIAL.** Text-chat and confirm-read fallbacks keep the payload; the
    immediate reply-only read path loses it in `AppModel`, and attempted providers are not
    recorded at all.
  - Mac packaging/model precedence: **PASS at Linux/mock level**; the operator docs still say
    Documents is checked first and still describe an unbundled arbitrary `.gguf`, both false
    after `verifyShippingModel`.
  - Busy-input durable staging: **OPEN, as recorded.** `AppModel.send` still refuses while busy.
    No false completed claim was found in the ledger or docs for this item.

## Findings

### C1 — Critical: an immediate cloud-read fallback hides the exact outbound payload

**Location**
- `core/Sources/PocketCore/ActionPlanner.swift:289-315` — `reason()` keeps
  `ReadResult.cloudPromptSent` when a cloud read fails and a local answer is produced.
- `core/Sources/PocketCore/ActionPlanner.swift:178-181` — the immediate read returns
  `.local(result.text)` while `read = result` keeps the payload.
- `core/Sources/PocketCore/Assistant.swift:148-163` — `AssistantTurn.cloudPromptSent` is set
  from `readResult`.
- `app/PocketGlimmer/AppModel.swift:236-242` — the `.local` case does **not** copy
  `turn.cloudPromptSent` into `ChatItem`; only `.cloud` and `.offlineFallback` do.
- `app/PocketGlimmer/Views/ChatView.swift:93-101` — the privacy sheet button is shown only when
  `item.cloudPromptSent != nil`.
- `docs/ACTION_VALIDATION.md:45-48` claims the fixes "preserve outbound-payload visibility when
  a cloud failure falls back locally."

**Reachable call chain**
1. A share/read request reaches `ActionPlanner.planSkillCore` for a reply-only skill such as
   `summarize_text`, `analyze_document`, or `translate`.
2. `execute` → `readSkill` → `reason` with long shared text. `CloudTurnComposer.prepareDocument`
   prepares and screens the turn; `turn.send` throws a non-cancellation provider error.
3. `reason` catches it, calls `localReason`, sets `result.cloudPromptSent = turn.sentText`, and
   returns a `ReadResult` with `provider == nil`.
4. `planSkillCore` assigns `read = result` and returns `.local(result.text)`.
5. `Assistant.handle` returns `AssistantTurn` with `cloudPromptSent` set; `AppModel.send`'s
   `.local` branch drops it. The chat shows `on device · N ms`, no privacy button, and no
   access to the text that actually left the device.

**Evidence**
`repro/ReviewRepros.swift::testImmediateReadCloudFailureKeepsPayload`, run in the scratch copy:

```text
READ_FALLBACK provider=nil cloudPromptSent=true withheld=false
READ_FALLBACK_TEXT=LOCAL_SUMMARY
(On device: read the first 2500 characters; cloud unavailable.)
```

The core result is correct; the app projection is the defect. The confirm-read path does
preserve it (`AppModel.swift:274-280`), so this is specifically the immediate read path.

**Fix**
In `AppModel.send`'s `.local` case, pass `cloudPromptSent: turn.cloudPromptSent`. When it is
non-nil, use a badge that says the answer is local after a failed cloud attempt (for example
`local fallback · best effort`) rather than `on device`. Add a projection test so a future
`ChatItem` initializer cannot drop the field again.

### C2 — Critical: shared documents are ignored by the default share intent on non-tool routes

**Location**
- `app/PocketGlimmer/Intents/SkillIntents.swift:63-67` — the intent builds `body` (including
  PDF text) and calls `AppModel.send(ask, sharedText: body, source:)`.
- `app/PocketGlimmer/Intents/SkillIntents.swift:71-75` — for a non-mail share the utterance is
  the instruction unchanged; the default instruction is `"Summarize this"`.
- `core/Sources/PocketCore/ActionPlanner.swift:44-55` — `explicitRequest` does not contain
  `"summarize this"`, `"summarize what I just shared"`, or a generic `"analyze this"`.
- `core/Sources/PocketCore/Assistant.swift:99-107` — `skillOverride` only runs when the route is
  not `tool` **and** `isExplicitRequest` is true.
- `core/Sources/PocketCore/Assistant.swift:167-177` — `answer_local` generates from the
  utterance only; `sharedText` is not used.
- `core/Sources/PocketCore/Assistant.swift:187-210` — `escalate_cloud` calls
  `prepareReply(profile:facts:utterance:...)`; `sharedText` is not used.
- Only the `tool` path (`Assistant.swift:159-160` → `planSkill` → `readSkill`) consumes
  `sharedText`.

**Reachable call chain**
1. Share a PDF or text into Pocket Glimmer with the default instruction "Summarize this".
2. `HandleTextIntent` calls `AppModel.shared.send("Summarize this", sharedText: body)`.
3. `Assistant.handle` runs the trained route. `isExplicitRequest("Summarize this")` is false,
   so `skillOverride` returns nil. If the route is `answer_local` or `escalate_cloud`, the
   branch never reads `sharedText`.
4. The app answers from local memory or sends only the utterance to the cloud. The shared
   document is neither analyzed nor mentioned. On `answer_local`, the user gets a plausible
   generic reply; on `escalate_cloud`, the cloud answer is also generic.

**Evidence**
`repro/ReviewRepros.swift::testShareTextIgnoredWhenRouteAnswerLocal` and
`::testShareTextIgnoredWhenRouteEscalatesCloud`:

```text
SHARE_ANSWER_LOCAL_REPLY=local("LOCAL_ANSWER")
SHARE_ANSWER_LOCAL_MARKER_IN_PROMPT=false
SHARE_CLOUD_REPLY=cloud("cloud answer", provider: "Meta Model API · muse-spark-1.3")
SHARE_CLOUD_MARKER_IN_BODY=false
```

`SHARE_CLOUD_MARKER_IN_BODY=false` is the failure: the cloud request body did not contain the
shared document. The test uses a scripted route, but the branch logic is deterministic.

**Fix**
Make the share intent produce an explicit request (`"summarize this document"` for a file,
`"summarize these emails"` for mail) and add those phrases to `explicitRequest`, **and** add a
guard in `Assistant.handle`: when `sharedText != nil`, route deterministically to
`analyze_document`/`email_digest`/`summarize_text` through the existing staged-read path rather
than allowing `answer_local`/`escalate_cloud` to ignore it. For a cloud document path, use
`CloudTurnComposer.prepareDocument` so the same screening applies. Add core tests for
`answer_local` and `escalate_cloud` with a unique marker.

### C3 — Critical: calendar writes silently drop duration, attendee, and location constraints

**Location**
- `core/Sources/PocketCore/ActionValidation.swift:112-114` — the only calendar constraint
  guard matches `for <digits> hours?|minutes?`, `until`, `ending`, `ends at`, `invite`,
  `attendees`, and `from <digit> ... to <digit>`. It does not match `2-hour`, `for 2 hrs`,
  `for 90 min`, `for 1.5 hours`, `a 90-minute`, `3pm-5pm`, `with Sam`, or `at the office`.
- `core/Sources/PocketCore/Assistant.swift:436-438` — `ArgumentExtractor.heuristic` stops
  the title at `at`/`with`; "Schedule a meeting with Dana tomorrow at 3pm" becomes title
  "meeting", and the attendee is gone.
- `core/Sources/PocketCore/EffectLedger.swift:520-522` — `calendar_create` has confirmation
  floor `modelMayAct`.
- `core/Sources/PocketCore/EffectLedger.swift:1463-1483` — with no pause, no hint, and no
  model-asked confirmation, the event is performed immediately; no card is shown.
- `app/PocketGlimmer/Actions/PocketEffects.swift:196-214` — every EventKit event gets
  `endDate = start + 3600`, and no location or attendees.

**Reachable call chain**
`Assistant.toolPath`/`planSkillCore` → `ActionValidation.requestIssue` returns nil →
`EffectSession.evaluate` → `mustCard == false` → `perform` → `PocketEffects.performEvent` saves
a one-hour event. The summary is only `"Event “…” saved for …"`; it does not say the duration
was changed or an attendee/location was dropped.

**Evidence**
`repro/ReviewRepros.swift::testCalendarTwoHourSilentOneHour`:

```text
CAL_TWO_HOUR_REQUEST_ISSUE=nil
CAL_TWO_HOUR_EXTRACTED=["title": "2-hour planning meeting", "when": "tomorrow at 3pm"]
CAL_TWO_HOUR_RESULT=finished(... committed(eventKitItem(... title: "2-hour planning meeting"...)))
CAL_TWO_HOUR_SUMMARY=Event “2-hour planning meeting” saved for Thursday, Nov 5, 2026 at 7:49 PM UTC. ...
```

`::testCalendarAttendeeAndDurationVariantsBypassGuard` confirms the guard is nil for:

```text
Schedule lunch with Sam tomorrow at noon        -> when "tomorrow", title "lunch"
Schedule a meeting with Dana tomorrow at 3pm    -> when "tomorrow at 3pm", title "meeting"
Schedule a meeting for 2 hrs tomorrow at 3pm    -> when "tomorrow at 3pm", title "meeting for 2 hrs"
Schedule a meeting for 90 min tomorrow at 3pm   -> when "tomorrow at 3pm", title "meeting for 90 min"
Schedule a 90-minute meeting tomorrow at 3pm    -> when "tomorrow at 3pm", title "90-minute meeting"
Schedule a meeting 3pm-5pm tomorrow             -> when "tomorrow", title "meeting 3pm-5pm"
Schedule a meeting at the office tomorrow at 3pm -> when "tomorrow at 3pm", title "meeting"
```

The fake adapter records the committed event and the real adapter uses the same fixed +3600
end. Its printed start time is a stub (`now+1h`), not the requested 3pm; a real EventKit run
still needs to show the 3pm start. The immediate no-card path and the fixed one-hour end are
what are verified here.

**Fix**
Either (a) extend `requestIssue` to reject every common duration/range/attendee/location
form until those fields exist, or (b) add typed `duration`/`location`/attendee fields and
honour them. Until then, set `calendar_create`'s confirmation floor to `.always` so the
one-hour/no-invitation review is always shown; the current immediate act bypasses the only
place the limitation is disclosed at execution. Add the strings above to
`ActionValidationTests.testUnsupportedRequestsAreNotSilentlySimplified`; that test currently
covers only "for 2 hours" and misses the variants.

### C4 — Critical: time extraction and validation rewrite common phrases

This is one root cause with several reachable symptoms: `ActionPlanner.SkillArgs.time`
(`ActionPlanner.swift:375-383`) and `ArgumentExtractor.heuristic` (`Assistant.swift:396`) capture only a prefix
of the time phrase, while `InstantParser` (`EffectLedger.swift:1952-1991`) validates an
incomplete set of zone/multiple/past forms.

**Reachable cases and evidence** (`repro/ReviewRepros.swift`):

```text
Remind me to call Mom the day after tomorrow at 9am
  -> args ["title": "call Mom the day after", "when": "tomorrow at 9am"]
  -> parsed(2026-11-05 ...)          # one day early

Schedule a meeting tomorrow at 7pm Eastern / ET / Berlin
  -> args ["title": "meeting", "when": "tomorrow at 7pm"]
  -> parsed(2026-11-05 ...)          # zone word dropped and accepted
  ZONE_DIRECT=parsed(2026-11-05 ...) # even the direct phrase is accepted

Remind me to call Mom tomorrow at 9am and 11am
  -> args ["when": "tomorrow at 9am"]  # 11am dropped; one reminder
Schedule a meeting tomorrow at 9am and 11am
  -> args ["when": "tomorrow at 9am"]  # one event, not two times

Schedule a meeting tomorrow 9am-11am
  -> ActionValidation.requestIssue == nil; when "tomorrow"; no duration guard

Set an alarm for yesterday at 9am
  -> ActionValidation.issues == []; card.canConfirm == true
  # ActionContractDescription says "invalid/past instants require correction"

Remind me ... tomorrow at noon
  -> when "tomorrow"; InstantParser -> unparsed("tomorrow")  # noon lost
tonight at 9pm
  -> InstantParser -> unparsed("tonight at 9pm")             # false rejection
```

**Locations**
- `core/Sources/PocketCore/ActionPlanner.swift:375-383` — `SkillArgs.time` suffix only accepts
  `[A-Z][a-z]+ time`, `in [A-Z][a-z]+`, and a fixed abbreviation list; it has no
  `day after tomorrow`, `noon`, `midnight`, `Eastern`, `ET`, or `Berlin`.
- `core/Sources/PocketCore/Assistant.swift:396` — the heuristic `when` regex has the same
  gaps and prefers the `tomorrow` alternative inside "day after tomorrow".
- `core/Sources/PocketCore/EffectLedger.swift:1952-1957` — `zoneHints` has no full US zone
  names or `ET/PT/CT/MT`.
- `core/Sources/PocketCore/EffectLedger.swift:1975-1976` — the ambiguity regex rejects every
  phrase containing `tonight`, so "tonight at 9pm" is rejected even though it is exact.
- `core/Sources/PocketCore/EffectLedger.swift:1977-1989` — every numeric clock match is
  validated, but a phrase with multiple valid times is still accepted; `dateResolver` returns
  the first.
- `core/Sources/PocketCore/EffectLedger.swift:1092-1113` — non-local datetimes take the
  `.text` path and only check that `InstantParser` parses; no past check.
- `core/Sources/PocketCore/EffectLedger.swift:1745-1757` — non-local `bind` stores the phrase
  without a past check. `ActionContractDescription` at `ActionValidation.swift:144` says
  "invalid/past instants require correction", which is false for these handoffs.

**Fix**
Preserve the full time phrase rather than a regex prefix, and make the parser reject what it
cannot honour:
- Extract `day after tomorrow`, `noon`, `midnight`, and a named-zone token.
- Reject multiple clock times/ranges (`and`, `to`, `-`) unless a single range is supported.
- Reject or resolve unhandled zones (`Eastern`, `ET`, `Berlin`, etc.); do not silently apply
  the device zone.
- Remove `tonight` from the ambiguity regex; the existing `timeToken` requirement already
  rejects a bare "tonight".
- For non-local handoffs, either reject explicit past dates ("yesterday", "last …") or change
  the exported `.datetime` rule to say the Shortcut owns next-occurrence semantics.
- Add parser/extractor tests for every string above, including a card/action test that fails
  if a "day after tomorrow" reminder binds tomorrow.

The false rejections ("noon", "tonight at 9pm") are usability defects; the day-after, zone, and
multiple-time cases are wrong date/time effects and are why this is critical.

### W1 — Warning: a cancelled or failed read is recorded as a failed terminal result with a false "nothing sent" claim

**Location**
- `core/Sources/PocketCore/EffectLedger.swift:1610-1618` — `confirmRead` catches every error,
  including `CancellationError` and any cloud/read failure, records
  `.settled(.failed(.unavailable))`, and returns:
  `"The read did not finish. Nothing was sent or changed."`
- `core/Sources/PocketCore/Assistant.swift:327-332` — the read closure can be a cloud read via
  `execute`/`reason`; by the time it throws, `reason` may already have sent the screened prompt
  and failed over providers.
- `app/PocketGlimmer/AppModel.swift:271-273` sets the card to that summary.

**Evidence**
`repro/ReviewRepros.swift::testConfirmReadCancellationMislabels`:

```text
READ_CANCEL_RESULT=finished(... failed(unavailable),
  summary: "The read did not finish. Nothing was sent or changed.")
```

This is deterministic: a cancelled closure produces that exact summary. It is also false for a
cloud read that already reached a provider and then failed locally. The `ReadResult` and its
`cloudPromptSent` are discarded.

**Fix**
Catch cancellation separately, release the claim or rethrow, and never settle it as a user
failure. For non-cancellation failures, preserve any `cloudPromptSent`/partial result and say
what is known: "The read did not finish. A cloud request may have left the device; no message
or event was sent." Add a test with a closure that captures a prompt before throwing.

### W2 — Warning: message-option guards miss common multi-recipient and attachment forms

**Location**
- `core/Sources/PocketCore/ActionValidation.swift:115-122` — the guard only matches exact
  `attach|attachment|cc|bcc|schedule|scheduled`, and a second recipient only when joined by
  `and`/`&`. It does not match comma/semicolon/plus/slash lists, `attached`, `copy`, or
  @handles.
- `core/Sources/PocketCore/ActionPlanner.swift:349-425` (`SkillArgs.person`) and
  `core/Sources/PocketCore/Assistant.swift:398-430` (`ArgumentExtractor`) extract only one
  `person`/`contact`; `email_compose` and `imessage_send` always require exactly one contact.

**Evidence**
`repro/ReviewRepros.swift::testCommaRecipientWithBodyReachesOnePersonCard`:

```text
COMMA_BODY_ARGS=["contact": "Dana", "body": ", Sam: launch update"]
COMMA_BODY_GUARD=nil
COMMA_BODY_CARD contact=Dana — home dana@example.com
              body=, Sam: launch update
              canConfirm=true
```

`::testCommaRecipientBypassesMessageOptionsGuard` and
`::testAttachedVariantBypassesMessageOptionsGuard` also show:

```text
Email Dana, Sam about the launch          -> issue nil
Email Dana + Sam about the launch         -> issue nil
Email Dana with the report attached       -> issue nil
Text Sam, Dana that I am late             -> issue nil
```

The card is always shown for `email_compose`/`imessage_send`, so the user can inspect the body,
but the app never asks about the second recipient or attachment; the effect would send to Dana
only. For social handles, "DM @sam, @dana" is also not caught because the second-recipient
pattern starts with a word character, not `@`.

**Fix**
Add a small recipient-list check (`^` command prefix, comma/semicolon/plus/slash-separated
capitalized names or @handles) and `attach(?:ed|ment)?`, `copy (to|me)`, `cc'?d?`, `bcc'?d?`.
Add tests for the strings above. If a form cannot be reliably parsed, reject the request rather
than send to one recipient.

### W3 — Warning: local fallback does not record which provider(s) saw the payload

**Location**
- `core/Sources/PocketCore/CloudBrain.swift:105-121` — `CloudBrainChain` tries providers and
  throws only the last error; successful/failed provider names are discarded.
- `core/Sources/PocketCore/Assistant.swift:30-36` — `AssistantTurn` has `cloudPromptSent` but no
  `attemptedProviders`.
- `core/Sources/PocketCore/Assistant.swift:211-224` — after all providers fail, the reply is
  `.offlineFallback` with no provider metadata.
- `app/PocketGlimmer/AppModel.swift:240-241` — the badge is the successful provider for
  `.cloud`; for `.offlineFallback` it is `local fallback · best effort`.
- `app/PocketGlimmer/Views/ChatView.swift:94-101,116` — the privacy sheet header is that badge,
  so it never names the provider that received the failed request.

**Why it matters**
`cloudPromptSent` gives the exact text, but the user cannot tell whether Meta, the custom
endpoint, or both received it. The chain can send the same text to multiple providers before
falling back. This is a provenance gap, not a privacy leak, and the prior review already noted
that the badge names only the successful provider. The task's "local fallback provenance"
scrutiny is still not met.

**Fix**
Return a typed attempt list from `CloudBrainChain` (provider, model, outcome) in both success
and failure envelopes; add `attemptedProviders` to `AssistantTurn`/`ReadResult`; show it in the
privacy sheet and in the local-fallback badge. Add a two-provider test where both fail and
assert both names are preserved.

### W4 — Warning: the app can say "Nothing was changed" after the effect already happened

**Location**
- `core/Sources/PocketCore/EffectLedger.swift:1640-1668` — `performClaimed` calls
  `effects.perform` first, then `finish`/`ledger.record`.
- `app/PocketGlimmer/AppModel.swift:262-284` — any thrown error from `confirmEffect` becomes
  `"Couldn't complete that card: \(error). Nothing was changed."`
- `core/Sources/PocketCore/EffectLedger.swift:1611-1617` — the read path has the same shape:
  the read may complete, then `ledger.record` may throw.

**Reachable chain**
`AppModel.confirm` → `Assistant.confirmEffect` → `EffectSession.confirm`/`performClaimed` →
`effects.perform` (Messages/EventKit/URL already acted) → `ledger.record` throws a
`SQLiteError` (for example, disk full or an I/O error) → `confirmEffect` rethrows →
`AppModel` says nothing changed. There is no fault-injection test; the claim is from the code
path. The same applies to `AppModel.edit` if `updateAwaiting` commits and card construction
then throws.

**Fix**
Catch storage failures after `effects.perform` and return a terminal/ambiguous result that says
the action may have completed and tells the user to check the destination; do not surface the
generic "Nothing was changed." Add a test with a failing ledger or a file-backed DB made
read-only after staging.

### W5 — Warning: `EffectLedger.swift` is a 1,993-line mixed-concern file and reaches back into `Assistant`

**Location**
- `core/Sources/PocketCore/EffectLedger.swift` — 1,993 lines: capability catalog, SQL schema
  and ledger, claim/receipt classification, draft cards, session orchestration, display text,
  `AutoreplyMemory`, and `InstantParser`.
- `core/Sources/PocketCore/EffectLedger.swift:1029` — `card(for:)` calls
  `Assistant.stringArguments`, a static helper on the high-level Assistant class; the ledger is
  the lower-level persistence/session layer.
- `core/Sources/PocketCore/Skills.swift:283-303` — `SharedInbox` is now dead in production;
  only tests call it.
- `app/PocketGlimmer/Intents/SkillIntents.swift:25-29` — `install(on:memory:)` discards its
  `memory` argument with `_ = memory`.

**Why it matters**
The file crosses the 1k-line smell by a wide margin, and the Assistant dependency inverts the
intended boundary. The code has clear sections, but the coupling makes the ledger harder to
test and change independently. `SharedInbox` is an obsolete compatibility path: the new
request-bound `_sharedText` design is the only production path, and the docs still describe
the old slot.

**Fix**
Split into `EffectContracts.swift` (catalog/types), `EffectLedger.swift` (SQL/records),
`EffectSession.swift` (bind/confirm/perform), `EffectDisposition.swift` (classification and
summaries), and `InstantParser.swift`. Move `stringArguments` to `BoundAction` (or the existing
`PersistedText` helper). Delete `SharedInbox` and its test cleanup, or wire it consistently if
the old path is still a supported product path; remove the unused `memory` parameter.

### W6 — Warning: operator docs contradict the bundled-model and shared-input code

**Location**
- `app/README.md:75-77` says `AppModel.findModel()` checks Documents first and prefers `reflex`.
  `app/PocketGlimmer/AppModel.swift:88-98` checks `[bundled, inDocs]`; bundled wins.
- `ios/MAC_DAY_RUNBOOK.md:198-200` repeats "checks Documents first" and describes an unbundled
  arbitrary `.gguf`. `AppModel.swift:100-114` now requires the exact 807,694,080-byte shipping
  file and SHA-256, so a base model or a different quant fails at boot.
- `docs/research/EFFECT_SLICE1_IMPLEMENTATION_NOTE.md:84-86,95-99,122` still says reply-only
  reads keep a `SharedInbox` copy, that `AppModel.send` returns before `SharedInbox.put`, and
  that 172 tests passed. The code stores `_sharedText` in the attempt (`EffectLedger.swift:1567-1584`),
  `AppModel.send` passes it explicitly (`:231`), and the current suite is 183 tests.
- `docs/research/REQUEST_INPUT_GROUNDING.md` still describes the old `SharedInbox` ownership
  and `AppModel.send` put; it is historical, but it is linked from the current handoff.

**Why it matters**
An operator following the README/runbook will put a model in Documents expecting it to win,
or copy an arbitrary `.gguf` and get "Model failed to load." A reviewer reading the effect note
will believe the shared-input ownership is still the old global slot.

**Fix**
Update both operator docs to say bundled first, Documents only when no bundled model exists,
and the Documents file must match the shipping size/hash. Update or archive the implementation
note; make it say `_sharedText` is the durable request-bound copy, the suite is 183/1 skipped,
and busy admission remains open. Remove the dead `SharedInbox` references.

### Nits (real but lower impact)

- `core/Sources/PocketCore/ActionValidation.swift:43` — the handle pattern allows X handles of
  1-3 characters (X requires 4-15) and trailing/consecutive dots for Instagram-style handles.
  Reject invalid lengths/edge dots; add tests.
- `core/Sources/PocketCore/EffectLedger.swift:922-934` — `duplicateHint` includes cancelled
  and failed prior attempts; the note then says an item "already exists" when the prior never
  committed. Filter to settled/ambiguous commits or adjust the wording.
- `core/Sources/PocketCore/EffectLedger.swift:1246-1255,903-917` — an unknown phase decodes to
  `ambiguous` and `recover` silently skips it; an unknown `UserPause` becomes nil (potentially
  confirmable). Throw for unknown phases/pauses or surface them as unresolved.
- `app/PocketGlimmer/Views/ChatView.swift:240-259` with
  `core/Sources/PocketCore/EffectLedger.swift:1015-1025` — an `analyze_document` card shows a
  "Document" text field, but the field is not used by `execute`; the read uses the picker or
  `_sharedText`. Hide it or make it a picker.
- `core/Sources/PocketCore/EffectLedger.swift:1097` — the local-write past check allows up to
  60 seconds in the past while the docs say an exact future time; either document the grace or
  tighten it.
- `app/PocketGlimmer/Actions/PocketEffects.swift:271-287` — `UIPasteboard.general` is used
  after an `await` in a nonisolated class; UI pasteboard access should be on the main actor.
  Phone-only; not run here.
- `app/PocketGlimmer/Actions/SystemActions.swift:147-173` — `finish` does not verify that the
  delegate callback belongs to the current `pending` controller/kind; a late mail callback
  while a message sheet is pending can dismiss the message sheet and never resume its
  continuation. Make `finish` take the controller and check identity/kind.
- `app/PocketGlimmer/Views/SettingsView.swift:25-38,55-58` — malformed BYOK/Meta settings are
  silently skipped by `CloudSettings.chain` (`AppModel.swift:361-376`); the user gets local
  fallback with no "cloud is misconfigured" message. Add inline validation on Save.
- `core/Tests/PocketCoreTests/ActionValidationTests.swift:105-114` — the "not silently
  simplified" test covers only five phrases and misses the C3/C4/W2 strings; its name
  overstates the coverage.

## Verification actually run

All commands ran in this checkout or in the scratch copy; nothing was written to tracked files.
Docker image: `swift:6.1-noble`. Scratch core: `/tmp/pocket-glimmer-takeover/contracts-review-v1/core`.

| Check | Result | Evidence |
|---|---|---|
| Swift core suite (`swift test`, Docker, scratch copy) | **PASS**: 183 executed, 1 skipped, 0 failures | `swift-test.log` |
| Python suites (`training.tests.test_pipeline`, `eval.round3.test_graders`, `training.round3.duration_eval_test`) | **PASS**: 22 executed, 0 failures | `python-22.log` |
| Mac preparation fixtures (`bash ios/test_mac_prep.sh`) | **PASS**: 84 passed, 0 failed; Linux/mock `uname/file/lipo/otool/nm/xcodebuild`, not Xcode | `mac-fixtures.log` |
| Prior false passes (zero-byte executable, no bundled model at default, `--allow-no-model`, symlinked embedded/source framework) | **FIXED at shell level**: exit 1/2 and messages as expected | `mac-fixtures.log` lines for check-app/build-unsigned |
| Shell syntax / ShellCheck | **PASS**: `bash -n` and `shellcheck -x` on `mac_prep.sh`, `test_mac_prep.sh`, `verify_submission.sh` | `shellcheck.log` (empty), command exit 0 |
| Real shipping resources (`mac_prep.sh verify-resources --root .`) | **PASS with caveat**: model 807,694,080 bytes and SHA-256 match; calibration SHA-256 and 31 prior sets match; 36 skills; entitlements empty. `WARN no bundled model`: source resources are verified, no built app. | `resources.log` |
| Contract manifest and bundled skills regeneration | **PASS**: `pg-cli action-contracts` equals `docs/ACTION_CONTRACTS.json` (38 contracts, 38 ids); `pg-cli dump-skills` equals `builtin.json` (36 skills) | `regenerate.log` |
| App Swift syntax | **PASS**: 18 app files parse with `swiftc -frontend -parse`; syntax only, no UIKit/SwiftUI/EventKit typecheck | `app-parse.log` |
| `scripts/verify_submission.sh` with `SKIP_SWIFT=1` | **INCOMPLETE, exit 2**: 7 Python tests pass, secret scans pass, repository PRIVATE, Swift skipped. Not an all-clear. | `submission.log` |
| `git diff --check` | **PASS**: no whitespace errors | command output |
| Xcode typecheck/build, Mach-O arm64 proof | **COULD NOT RUN**: no Mac/Xcode in this session; mock `file` is not proof | — |
| iPhone install/launch/permissions/Documents model/Shortcuts/latency/memory/thermal | **COULD NOT RUN**: no device; not claimed | — |
| Live Meta Model API / paid inference | **NOT RUN**; the earlier smoke at source `4bf72c9` used scripted local decisions, Linux, no iPhone | `docs/verification/cloud_smoke_2026-11-04.json` |
| C1 payload repro | **FAIL (bug reproduced)** | `repro.log`: `READ_FALLBACK provider=nil cloudPromptSent=true`; `AppModel.swift:237` drops it |
| C2 share repro | **FAIL (bug reproduced)** | `repro.log`: `SHARE_CLOUD_MARKER_IN_BODY=false`; answer-local marker absent |
| C3 calendar repro | **FAIL (bug reproduced)** | `repro.log`: `CAL_TWO_HOUR_REQUEST_ISSUE=nil`, committed one-hour event, no card |
| C4 time repro | **FAIL (bug reproduced)** | `repro.log`: day-after -> tomorrow; Eastern/Berlin dropped; 9am+11am -> 9am; past alarm confirmable; noon/tonight rejected |
| W1 confirmRead repro | **FAIL (bug reproduced)** | `repro.log`: cancellation recorded as `finished(... failed(unavailable), "Nothing was sent or changed")` |
| W2 message-option repro | **FAIL (bug reproduced)** | `repro.log`: comma/plus/attached forms issue nil; Dana-only card |
| Prior partner-mask regression | **PASS** | `CloudPrivacyTests.testPartnerProfileValueIsMaskedInTheWholeCloudPayload` in `swift-test.log`; scripted classifier |
| Prior cancellation-chain regression | **PASS** | `CloudBrainTests.testCancellationNeverTriesAnotherProvider` |
| Prior malformed-settings regression | **PASS** for empty/malformed values reaching no transport | `CloudBrainTests.testMalformedSettingsCannotReachTransport`; Settings UI error is still missing |

## Repairs verified and gaps that remain

- Partner name in memory: the partner value is now offered to the scrubber and the full
  mock-cloud payload contains `[PERSON_...]`, not `Linda`. This fixes the reported path; names
  hidden inside arbitrary todo/autoreply text and classifier false negatives remain documented
  limits, not solved here.
- Cloud provider cancellation: the chain rethrows cancellation and does not call the next
  provider. `ComposeSheets` cancellation is a separate UI path and can still label a
  task-cancelled sheet as a user cancel.
- Malformed cloud settings: invalid values no longer create a brain, but Settings gives no
  visible error and any nonempty Meta model id is accepted.
- Local fallback: text-chat `.offlineFallback` and confirm-read fallback carry
  `cloudPromptSent`; the immediate `AppModel.send` `.local` case does not. No attempted-provider
  provenance exists.
- Mac packaging: the three prior false passes are repaired at the fixture level. A symlinked
  app root or Info.plist is still not explicitly rejected, and there is no Xcode/Mach-O proof.
- Model precedence: the app prefers bundled and verifies the exact hash; the README/runbook
  still say Documents first and still describe an arbitrary unbundled `.gguf`.
- Busy input: still refused before staging; the ledger and ACTION_VALIDATION.md say so. No false
  completed claim. `EFFECT_SLICE1_IMPLEMENTATION_NOTE` is stale on this point.

## Remaining platform limitations

- Xcode build/typecheck, signed install, iPhone launch, real EventKit read-back including
  synced calendars/write-only access, Contacts unified identifiers/limited access, MessageUI
  and Mail sheet contention/cancellation, Shortcuts alarm/time phrase behavior, Files
  Documents copy, and latency/memory/thermal behavior are all unverified.
- The Mac fixtures use fake `uname/file/lipo/otool/nm/xcodebuild`; they prove shell control
  flow only.
- The fake `PhoneEffects` proves typed contracts and ledger transitions, not Messages/Mail
  delivery, EventKit persistence, or URL/Shortcut effects.
- The cloud smoke at `4bf72c9` proves one HTTP 200 transport with scripted local decisions and
  a scripted sensitive/ok outcome; it does not prove the frozen classifier, real routing, or
  iPhone privacy behavior.
- The latest parent thread (after this checkpoint) says the user now has a MacBook Air and
  iPhone available and is setting up T3 linked environments; that is not a build, install, or
  device test in this checkout. No phone readiness is established.
