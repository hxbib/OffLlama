# Floor LoRA retrained with nudge_v2 labels (nv2) vs shipping 1-epoch floor (ep1)

Same config (bf16 / micro 2 / grad-ckpt, 1 epoch), train set = old labels + 300 new nudge_v2 scenarios labeled by Muse Glimmer 30B IQ2_M (training/local_teacher/out/nv2/). Same v2+cc eval pipeline.
Selection rule: calibration split only (n=180); test120 is a held-out report.

| split | metric | ep1 (shipping) | nv2 |
|---|---|---|---|
| cal180 | acc | 0.78 | 0.79 |
| cal180 | handled@0.8 | 0.49 | 0.47 |
| cal180 | acc on handled | 0.96 | 0.92 |
| cal180 | conformal tightest (alpha 0.05, delta 0.1) | tau 0.90, 36% handled, 0 errors, bound 10.2% | tau 0.87, 33% handled, 0 errors, bound 10.9% |
| cal180 | nudgeNow | 7/15 | 7/15 |
| test120 | acc | 0.82 | 0.79 |
| test120 | handled@0.8 | 0.51 | 0.42 |
| test120 | acc on handled | 0.92 | 0.90 |
| test120 | ECE (10 bins) | 0.064 | 0.106 |
| test120 | nudgeNow | 3/10 | 3/10 |

Per type on test120, nv2 vs ep1: toolChoice 5/10 vs 8/10, rememberOrNot 6/10 vs 7/10, eventPick 8/10 vs 9/10, timing 9/10 vs 8/10, memoryConflict 10/10 vs 9/10; nudgeNow unchanged at 3/10.
Per type on cal180, nv2 vs ep1: answerability 14 vs 11, timing 13 vs 10, toolChoice 11 vs 12, confirmBeforeAct 12 vs 13, eventPick 11 vs 12, sensitivity 14 vs 15; nudgeNow 7/15 both.

Decision: keep ep1 as the shipping adapter. On the calibration split nv2 gains one item of overall accuracy but is wrong more often on what it handles (0.92 vs 0.96) and its conformal bound is looser (10.9% vs 10.2%). The targeted fix did not move nudgeNow on either split, so the 300 new labels did not teach the intended behavior; the next step for nudgeNow is checking the nv2 teacher labels themselves (label distribution vs the intended 143 skip / 91 nudge / 66 later), not another retrain.
Files: after_floor_nv2.{test,calibration_split}.json, after_floor_nv2.reliability.txt, after_floor_nv2.conformal.txt, conformal_after_floor_nv2.calib_split.json.

Why it didn't move (checked against nv2_labels.jsonl and build_stats.json): the Glimmer IQ2_M teacher agreed with the scenario's intended outcome on only 20 of 66 "later" scenarios (24 went to skip, 22 to nudge), and 30 of 143 intended "skip" went to nudge. Overall teacher labels: 141 nudge / 139 skip / 20 later. The confidence filter then dropped 209 low-confidence nudgeNow rows across old+new labels, so the train set grew only 892 to 1,030. The bottleneck is the teacher's handling of "later", so a stronger teacher (the Spark labeling run in flight) is the right next test, not more epochs or more IQ2_M labels.
