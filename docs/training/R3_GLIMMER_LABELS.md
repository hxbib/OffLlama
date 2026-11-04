# Round 3 Glimmer probability labels

Verdict. PASS. All 2,915 matched training contexts now carry raw Glimmer next-token letter distributions. Every row passed the completeness and letter-mass checks. No student was trained. Shipping files stayed untouched.

## Teacher and readout

The teacher is the open-weight checkpoint `meta-models/Muse-Glimmer-30B` in the existing `pg-glimmer-weights` volume. The recorded revision is `main`. The prompt rendering matches `training/local_teacher/glimmer_teacher.py`. The checkpoint chat template renders the Reflex system and user body from `pg_train.prompts.chat_messages`. Rendering uses `reasoning_strength` low and `current_date` 2026-10-31. The forced suffix ` to=user<|message|>Answer:` follows the generation prompt. Tokenization uses `add_special_tokens=False`. The template SHA-256 is `cfc67e5f349f37690dfd31ed1f18bc4442a9dd32fe39a648f993cb4eb3cae678`.

Inference ran as direct batched vLLM 0.33.0 on one NVIDIA B200. Sampling used temperature 1.0 and top-p 1.0 with one output token. No logit bias was used. No constrained sampling was used. No reasoning text was read. The installed engine capped `SamplingParams` logprobs at 20, so a request for 100 fell back to 20. Exact prompt-logprob probes then completed every missing legal letter token. Each row therefore stores a complete raw distribution, not a vote share and not a floored renormalization.

Legal letter forms cover all 24 vocab tokens whose decoded text is whitespace plus one uppercase letter. Plain forms are token IDs 45 to 52. Space forms are 352, 410, 354, 401, 427, 433, 477, and 465. Tab forms are 55362, 41985, 20160, 30082, 53289, 30018, 31307, and 31579. Per-letter probability sums all three forms. A missing token is censored and never treated as zero. Nonfinite logprobs reject the row. A row is usable only when the distribution is complete and raw letter mass is at least 0.5.

## Gates and results

The 24-row balanced preflight passed with 24 usable rows. The 600-row anchor passed with 600 usable rows. The anchor gate required at least 95 percent usable, so the run continued to all 2,915 contexts. The final file holds 2,915 rows and 2,915 unique prompt hashes. Every row has status `valid_complete`. Letter mass spans 0.932 to 0.993 with median 0.979. Total recorded prompt tokens are 428,495.

Weak types stay visible. `nudgeNow` has 886 rows and median top probability 0.726. `eventPick` has 104 rows and median top probability 0.787. High letter mass means the teacher puts mass on letters. It does not prove the teacher is right on those types.

## Throughput

Warm chunks of 128 rows ran at a median of 16.4 rows per second on engine inference time. The warm range was 14.6 to 18.8 rows per second. Warm wall throughput had median 15.4 rows per second. Across all chunks, inference time totals 182.6 seconds for 15.96 rows per second. Total wall time across the three runs is 1,963.9 seconds for 1.48 rows per second including startup. Cold chunks paid Modal scheduling, weight loading, torch compilation, and FlashInfer JIT building. The first preflight chunk took 1,077.1 wall seconds for 24 rows. Later cold chunks took 423.7 and 286.0 wall seconds. Startup dominates small runs and the inclusive figure.

## Spend

The hard cap was $20 total on Modal. The budget ledger settled $3.81 using local wall seconds at the B200 rate of $6.25 per hour plus memory and CPU. Modal billing for 2026-11-04 attributes $1.89 to the three GPU apps. Preflight billed $0.37. Anchor billed $0.72. Full billed $0.80. The failed image build billed $0. The wall-based ledger is the conservative bound figure because it charges scheduling wait that Modal does not bill. Baseten spend was $0. Meta API spend was $0. Every launch first checked that settled cost plus the 1,200-second worst case stayed under the cap. No call retried automatically. All three ephemeral apps stopped with zero tasks. The deployed `pg-glimmer-vllm` app was never touched and still shows zero tasks.

## Runs and artifacts

Preflight app `ap-3J9f4LhHR5m6eV5iOR9EOj` labeled 24 rows. Anchor app `ap-SJ4Mav6HWdtYZv3Pi7TtRF` added 576 rows. Full app `ap-etw8IVdN6c1BNU4GOGWZvA` added 2,315 rows. Anchor rows were reused by prompt hash, so no context was charged twice. The label file is `/tmp/pocket-glimmer-training-scale/glimmer-v2/labels.jsonl` with SHA-256 `eb918f218eb4f8ff3ac52bbad80b6f633dc2bf66afb68e66b20ca76ffe3cd2fb`. Run status, exact redacted commands, chunk timings, and billing detail live in `/tmp/pocket-glimmer-training-scale/glimmer-v2/status.json`. The machine summary is `/tmp/pocket-glimmer-training-scale/glimmer-v2/summary.json`.

Each label row stores the source ID, decision type, candidates, prompt hash, prompt token count, option IDs, teacher identity, template hash, weight file byte sizes, top-k size, letter token logprobs, raw letter probabilities, renormalized distribution, letter mass, missing token list, top letter, token usage, GPU, phase, and timestamp. Code lives in `training/round3/glimmer_common.py` and `training/round3/glimmer_modal.py`. Stub tests live in `training/round3/glimmer_tests.py` and cover token aggregation, censored mass, nonfinite rejection, restart progress, and the spending bound. Nine tests pass.

## Failures recorded

The first preflight launch failed during image building. Jinja2 3.1.2 conflicted with the vLLM dependency floor of Jinja2 3.1.5. No GPU started and nothing billed. The fix removed the Jinja2 pin from the container image because rendering happens locally. One design fact also matters. The engine rejected 100 requested logprobs and the pipeline fell back to 20 plus exact probes. Probes are part of the readout, not a workaround that hides censoring.

## Limitations

The weights revision is the mutable string `main` in a cached volume. No immutable snapshot exists, so file byte sizes plus config and template hashes are the recorded weight identity. These bf16 logits differ from the shipped IQ2_M llama-server teacher logits. The labels are a new teacher readout and must not be mixed with the old 892 floor rows without a teacher-identity field. All inputs are existing training contexts. No held-out row was labeled or read for training. A larger expansion can reuse this pipeline against a new grouped data manifest. This run did not label any expansion rows. Student training waits for paired Spark data and the new evaluation protocol.
