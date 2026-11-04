# Training scale-up, November 4

Status: authorized and being prepared. No new training result is claimed in this document.

## Objective

Improve the phone model's useful local decisions and investigate broader local task capability
within the remaining credits. Preserve the deployed ep1 artifact until a candidate earns promotion.
The first controlled experiment tests whether more optimization helps the strongest prior recipe.
Data expansion and evaluation design proceed independently.

## Evidence that constrains the next experiments

- The shipping model learned from 892 Glimmer-labeled rows. Round 2 used up to 2,915 mixed rows.
- The existing expansion pool has 8,245 rows. Of these, 6,455 IDs are absent from the 1,790-row
  round-2 label file. They still need checks against older labels and source-family duplicates.
- Those 6,455 rows include 4,424 synthetic rows, 1,141 MASSIVE rows, 598 CLINC rows, and 292 SNIPS rows.
  A row count is not a count of independent task families.
- V4 on r2c improved development coverage and the nominal selection-set calculation, but its
  calibration error worsened on warm-server repeats. It did not pass the old acceptance gate.
- r2c changed target construction as well as the data mixture. The old experiments do not isolate
  a benefit from data quantity. Adaptive vote shares are not teacher token probabilities.
- The trainer uses zero-shot prompts while the shipping evaluation uses few-shot prompts with
  contextual correction. Treat prompt alignment as a separate hypothesis, not a hidden change.

## First controlled pilot

Keep the existing base Llama 3.2 1B Instruct, r2c data, V4 loss, rank, seed, and learning rate.
Change only training duration from one epoch to two. Use the existing Modal training script,
GPU mode, one candidate, and a unique name such as `V4-R3E2-20261104`.

Maximum reservation: $5 on Modal, including the job and attributable preparation. Do not start a
CPU fallback sweep. The existing GPU function has a 1,500-second timeout. Record the actual
hardware, completed steps, abort flag, input SHA-256, output SHA-256, and app ID. Reject partial
or failed runs as training evidence. Never overwrite round-2 artifacts or shipping files.

This pilot tests an optimization-scaling hypothesis. It does not itself establish generalization
or authorize promotion. A new data-and-evaluation plan must precede the larger sweep.

## Larger run requirements

1. Audit the existing pipeline and compare controlled choices for data quantity, target quality,
   prompt alignment, and calibration. Choose experiments that separate these effects.
2. Inspect licensed source datasets and public training splits. Record source revisions, hashes,
   transformation rules, and label provenance. Model-authored training content must come from
   the previously authorized Meta open-weight teachers, not an orchestrator's prose.
3. Create source-group-separated development and final reporting sets before scaling training.
   Deterministic expected outcomes and teacher-generated labels must be identified separately.
   A synthetic holdout is not a sample of real iPhone traffic.
4. Freeze the comparison command and promotion criteria before candidate results are inspected.
   Include decision quality, calibration, useful local coverage, per-type failures, general-answer
   regressions, and identical fresh/warm runtime sequences. Keep old test120 report-only.
5. Before API labeling, repair or replace the existing end-of-run-only budget accounting with
   durable per-call reservations, usage records, bounded retries, and restart-safe progress.
   Unknown billed outcomes retain their reservation. One owner controls each paid allocation.
6. Run a quality and throughput pilot, then expand data and GPU jobs in measured tranches.
   Check the actual available credits, queued work, and runtime before each tranche. Use remaining
   credits where an experiment can answer an unresolved question; spending is not the success metric.
7. Consider RL only for an explicit, tested reward such as a correct supported tool call or a
   deterministic answer. A teacher's confident opinion is not a verified phone action.
   General pretraining requires a separate throughput and useful-token estimate before allocation.

No new Baseten or Muse API spend has been allocated yet. Parent-side budget snapshots are under
`/tmp/pocket-glimmer-training-scale/`. Fresh task IDs and dispatch states will be stored in
`docs/training/round3_jobs.json` once dispatched.

## Sources

- [Round-2 results](../../eval/results/ROUND2.md) and [evaluation limits](../EVALUATION_CLAIMS.md).
- [Compute-optimal training](https://arxiv.org/abs/2203.15556) studies the balance between
  model size, data, and compute. It does not promise monotonic gains for this fine-tuning recipe.
- [Meta post-training guidance](https://dev.meta.ai/docs/muse-glimmer/post-training) distinguishes
  supervised demonstrations from RL with a checkable reward.
- [Meta Model API terms](https://dev.meta.ai/legal/terms-of-service) apply separately from
  the open-weight licenses. Preserve the repository's existing teacher-source restriction.
