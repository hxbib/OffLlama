# Action time and recipient repairs

This change implements the accepted defects from the independent review's C3, C4, and
W2 findings, plus the datetime text-size check. The parent repaired ordinary C1/C2 fallback paths at `5912cd7`. W1/W4 still have
projection, recovery and edit-path gaps recorded in `SHARED_READ_FIX_REVIEW_2026-11-04.md`;
those paths are untouched here.

No iPhone, Xcode, EventKit, NSDataDetector, Messages, Mail, or Shortcuts run was
available. All evidence below is Linux core with fake effects and fake date resolvers.
It proves the typed contract and ledger transitions, not phone behavior.

## Calendar contract

`calendar_create` now always shows a review card. The compiled floor changed from
`modelMayAct` to `always`. The card and the committed summary both state the fixed
limitation: one hour, no invitations, no location. No duration, attendee, or location
field was invented.

`ActionValidation.requestIssue` now refuses the reproduced forms before a card is
built:

- durations: `for 2 hrs`, `for 90 min`, `for 1.5 hours`, `2-hour`, `90-minute`,
  `for two hours`
- ranges: `3pm-5pm`, `9am-11am`, `from 3pm to 5pm`, `between 9am and 11am`
- attendees: `with Sam`, `with Dana`, `invite`, `attendee`
- locations: `at the office`, `in the conference room`, `at 123 Main Street`
- explicit month/day dates such as `November 5 at 3pm`

A duration mention after the time that is subject matter, such as `to discuss the
2-hour plan`, is not treated as an event duration. The title and supported time are
still extracted for the correction message; no fake field is added.

The catalog versions for `reminder_create`, `calendar_create`, and `alarm_create`
moved to 3. A pending version-2 card is now stale and cannot execute under the new
time/confirmation policy. `testStaleCalendarSnapshotCannotExecuteUnderTheNewPolicy`
covers the calendar case.

## Time extraction and validation

`TimePhrase` in `ActionValidation.swift` captures the complete time expression. Both
`SkillArgs.time` and `ArgumentExtractor.heuristic` use it. The follow-on
`InstantParser.rejection` is the single structural gate used by argument validation,
readiness, planning, and `parse`.

The repaired cases:

- `the day after tomorrow at 9am` keeps that phrase; it is no longer reduced to
  `tomorrow at 9am`
- `tomorrow at noon` keeps `noon`; `noon` and `midnight` are accepted as exact times
- `tonight at 9pm` is accepted; bare `tonight` still needs an exact clock time
- `tomorrow at 9am and 11am` keeps both times and is refused as multiple instants
- `tomorrow 9am-11am` keeps the range and is refused
- `Eastern`, `ET`, `Berlin`, `Berlin time`, `in Berlin`, and `Eastern Standard Time`
  are preserved and refused as named zones. The app does not claim to understand
  arbitrary zones; it refuses a curated set and a capitalized qualifier after a clock
- explicit past phrases such as `yesterday at 9am`, `yesterday morning at 9am`,
  `last Friday at 3pm`, `last night at 9pm`, and `3 days ago at 9am` are refused
- approximate qualifiers such as `around`, `about`, `approximately`, `roughly`,
  `maybe`, and `perhaps` are refused
- a relative handoff phrase that the resolver returns in the past, such as
  `tonight at 9pm` after 9pm, is not stored as a confirmable Shortcut field
- explicit month/day dates are refused rather than reduced to their clock time

All datetime values still pass the existing 2,000-character limit. The tests cover a
2,500-character alarm and reminder time, both stage as unconfirmable, and neither
effect runs.

The datetime contract rule now says what is true: local reminder/calendar writes bind
a future Date once; Shortcut handoffs receive the reviewed phrase and the Shortcut
decides the next occurrence. Explicit past phrases are still refused before handoff.

## Message recipients and attachments

`messageOptionsIssue` inspects only the instruction prefix. It stops at a quote,
colon, or a body marker such as `saying`, `that says`, `to say`, `with the message`,
or `that`. The repaired forms include comma, semicolon, plus, slash, ampersand, and
`and` lists; `@handle` lists; `attached`, `attachment`; `cc`, `bcc`, `copy`; and
`send this later` style scheduling.

`ActionValidation.issues` also refuses a message body that starts with a recipient
separator, so an already-extracted `", Sam: launch update"` body cannot reach a
confirmable card as a message to Dana alone.

Body text is not treated as an instruction. `Text Sam saying I'll attach the report`,
`Text Sam: I'll cc Dana`, and quoted bodies containing `attach` remain valid single
recipient messages.

## Tests

Focused new suite:

```text
swift test --filter ActionTimeConstraintTests
Executed 14 tests, with 0 failures
```

Full core suite in `swift:6.1-noble` with the worktree `core` mounted:

```text
swift test
Executed 203 tests, with 1 test skipped and 0 failures
```

The baseline was 189 executed, 1 skipped, 0 failures. The new file adds 14 positive
tests. Two existing tests changed semantics intentionally:

- `EffectRecoveryTests.testModelActClaimsBeforeEventSave` now expects a staged
  calendar card, confirms it, then checks that the claim commits before the EventKit
  save. Calendar review is always required now.
- `SkillsTests.testArgExtraction` now expects `wake me at 6` to extract `6`, not
  `6:00`. The phrase is preserved; the ambiguous clock is refused by validation
  rather than rewritten.

`pg-cli action-contracts` was regenerated. `docs/ACTION_CONTRACTS.json` matches the
compiled output, with the three datetime contracts at version 3 and the updated
calendar and datetime rules.

## Limits

- `day after tomorrow`, `noon`, and `tonight` are accepted here, but whether iOS
  `NSDataDetector` resolves the exact phrase is unverified. If it cannot, the card
  asks for correction instead of writing a guessed instant.
- The named-zone refusal is a conservative lexical guard. It does not understand
  arbitrary zones or cities. An unknown lowercase city outside the curated list can
  still be dropped by extraction.
- A time-like title before the real time can still win as the first extracted time.
  This is the existing first-match extraction behavior, not a new guarantee.
- Calendar guards are lexical. A reason or subject clause can be conservatively
  refused when it contains a duration, `with`, or a location phrase.
- Parent integration updated `docs/ACTION_VALIDATION.md` to describe the three version-3 contracts.
- No iOS parser, EventKit, Messages, Mail, or Shortcuts proof exists.
