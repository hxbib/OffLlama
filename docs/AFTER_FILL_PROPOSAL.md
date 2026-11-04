# AFTER fill (shipping ep1): APPLIED, Option A (τ=0.90)

> November 4 correction: earlier “certified” claims below are historical. Model selection reused cal180; the nominal bound is not a post-selection guarantee. See [evaluation limits](EVALUATION_CLAIMS.md). Saved predictions are unchanged.

**Status (2026-11-04 ~6:00 AM ET):** Option A applied with `TAU=0.90 scripts/apply_after_fill.sh` by the orchestrating agent under Habib's "go, complete this" directive. The values below are now in README.md, docs/SUBMISSION.md and docs/DEMO_SCRIPT.md. The script also filled the teacher-label count (892). This file is kept as the record of the decision.

Drafted 2026-11-02 07:20 ET.

| Placeholder | Value | Source |
|---|---|---|
| `AFTER_ACC` | 82% (98/120) | LEDGER 6.1, eval/results/AFTER_FLOOR.md |
| `AFTER_COVERAGE` | 51% at τ=0.8 (61/120) | LEDGER 6.1 |
| `AFTER_ACC_HANDLED` | 92% (56/61) | LEDGER 6.1 |
| `AFTER_ECE` | 0.064 | LEDGER 6.1 |
| `AFTER_TAU` | **0.90 (Option A, applied)** | after_floor.conformal.txt |
| `AFTER_BOUND` | ≤10.2% (cal N=180, τ=0.90, 64/180 handled, 0 errors); 5% not certified | after_floor.conformal.txt |
| `AFTER_RELIABILITY_CHART` | `docs/img/reliability_after_floor_test120_v2cc.png` | docs/img |
| `AFTER_ROUND_SHARES` | 15% (untrained) to 51% (round 1), one shipped round; ep2/nv2/Spark rounds rejected on cal180 | LEDGER 6.1, 15 |

## The one decision: which threshold ships
- Option A, τ=0.90: the certified one. Error among on-device decisions ≤10.2% (cal180). On-device share ~36% on cal180. Honest "certified" story; then the 51% figure must be labeled "at τ=0.8" wherever it appears.
- Option B, τ=0.80: on-device share 51% on test120 with 92% accuracy on handled, but no conformal certificate at that threshold.
Recommendation: A for the app and the certified claim; keep 51% @0.8 only in the before/after table (same τ as the 15% baseline, so it is apples to apples). **Chosen: A.** The app bundles `defaultTau` 0.90 (`app/PocketGlimmer/Resources/Models/calibration.json`).

Still open after this: the iPhone measurements only; they are listed in docs/FINAL_HOURS.md §A. The teacher-label count (892) is filled.
