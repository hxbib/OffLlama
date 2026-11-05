# Review: f7db1f0..b5fdfb0 (7 files)

**Verdict: no blocking regressions found. Ship-eligible for the Mac integration check.** Verified at `b5fdfb0`; nothing in the tree was modified (probe file added then deleted).

## What I verified

**Source-of-truth / compiled contract**
- `Assistant.swift:203-212` selects the skill with `BuiltinSkills.all.first(where: $0.id == "appletv_play")` — the compiled catalog, never a merged JSON registry, and passes `registry: SkillRegistry()` so no on-disk or user registry can shadow it.
- `ActionPlanner.swift:145` (`preselected` → `forced`) skips `skillPick` entirely, so no model guess can choose a different skill; args still come from `CapabilityCatalog.current` + `BuiltinSkills` (`ActionPlanner.swift:207-211`), so executor and review sentence are the compiled `externalHandoff` / `https://tv.apple.com/search?term={show}` contract (`EffectLedger.swift:558-560`).
- Path goes through `EffectSession.evaluate` via the normal `.compiled`/`.userHandoff` branch (`ActionPlanner.swift:252-259`). No auto-execution: the only way to perform is `confirmEffect`, and the test asserts `performCount == 0` before confirm.

**Action hijack boundaries (probed in-container)**
- No match: `Text Sam: Ted Lasso on Apple TV`, `What is on Apple TV?`, `Play Ted Lasso on Apple TV and then text Sam`, `Open Ted Lasso on Apple TV, please`. Questions, message bodies and trailing clauses fall through to their existing routes.
- Match: `Can you play Ted Lasso on Apple TV?` is treated as a command — correct for iOS usage; the anchored verb makes an interrogative reading unlikely, and the outcome is a non-executing review card either way.
- Extraction is stable across phrasings: `Ted Lasso` for all three variants in `testAppleTVLatestEpisodeStillReviewsSearchForTheShow`; the "latest episode of" prefix is dropped and the note "does not start playback" is preserved (`TakeoverRegressionTests.swift:243-246` unaffected).

**Message status wording**
- `DecisionPresentation.swift:84-85` and `EffectLedger.swift:1411-1413` drop "delivery not confirmed" while keeping the typed distinctions (`submitted`/`queued` vs `failed`/`cancelled` at `:1440-1441`, `:77` `Outcome unverified`). The absolute honesty assertion survives in `ActionStatusLabel.label(for: .claimed/.ambiguous)` and `.handedOff`.
- The rewritten tests actually strengthen evidence: `EffectRecoveryTests.swift:233-234` and `:258-259` now assert no `deliver` substring appears, so a future regression that reintroduces the warning fails loudly. The removed `contains("not confirmed")` assertion was a wording pin, not a safety property — no weakening.
- UI worker is disjoint: I found no app-side consumer of the changed strings (`grep` over `app/` returned nothing), so the app views are not silently out of sync.

**Tests**
- Root Docker `swift:6.1-noble`: `398 tests, 1 skipped, 0 failures` — matches the claim exactly.
- New coverage is real: 4 routes × 2 registry states, generate prompts asserted empty, double-confirm idempotent (`effects.performCount == 1`).

## Non-blocking observations

1. **N2 — `ActionPlanner.swift:64-69`**: the anchoring permits `Can you play … on Apple TV?` to become a card. Acceptable because the card never executes (confirm required), but if you want strict symmetry with `explicitToolCommand`'s `hasSuffix("?")` guard, add it. Not a correctness regression.
2. **N3 — `ActionPlanner.swift:66` / `SkillArgs` "show" branch**: `Open the Apple TV on Apple TV` yields `show == "Apple TV"`. That's a benign self-referential search, not a hijack; no fix needed.
3. **N4 — wording**: "Message submitted" is accurate for the Messages sheet but relies on "submitted ≠ delivered" being understood. The conversationally prior "delivery not confirmed" was removed by design; if a reviewer wants the caveat back it belongs in the review-sentence copy, not the status label.

**Reproduction for the fixed bug**: `assistant.handle("Open Ted Lasso on Apple TV")` with an `answer_local` route previously generated chat (`Done! I set that for you.`); now returns `.needsConfirmation` with `capabilityID == "appletv_play"` and `show == "Ted Lasso"`.

No PR created, no delegates, no installs, no production edits.

## Parent adjudication

No code change requested for the nonblocking observations. Polite commands intentionally reach review. The reviewer’s statement that no app-side consumer exists is too broad: `AppModel.swift` uses `ActionStatusLabel.label(for:)` when projecting results. It does not compare the old strings, so the new labels flow through normally. Typed phases and non-committed message outcomes remain intact.

