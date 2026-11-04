# Round-3 Spark phone expansion (spark-phone-v1)

Batched iPhone data generation + matched phone decision labeling through the
licensed open-weight teacher `meta-models/muse-spark-open-1026` on Baseten.
Agent prose and Meta Model API outputs are never training targets; every
target below is a Spark Open vote or deterministic contract semantics.
Runtime student architecture unchanged. Allocation: **$54.99 Baseten, zero
Modal, zero Meta API**, separate from the matched $25 Spark worker and the
$0.01 rate probe. Rate: this worker throttles to **25 RPM** (the matched
worker owns 70 RPM of the measured 100 RPM / 2M TPM workspace limit;
`state/rate-ack-snapshot.json` saved before paid traffic). Max 2 concurrent
in flight (4 concurrent reads stall at the provider; observed, then fixed).

## Code (owned: training/round3/spark_phone_*)

- [spark_phone_common.py](/home/habib/.t3/worktrees/pocket-glimmer/t3-f127e998/training/round3/spark_phone_common.py) — contract loading, Reflex option rendering identical to the frozen phone inputs (verified 0 option-ID mismatches on all 3,115 v1 rows), batched label/generation prompts, exact-ID batch parsers, deterministic validators, dedupe keys.
- [spark_phone_store.py](/home/habib/.t3/worktrees/pocket-glimmer/t3-f127e998/training/round3/spark_phone_store.py) — durable SQLite ledger: worst-case reservation (full prompt bound + max completion, no cached-input discount) persisted **before** dispatch; UNKNOWN retains its reserve forever; HTTP errors settle $0 with each retry a new reservation; single-writer flock; 25 RPM + rolling token budget.
- [spark_phone_label.py](/home/habib/.t3/worktrees/pocket-glimmer/t3-f127e998/training/round3/spark_phone_label.py) — 12 contexts/request × 3 fixed passes. Batch IDs are namespaced by input-file hash so input sets sharing one ledger never collide. Vote frequencies are labelled empirical sample frequencies, never teacher probabilities; no soft target from fewer than 2 valid draws.
- [spark_phone_generate.py](/home/habib/.t3/worktrees/pocket-glimmer/t3-f127e998/training/round3/spark_phone_generate.py) — teacher-generated utterances/arguments from contract specifications only (never seeded from held-out utterances), deterministically validated, grouped, held-out screened.
- [spark_phone_convert.py](/home/habib/.t3/worktrees/pocket-glimmer/t3-f127e998/training/round3/spark_phone_convert.py) — labels → trainer rows (majority letter + alpha-0.5 smoothed sample frequencies); drops <2 valid draws or top share <0.6, counted, never imputed.
- [spark_phone_test.py](/home/habib/.t3/worktrees/pocket-glimmer/t3-f127e998/training/round3/spark_phone_test.py) — 14 fake-transport tests, all passing before any spend: reserve-before-dispatch, concurrent cap, restart→UNKNOWN, budget denial, exact-ID rejection, throttle ceiling.

## v1 pause and v2 remap

Parent found wrapper-free (type, context) leakage in v1 phone splits
(independently reproduced here: 530/736 dev and 578/753 calfit rows overlapped
v1 train). V1 labeling was paused; no v1 held-out label is used and no v1
evaluation is claimed. Settled v1 batches and spend stay immutable in the
ledger. Corrected v2 inputs arrived from the phone owner:
`frozen-v2/phone_v2_inputs_train.jsonl` SHA-256
`3b544c0f4b4678e213a6507ea11dba0beee783d6e611a73a7f580d6e8a083534`
(3,174 rows). Independent gate recheck: with candidates included (the actual
decision input) train↔dev/calfit overlap is **0**; context-only overlap
remains only for eventPick/contactPick rows with different candidate sets
(25 dev, 34 calfit rows) — distinct decision inputs, disclosed. Of 72 settled
v1 phone votes, 51 land in v2 train (remapped by `stable_prompt_id` =
SHA-256 of reflex type + context + candidates, topped up with 2 fresh passes
to fixed k=3); the other 21 now sit in held-out splits and are excluded from
training exports. The remaining 3,123 v2 train contexts were labeled fresh
(all 3,123 with ≥2 valid draws; converter kept 3,122, 1 dropped for top vote
share <0.6). Combined v2 export: `out/v2_trainer_rows_all.jsonl`, **3,173
trainer rows** (3,122 + 51 remapped) of 3,174 v2 train contexts.

## Generated corpus (independent of v1)

565 generation batches (38 contracts × 12 families + 10 underrepresented
Reflex types × 6 families), 5–10 utterances per request. 2,354 accepted
contexts (1,830 skillPick + ~524 Reflex-type contexts), 381 rejected:
379 deterministic disposition mismatches, 1 held-out core overlap,
1 duplicate. Provenance `teacher_generated_spark_open` is kept distinct from
developer templates; each row is its own group. Re-screened against v2
held-out cores: 0 overlaps. All 2,354 rows received ≥2 valid votes
(2,058 unanimous); converter kept **2,345 trainer rows** (9 dropped for top
vote share <0.6). Quality cross-check: on `valid_complete` skillPick rows the
Spark hard letter matches the intended contract in 162/168 cases (96.4%);
disagreement concentrates in cancellation/hard_negative families, where not
picking the contract is the intended behavior. No accuracy claim is made —
student evaluation has not run.

Artifacts (immutable, hashed in `status.json`):
- `out/generated_inputs.jsonl` — 2,354 contexts, SHA-256 `66f19ff7…`
- `labels/generated_spark_labels.jsonl` — per-context votes, raw completions preserved in `state/gen_batches.jsonl` / `state/label_batches.jsonl`
- `out/generated_trainer_rows.jsonl` — 2,345 comparison-ready trainer rows

## Spend

Durable ledger at `/tmp/pocket-glimmer-training-scale/spark-phone-v1/state/`
(`state.sqlite3` + batch JSONL + `status.json`). Rate coordination: traffic
was drained (committed $6.0750 at pause) so the matched worker could run at
99 RPM; after its durable `phase=complete` handback this worker resumed at
99 RPM and finished. **Final: 2,083 SETTLED calls, $8.72394 billed observed;
20 UNKNOWN, $0.215854 reserved (retained forever, never re-charged);
committed $8.939794 of $54.99.** No RESERVED calls remain; paid traffic is
stopped and the 99 RPM lease is handed back (`status.json` phase
`complete_lease_handed_back`). Total usable exports: 3,173 v2 trainer rows +
2,345 generated trainer rows = **5,518 labeled trainer rows**, plus the
2,354-row generated input corpus with full vote records. No accuracy claim:
no student was trained or evaluated under this allocation.
Two defects found and fixed en route: a throttle token-log double-append
(self-starvation) and batch-ID collisions across input sets sharing one
ledger (fixed by input-hash namespacing; the colliding run's votes were
excluded from fixed-k aggregation and re-bought — a small, recorded waste).

## Limits

Batched multi-item prompts are a different measurement than single-context
logprobs; per-item Context/Question/options text and option order are
identical, and the difference is disclosed wherever these labels are consumed.
Vote frequencies are not calibrated probabilities. Generated utterances are
teacher inventions, not iPhone traces. No student was trained or evaluated
under this allocation.
