# Per type at the certified threshold τ=0.90 (shipping ep1, frozen test120, report only)

Re-analysis 2026-11-04 ~06:20 ET of `eval/results/after_floor.test.json` (no model re-run). Companion to
`PER_TYPE_SHIPPING.md`, which reports τ=0.80. τ=0.90 is the threshold the app ships with under AFTER_FILL
Option A (certified ≤10.2% error bound on cal180; LEDGER 6.2). n=10 per type, so one item = 10 points.

| Type | Acc | Handled @0.90 | Correct on handled @0.90 | Handled @0.80 | Correct on handled @0.80 |
|---|---|---|---|---|---|
| answerability | 9/10 | 3/10 | 3/3 | 5/10 | 5/5 |
| confirmBeforeAct | 10/10 | 2/10 | 2/2 | 6/10 | 6/6 |
| contactPick | 9/10 | 8/10 | 7/8 | 9/10 | 8/9 |
| eventPick | 9/10 | 8/10 | 8/8 | 9/10 | 8/9 |
| memoryConflict | 9/10 | 0/10 | n/a | 1/10 | 1/1 |
| notificationTriage | 8/10 | 2/10 | 2/2 | 4/10 | 3/4 |
| nudgeNow | 3/10 | 0/10 | n/a | 0/10 | n/a |
| rememberOrNot | 7/10 | 1/10 | 1/1 | 1/10 | 1/1 |
| route | 8/10 | 6/10 | 6/6 | 7/10 | 7/7 |
| sensitivity | 10/10 | 5/10 | 5/5 | 7/10 | 7/7 |
| timing | 8/10 | 3/10 | 2/3 | 5/10 | 4/5 |
| toolChoice | 8/10 | 6/10 | 5/6 | 7/10 | 6/7 |
| **all** | **98/120** | **44/120 (37%)** | **41/44 (93%)** | **61/120 (51%)** | **56/61 (92%)** |

Demo implication (DEMO_SCRIPT.md): with τ=0.90 in the app, the types that most often stay on device are
contactPick, eventPick, route, toolChoice and sensitivity. confirmBeforeAct is 10/10 accurate but clears τ=0.90 only
20% of the time, so a "confirm" card will usually show the orange below-τ bar and the hard rule "messages always
confirm" (Assistant.swift) is what makes the beat work, not the confidence. Rehearse each offline shot on the real
phone and keep only those that clear τ (pre-shoot checklist). nudgeNow and memoryConflict never clear τ=0.90 on
test120: show them only as the hand-off to Muse Spark 1.3.
