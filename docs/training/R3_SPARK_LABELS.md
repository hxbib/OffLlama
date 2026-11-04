# Round 3 Spark Open labels (fixed k=5)

Status: complete. Final measured numbers are at the end of this file.

## What ran

- Teacher: `meta-models/muse-spark-open-1026` on the existing Baseten endpoint
  (`https://inference.baseten.co/v1/chat/completions`). Hosted endpoint. The
  GPU is controlled by Baseten and cannot be selected by the caller.
- Sampling preserved from round 2: temperature 1.0, top_p 1.0,
  `reasoning_effort: low`, `max_tokens: 768` enforced per call.
- Every context gets a fixed k=5 draws. No agreement-based early stop. No vote
  imputation. Failures are preserved, never silently dropped.
- Inputs: `training/round3/anchor_inputs.jsonl` (600 rows, sha256
  `efea3ad2c53b8b93b4a7d5f4f39707de727dcfb8c9c4e1822c5f3c3be17685ed`) then
  `training/round3/target_comparison_inputs.jsonl` (2915 rows, sha256
  `f4bfe57be6ad9e013a3523ef64c76b14c3ae81399649211f52b2112053fd8c3e`), verified
  against `inputs_manifest.json`. The anchor is a subset of the full list, so
  its draws were reused and not recharged. These are existing training
  contexts, not a new holdout. test120 was not inspected or evaluated.

## Labeler

`training/round3/spark_label.py` replaces the budget handling of
`training/round2/label_round2.py`:

- Per-call reservation inserted in SQLite (WAL, FULL sync) before dispatch,
  priced at worst case: prompt upper-bound tokens x $1.25/1M plus
  `max_tokens` x $4.25/1M. Prompt bound is character count plus framing
  overhead, an assumed upper bound, not a tokenizer count.
- Settled calls are charged from raw provider usage. Completion tokens
  include reasoning tokens. Missing usage fails closed as UNKNOWN.
- Timeout, dropped connection, missing usage, or a crash between response
  and settlement stays UNKNOWN with its worst-case reserve charged.
  Explicit HTTP responses settle at 0. Each retry is a new reservation.
  At most 3 attempts per draw.
- Bounded in-flight pool (8 workers). No all-futures-at-once submission.
- 94 RPM throttle initially, reduced to 70 RPM on 2026-11-04 for quota
  sharing. Retry-After and exponential backoff still apply.
- One writer via lock file. Old label files and spend logs were not touched.
- Per-draw records (raw content, parsed letter, usage, logprobs only when
  genuinely returned, which Baseten does not return here) are appended with
  fsync to `draws.jsonl`. Vote counts and the derived majority target are
  stored separately from raw draws in `contexts.jsonl`. Vote fractions are
  empirical frequencies from fixed k=5 sampling. They are not teacher
  log-probabilities and must not be described as raw logits.

Fake-transport tests in `training/round3/spark_label_test.py` cover
concurrent near-cap admission, restart after a response-before-log failure,
unknown/timeout retention, missing-usage fail-closed behavior, retry caps,
throttle spacing and Retry-After, duplicate-input resume, partial votes, and
malformed labels. All 10 passed before the first paid call. The existing
`training/tests/test_pipeline.py` suite also passed (7 tests).

## Measured limits (not assumed)

- Header probe (parent, separately reserved $0.01, 1 call, HTTP 200):
  `x-ratelimit-limit-requests: 100`, `x-ratelimit-limit-tokens: 2000000`.
  Per official Baseten docs both windows are per minute. The token figure
  is 2M tokens per minute, not per second.
- Label calls average about 264 prompt + 150 completion tokens. At the
  100 RPM request cap that is roughly 41K tokens per minute, about 2% of
  the token window. Requests per minute is the binding bottleneck.
  Batching more text per request is the only way to use the token window,
  and that belongs to a later tranche with a different request shape.
- Prices $1.25 / $4.25 per 1M input/output come from
  `training/config/pricing.json` (verified 2026-10-31). They were not
  re-verified against a live billing API in this run. Baseten billing
  returned HTTP 403 earlier. Spend below is computed from raw usage at
  those rates.

## Phases and spend

Cap: $25.00 total for this matched experiment, including failures and
retries. Exact redacted commands are in the run log at
`/tmp/pocket-glimmer-training-scale/spark-v2/run.log`. Durable state:
`state.sqlite3`, `draws.jsonl`, `contexts.jsonl`, `status.json`,
`rate-ack.json` in the same directory.

1. Transport check: 24 balanced contexts (2 per type from the anchor),
   120 calls, all settled, billed $0.1223, parse rate 99.2%.
2. Anchor: 600 contexts, 3000 calls, all settled, billed $2.8947 total at
   that point, parse rate 99.43%. Gate of 95% parse passed. Projected full
   cost about $14, inside the cap, so the full list proceeded.
3. Full list: 2915 contexts at fixed k=5, reusing anchor draws.
   Mid-run the throttle was reduced from 94 to 70 RPM for quota sharing
   with a disjoint worker. The process was stopped and resumed on the same
   ledger. The 8 in-flight reservations became UNKNOWN ($0.0319 retained)
   and their draws were retried as new attempts. No settled draw was
   duplicated or recharged.

## Final results

Measured at completion on 2026-11-04T21:43:16Z. The labeling process has
stopped. No paid traffic is running from this task.

- Contexts complete: 2915 of 2915, each with 5 settled draws
  (14575 settled calls). Final usable context count: 2915.
- Valid parsed votes: 14412 of 14575 settled draws. Parse rate 98.88%.
  The 163 malformed draws are preserved with their raw strings and a null
  parsed letter. They are counted in vote denominators only through
  `n_valid`, never imputed.
- Billed usage (settled, from raw provider usage): $15.0155 on
  3,804,025 input tokens and 2,414,219 completion tokens. Completion
  tokens include 2,255,098 reasoning tokens.
- UNKNOWN reserved: $0.0636 across 16 calls. These came from the two
  quota restarts (8 in-flight reservations each time). Their draws were
  retried as new attempts and settled. The reserves stay charged in the
  accounting and are reported separately from billed usage.
- Committed total: $15.0791 of the $25.00 cap. Budget denied: 0 calls.
  HTTP error settlements: 0 in the final ledger. The $0.01 header probe
  was reserved separately by the parent and is not in this total.
- Per-type complete contexts: answerability 344, confirmBeforeAct 104,
  contactPick 333, eventPick 104, memoryConflict 137,
  notificationTriage 152, nudgeNow 886, rememberOrNot 144, route 101,
  sensitivity 98, timing 384, toolChoice 128.
- Unanimous 5-of-5 contexts: 2610.
- Majority letter versus the existing r2c target letter: same on 2834
  contexts, different on 81. This compares repeated fixed k=5 sampling
  with the older target construction (adaptive draws, smoothing, and
  imputation in r2c). It does not show that either distribution is the
  teacher's raw token probabilities, because Baseten returns no logprobs
  for this model.
- Throughput: sustained 70 RPM during quota sharing, then 99 RPM measured
  at 99 settled per minute after the expansion worker drained. The strict
  ceiling was fixed-interval start spacing, at most 99 starts in any
  60-second window, with Retry-After and backoff retained.

Artifacts under `/tmp/pocket-glimmer-training-scale/spark-v2/`:

- `contexts.jsonl`, 2915 rows, sha256
  `a6f7970dca2a35cd659ecce9082b92d9d4889ad9f2ae1a3827f34892b89f58d5`
- `draws.jsonl`, 14575 rows, sha256
  `04cabd1a7eac551667fc63f12a2ae8ac801d945dad2c850192f818dbeba9f418`
- `state.sqlite3` (reservation ledger), `status.json` (final status with
  `paid_traffic_stopped: true`), `rate-ack.json` (quota transitions),
  `run.log` (redacted commands and progress)

Limitations:

- Prices are the recorded $1.25 / $4.25 per 1M rates from 2026-10-31.
  Live billing could not be re-verified (HTTP 403 earlier). Spend here
  is computed from raw usage at those rates.
- The prompt-token worst case is a character-count upper bound, an
  assumed bound used only for reservations. Settled charges use actual
  provider usage.
- The hosted endpoint's GPU cannot be controlled or reported by the
  caller. The user request for the best GPUs does not apply to this
  endpoint, and no substitute teacher was deployed.
- These labels are training inputs on existing contexts. Label
  completion is not student improvement. No student was trained and
  nothing was promoted. The script accepts any future input file plus
  manifest, so a later data manifest can reuse it without code changes.
