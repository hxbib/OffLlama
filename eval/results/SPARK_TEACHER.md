# Floor LoRA distilled from Muse Spark Open labels (floor_spark) vs shipping ep1

**Verdict: rejected. ep1 stays shipping.** On cal180 (the only selection split), floor_spark is right less often on the items it handles (0.90 vs 0.96) and its conformal bound is looser (13.7% vs 10.2%). It does fix much of nudgeNow (10/15 vs 7/15 on cal).

## Setup
- Teacher: Muse Spark Open 816B-A42B (NVFP4, Baseten `meta-models/muse-spark-open-1026`), k=8 samples, t=1.0. Baseten ignores logprobs, so the soft labels are vote shares.
- Train set: 892 original scenarios + 280 extra weak-type scenarios, relabeled by Spark → `training/spark_teacher/out/distill_train_spark.jsonl`, 1,157 rows after filtering (build_stats_spark.json).
  The per-type weights and filters come from the **Glimmer** QC report (`QC_REPORT=../local_teacher/out/qc_report.json`), the same one shipping used. I did not use Spark's own QC report, because its 50 QC items are calibration-split rows, so using it would leak Spark's cal-split output into training. No train row's id or context overlaps cal180 or test120 (checked).
- Recipe: floor, unchanged (lora_cpu.py, bf16, bsz 8 = micro 2 × grad-accum 4, lr 2e-4, r16, 1 epoch, grad-ckpt). 145 steps, 654 s on the box CPU. Modal was not used: `MODAL_TOKEN_SECRET` was not set. The first run (identical script, sha 79e9b01d…) finished on the PC 3080 Ti in 44 s, but the PC's C: drive filled up while it was exporting the merged model. The PC shell then stopped working and the adapter could not be copied off it, so I retrained on the box. **The numbers below come from the box run.**
- Merge → Q4_K_M → llama-server, eval with the v2+cc prompt (run_prompt_variants.py), reliability.py (10 bins), and conformal LTT (alpha 0.05, delta 0.1). This is the same pipeline as ep1 (run_after_eval_spark.sh).
- **Grading key:** run_prompt_variants.py reads `eval/gold/gold_calibration.jsonl` and `eval/gold/gold_test.jsonl` and grades `ok = pred == g["gold"]`, using the human gold field from those files, which is the same key as ep1. Spark's cal-split labels (`cal_labels_spark.jsonl`) were used only for the Spark-vs-gold agreement analysis below. They were never used as a grading key or for training.

## Results (ep1 numbers recomputed from after_floor.*.json; they match LEDGER)
| split | metric | ep1 (shipping) | floor_spark |
|---|---|---|---|
| cal180 | acc | 0.78 | 0.80 |
| cal180 | handled@0.8 | 0.49 | 0.70 |
| cal180 | acc on handled | **0.96** | 0.90 |
| cal180 | conformal tightest | tau 0.90, 36% handled, 0 errors, bound **10.2%** | tau 0.98, 35% handled, 1 error, bound 13.7% |
| cal180 | nudgeNow | 7/15 | **10/15** |
| test120 | acc | 0.82 | 0.81 |
| test120 | handled@0.8 | 0.51 | 0.73 |
| test120 | acc on handled | 0.92 | 0.89 |
| test120 | ECE (10 bins) | 0.064 | 0.089 |
| test120 | nudgeNow | 3/10 | 4/10 |

Per-type correct counts, ep1→spark. cal180 (n=15 each): answerability 11→15, confirmBeforeAct 13→11, contactPick 10→10, eventPick 12→12, memoryConflict 15→15, notificationTriage 11→9, nudgeNow 7→10, rememberOrNot 13→13, route 12→12, sensitivity 15→14, timing 10→11, toolChoice 12→12.
test120 (n=10 each, report only): answerability 9→9, confirmBeforeAct 10→9, contactPick 9→9, eventPick 9→9, memoryConflict 9→10, notificationTriage 8→8, nudgeNow 3→4, rememberOrNot 7→6, route 8→9, sensitivity 10→9, timing 8→9, toolChoice 8→6.

What the numbers say: the Spark student is more confident. It handles about 70% of items at the 0.8 threshold versus about 50% for ep1, but it is right less often on what it handles. The certification uses the tightest error bound, and that gets worse, so the student does not qualify. Temperature scaling was not part of this protocol. A cal-fit temperature could recover some calibration, but that would be a separate experiment.

## Teacher agreement (training/spark_teacher/out/agreement.json, analyze.py)
- Spark vs Glimmer IQ2_M (old teacher) top-1 agreement on the 892 train rows: 860/892 = 0.964, mean total variation 0.086. Lowest per type: notificationTriage 0.80, rememberOrNot 0.92, nudgeNow 0.925. 0 parse failures.
- Extra nudge rows that Glimmer also labeled in nv2: 98/120 agree.
- Earlier sample check (agreement_sample.json): 549/566 = 0.97.
- Against **human gold** (analysis only): Spark 49/50 = 0.98 on QC50 vs Glimmer 0.86. Spark 178/180 = 0.989 on all of cal180 (cal labeler finished 10:58 PM ET, 180 rows, $1.20).

## License (docs/LICENSING.md)
Muse Model License (Muse Spark Open, Oct 15 2026, © Meta), read from the unsloth HF mirror LICENSE.md. The official meta-models repo is gated and was not diffed against the mirror. The license explicitly grants the rights to "modify (including fine-tune), create derivative works, distill". "Derivatives" includes any model "trained … distilled … using the Software or any outputs". Conditions: include the copyright notice, the license and the Usage Policy, and display "Built with Muse Spark Open" (NOTICE already says this). **Verdict: distilling a Llama student on Spark outputs is permitted, with attribution.** This only matters if a Spark-distilled model ships. floor_spark does not ship.

## Spend
Baseten Spark labeling: $11.06 total in spend.jsonl. This includes a $1.00 conservative estimate for a crashed run, $6.42 for train, $2.40 for extra, $1.20 for cal, and small probes. Modal: $0. PC and box compute: $0.

## Artifacts (box only, not uploaded because the model lost)
adapter `training/local_teacher/out/lora-llama1b-spark/adapter_model.safetensors` sha256 75c9bb6e…b069b; GGUF `…/lora-llama1b-spark-merged/Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf` sha256 d6f77bd1…6b43.
Files: after_floor_spark.{calibration_split,test}.json, .reliability.txt, .conformal.txt, conformal_after_floor_spark.calib_split.json.
