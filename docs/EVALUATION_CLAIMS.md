# What the evaluation supports

Updated November 4, 2026. This corrects the earlier claim that the shipping pipeline has a 10.2% error certificate. The saved predictions and arithmetic remain useful; that guarantee does not follow from this experiment.

## Recorded results

Each row tests one multiple-choice decision, not a complete phone task. These results used llama-server on a Linux CPU, not the current iPhone app.

| Saved reference run | Decisions | Accepted at τ = 0.90 | Correct among accepted |
|---|---:|---:|---:|
| Calibration/selection split | 180 | 64 | 64 |
| Report-only split | 120 | 44 | 41 |

The report-only split has 98/120 correct before thresholding. At the earlier comparison threshold of 0.80, it accepts 61/120, with 56/61 correct. ECE is 0.0638 and AURC is about 0.085. Sources: `eval/results/after_floor.calibration_split.json`, `after_floor.test.json`, `AFTER_FLOOR.md`, and `RISK_COVERAGE.md`.

The 300 examples were written by one person and split by decision type: 15 calibration and 10 report-only examples per type. They are a small internal diagnostic set, not a random sample of deployment traffic. The project records selection on cal180; no shipping choice used test120. There are 13 saved report-only test120 result files, including a precommitted permutation experiment. It was not evaluated only once. The early prompt-selection artifact lacks original contexts, limiting a complete reconstruction of that comparison.

## Why 10.2% is a calculation, not a shipping guarantee

For 0 errors among 64 accepted decisions, the implemented Clopper–Pearson calculation with δ = 0.1 and a 99-threshold Bonferroni correction is:

`1 − (0.1 / 99)^(1 / 64) = 0.10217188684`

The Python and Swift implementations agree. However, the same 180 examples also selected the teacher, epoch, quantization, prompt and threshold. The 99-way correction covers thresholds only, not those model choices. [Learn then Test](https://arxiv.org/html/2110.01052v5) assumes a fixed pretrained model and independent, identically distributed calibration observations. This experiment does not establish those conditions for the selected pipeline or for real phone traffic. Merely saying that new requests should “look similar” does not repair the selection problem.

We therefore call 10.2% a **nominal calculation on the selection set**, not a valid post-selection bound. Saved reruns yield roughly 10.4–10.9%, with runtime state and the selected threshold affecting the result. The exact reference value is not a reproducibility guarantee.

At fixed τ = 0.90, the report-only count of 3 errors in 44 accepted decisions gives a nominal one-sided 90% binomial upper limit of about 14.6% (95%: 16.7%). That calculation also needs sampling assumptions; this hand-authored, stratified set does not establish a deployment guarantee. It is not a replacement certificate.

The 5% target was not certified. The often-quoted 135 zero-error accepted rows is the sample requirement for a fixed model, independent sampling, δ = 0.1 and a 99-threshold grid. It does not account for adaptive model selection. The 5%-target `conformal.py --profile` path would write τ = 1.01 when no threshold qualifies. The shipped τ = 0.90 was set separately using the tightest nominal calculation; it is a product operating point, not a 5% certificate.

## Limits of the evidence

- A decision-label score does not measure argument extraction, contact resolution, action execution, message delivery, cloud answers or complete tasks.
- The 27-item skill probe is separate, author-written diagnostic evidence: 25/27 argmax choices, 15/27 accepted and 15/15 correct among those. `skillPick` was not trained in the shipping distillation and has no calibration-set guarantee.
- CLINC contributes 1,000 unique out-of-scope utterances rendered twice, making 2,000 correlated decision rows. The 5/2,000 false-confident result at τ = 0.90 is a proxy, not a task error rate.
- iPhone tokenization, letter scores, Metal behavior, speed and memory still need direct verification. CPU measurements do not establish phone performance.

## A future independent evaluation

Keep the current GGUF, priors, prompt, threshold and test120 frozen. Before collecting new labels, define the target population, sampling plan, decision metric and separate task-success metric. Fix the pipeline before an independent certification set is seen. If further model selection is needed, use a separate development set; do not recycle any part of cal180 as unseen data. Record every device/runtime setting, report all planned runs, and check execution behavior separately from decision labels.

Earlier research logs are historical records. Their “certified” wording is superseded by this correction; their saved predictions have not been rewritten.
