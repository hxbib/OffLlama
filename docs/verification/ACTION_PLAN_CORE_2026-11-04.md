# Journal-owned action plans, first core unit

The core can stage two or three actions under one request ID. Every step requires
its own review. Calendar and reminder steps can provide a verified saved title,
time or summary to a later message or mail step. Other capabilities are visible
as unsupported plan steps. Independent steps do not wait for unrelated outcomes.

`EffectLedger.claim` remains the only execution gate. Dependency checks and the
revision compare-and-swap run in the same SQLite transaction for both existing
claim branches. A dependent body must be materialized from the predecessor's
typed receipt, saved, and confirmed with its current displayed revision. A mail
draft, accepted message, URL opening, failed, cancelled or uncertain result does
not supply that receipt. Launch recovery performs no action. Refreshing a plan
can fill a draft but never claims or performs it.

Plan metadata is separate from legacy rows. Migration adds two nullable columns
and a partial unique index. Legacy duplicate request/step pairs remain valid.
Four active plans, three steps per plan and 16 KiB per staged plan are limits,
not performance measurements. Refusal keeps existing work. Repeated staging for
one request ID returns the existing attempts. There is no timed deletion in this
unit and no claim of exactly-once delivery across SQLite and native apps.

Verification used Docker `swift:6.1-noble`. All 14 new plan tests passed. The full
suite executed 348 tests, skipped one opt-in live test and had zero failures.
Output is `action-plan-core.txt`. Tests include concurrent staging/confirmation,
file-backed restart, late receipt-derived bodies, non-success dependencies,
stale or absent displayed revisions, independent steps, cancelled predecessors,
read-only recovery, receipt-write failure and second-insert rollback, invalid
metadata, bounds, and legacy migration. Source inspection still finds one
`effects.perform` call, in `EffectSession.performClaimed`.

This unit is not wired to Assistant compound parsing or app plan cards. It does
not implement a cloud planner or demonstrate model planning. Tests use fake
effects and do not establish EventKit read-back, native compose presentation,
message delivery or iPhone performance. Independent review and an Apple build
remain required. The selected design and rejected alternatives are recorded in
`docs/research/MULTISTEP_DESIGN_SYNTHESIS_2026-11-04.md`.
