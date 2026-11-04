# Round 3 execution and benchmark contract

Recorded November 4, before the next teacher outputs and exported-candidate evaluations.
This extends the user-authorized training work. The agent assignment remains Muse Code
`muse-wonder-1.0` with `reasoningEffort=max` for every training-related task.

## Current evidence

The two-epoch V4 pilot completed all 729 steps. Its GGUF hash was independently checked.
The current per-app Modal bill confirms $0.18916778. The report is [R3E2_PILOT.md](R3E2_PILOT.md).
The training function's zero-shot calibration diagnostic is already exposed. It is not a
deployment-matched evaluation or independent evidence of improvement.

The archived [training investigation](evidence/TRAINING_GROUNDING.md) and
[data investigation](evidence/DATA_GROUNDING.md) are source reports. Their proposals are not
automatically accepted gates. In particular, a bound optimized on a development set cannot
substitute for independent testing, and licensing alone does not establish label correctness.

## Separate teacher quality from data quantity

Both teachers use the exact input files in `training/round3/inputs_manifest.json`.
The 600-row anchor is balanced across the 12 existing decision types. The complete matched
comparison contains the same 2,915 contexts as r2c. These are existing training examples,
never new held-out evaluation data. Agents must not write their own training answers.

- Glimmer supplies raw next-token probabilities through the previously authorized open weights.
  Validate tokenization, prompt rendering, letter mass, and missing-token behavior before scaling.
  Do not call probabilities after sampling constraints or positive logit bias raw teacher probabilities.
- Spark Open supplies five independent draws per context. Save actual counts and all draws.
  Do not impute unseen votes or stop early on agreement. Treat vote frequencies as vote frequencies.
- Run a small transport and label-quality check, then complete the anchor and up to all matched
  contexts if that check passes. Save failures and uncertain labels. Do not silently drop hard rows.
- Use separate output namespaces, manifests, spend records, and result files. Keep prompts and
  source contexts traceable. Do not change the shipping model or teacher identity.
- Larger data-volume experiments follow the new split manifest. Hold target construction,
  training recipe, and evaluation fixed when changing data quantity.

Glimmer has a $20 Modal allocation. Spark Open has a $25 Baseten allocation. These are maximum
allocations including preparation, retries, failed calls, and idle GPU time. GPU selection must
consider current availability, compatibility, measured throughput, and the allocation. Prefer a
fast compatible accelerator for batching; do not assume the largest GPU improves model quality.
Spark Open on Baseten is a hosted endpoint whose GPU is controlled by the provider.

Before any Spark paid call, implement and test durable per-call reservations, bounded concurrency,
bounded retries, and restart recovery. Unknown outcomes retain their reservation. The old
`label_round2.py` budget check cannot enforce this allocation. Reserve at least $15 Modal and
$20 Baseten for later evaluation and integration. See [budget record](round3_budget_snapshot.json).

## Strengthen the benchmark before promotion

Build new source-traceable splits for training, development, calibration fitting, and final reporting.
Preserve publisher split, original intent, source revision, licensing, transformation, and label origin.
Split related templates, paraphrases, scenarios, and conversations as groups. Audit normalized and
near-duplicate contexts across old training, evaluation, and CLINC OOS stress data. Unresolved source
identity or an uncertain mapping is an exclusion or a pending label, never silently trusted gold.

Cover these distinct capabilities with separate scores:

- Decision routing and abstention, including private text and requests outside supported actions.
- Exact action arguments, contact method, date, timezone, and confirmation requirements.
- Action outcome with fake executors and durable state, including permission refusal and restart.
- General answers, grounded document answers, and answerability.
- Cloud selection, privacy withholding, scrubbed outbound text, and honest result provenance.
- Phone latency, memory, and thermal behavior, recorded only when a real device can run the test.

Public assistant datasets and API schemas can supply inputs and deterministic contracts. They are
not automatically iPhone interaction traces. Synthetic, teacher-labeled, deterministic, and human
labels must remain distinct in reports. More test rows from one template do not add independent evidence.

The benchmark worker must commit executable validation, split hashes, and an exact comparison
protocol before candidate scores are examined. For deployment-matched decision evaluation, use the
same GGUF readout, prompts, contextual correction, row order, server flags, and explicit fresh/warm
sequence for every model. Record two server starts, each with a fresh and warm pass. Report every
pass, count all errors, and retain per-type counts. Keep cal180 as historical development data and
test120 report-only. Do not derive a certification claim from either reused set.

Primary comparison is useful handled share at a threshold chosen only on calibration-fit data,
with a fixed development error constraint and separate calibration, argument, and answer regressions.
The exact numerical new-set gate is pending benchmark construction and must be frozen before results.
No candidate may be promoted while that gate or its evidence is missing.

## Evaluate the completed duration pilot now

Use the existing round-2 gate unchanged for a historical diagnostic, not promotion. Compare the
shipping GGUF, the one-epoch V4-gpuC, and the two-epoch candidate on cal180 with two fresh starts
and one subsequent warm pass per start. Preserve the existing v2+cc protocol. The legacy clauses
are nominal bound below 10.0% with handled share at least 35%, handled accuracy at tau 0.8 at least
95%, and 10-bin ECE at most 0.06, on every pass. Report the nominal calculation with its selection
caveat. Run no test120 and fit no new priors or thresholds for this diagnostic.

No live iPhone or Xcode access has been recovered. Linux tests and cloud responses cannot establish
phone readiness. Keep that limitation separate from measured improvements.
