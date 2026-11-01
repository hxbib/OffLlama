# Floor LoRA, 2 epochs vs 1 epoch (same bf16 / micro 2 / grad-ckpt config, 892 labels)

Selection rule: calibration split only (n=180); test120 is a held-out report.

| split | metric | ep1 (floor) | ep2 |
|---|---|---|---|
| cal180 | acc | 0.78 | 0.78 |
| cal180 | handled@0.8 | 0.49 | 0.60 |
| cal180 | acc on handled | 0.96 | 0.90 |
| cal180 | conformal tightest (delta 0.1) | tau 0.90, 36% handled, 0 errors, bound 10.2% | tau 0.96, 25% handled, 0 errors, bound 14.2% |
| test120 | acc | 0.82 | 0.81 |
| test120 | handled@0.8 | 0.51 | 0.61 |
| test120 | acc on handled | 0.92 | 0.92 |
| test120 | ECE (10 bins) | 0.064 | 0.076 |

Per type on test120, ep2 vs ep1: rememberOrNot 5/10 vs 7/10, memoryConflict 10/10 vs 9/10, nudgeNow 3/10 both; others equal.

Decision: keep ep1 (floor) as the shipping adapter. On the calibration split ep2 handles more but is wrong more often on what it handles (0.90 vs 0.96) and its conformal bound is looser; a second epoch makes it more confident, not more correct.
Files: after_floor_ep2.{test,calibration_split}.json, after_floor_ep2.reliability.txt, after_floor_ep2.conformal.txt.
