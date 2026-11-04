# R3E2 evaluation. Two-epoch candidate under the frozen cal180 diagnostic

## Verdict

ISSUES. The two-epoch candidate does not pass the legacy gate on every pass. It passes on both warm passes and fails on both fresh passes. No promotion follows from this diagnostic even where a single pass passes. The independent new benchmark is still pending.

This evaluation spent $0. It ran no training, no paid teacher call, and no test120.

## What was compared

All three files were read as exact GGUFs on the same host, same llama.cpp build, same server flags, and same row order.

| Model | GGUF | SHA-256 | Role |
|---|---|---|---|
| SHIP | `models/SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf` | `a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2` | Shipping ep1 reference |
| V4gpuC | `/tmp/gencode/round2/V4-gpuC.gguf` | `1c456772fdee4a931e326b0cad7c32d6f59a32d552fab10809169ec7e79bd901` | One-epoch V4 on r2c, 365 steps. Modal log `V4-gpuC.json` flags `--lr 1e-4 --conf-weight`, H100 |
| R3E2 | Candidate in the pilot worktree, read-only | `90af88d44f4a2dae0bfad0803a4d14ed12aa7397d421380dee9e64a3606d837c` | Two-epoch V4 on r2c, 729 steps. Volume log flags add only `--epochs 2` |

The one-epoch file was located under `/tmp/gencode/round2`. No artifact was fetched for pay. If it had been missing, this report would have recorded that limitation instead.

Frozen protocol from `docs/training/ROUND3_EXECUTION.md`. Cal180 v2+cc is a historical diagnostic only. Each model got two fresh server starts. Each start ran one fresh pass then one warm pass on the same server. That is four passes per model and twelve passes total. The harness reuses `run_prompt_variants.run(rows, "v2", True, 0.8)`, `reliability.ece`, and `conformal.tightest_bound` without copying inference logic. Only the server URL is pointed at the isolated port.

Server per start. `/tmp/gencode/llama.cpp/build/bin/llama-server -m <gguf> --port <port> -t 4 -c 4096`. Ports were isolated at 8124 or the next unused port at or above 8124. SHIP used 8124. V4gpuC used 8125 because 8124 was still releasing when it launched. R3E2 cal used 8124 and drift used 8125. The port number does not enter inference. No other server was shared or stopped. No build cache was shared. Raw server logs sit in `/tmp/pocket-glimmer-training-scale/r3e2-eval/`.

CPUs were contended during the runs. This is a quality evaluation. Latency columns in the raw files measure contention, not phone speed. No iPhone speed result follows.

## Identity checks

Every pass passed these checks. A failure would have invalidated that pass.

- Row count. 180 rows on every pass. Gold file order is `g01` through the cal set with 15 rows per decision type across 12 types.
- Order. Predicted type and gold sequences match the gold file order on every pass. `verification.order_match` is true twelve times.
- Errors. Argmax errors plus correct equals 180 on every pass. Errors at the tightest-bound tau are reported separately below.
- Prompts. The SHA-256 of the 180 rendered v2 prompts is `1ed13c51d67a4722f8d458b4363324e007937f50abbbc8cb2666f263d52b6ef2`. It is identical for all three models because rendering does not depend on weights.
- Priors. Empty-context priors use the same three contexts, `N/A`, empty string, and `[MASK]`, through the same `cf_logp` cache. Each model has 14 cache entries. The cache is cleared at each fresh start and reused on the warm pass of that start, exactly as `eval_round2_reps.py` reuses it. Prior hashes differ by model because priors are model logits. Within each model the hash is identical across all four passes in this run. Fresh recomputation reproduced the same priors, and warm passes reused them.
- Fresh repeats. For each model, start 1 fresh and start 2 fresh give identical predictions and confidences to the precision stored. The same holds for the two warm passes. Server state still matters across the fresh to warm step, which is why the protocol keeps them separate.

Harness. `training/round3/duration_eval.py` parameterizes GGUF, name, and port. `training/round3/duration_eval_test.py` covers gate boundaries, paired deltas, row verification, pass identity, and drift matching with 11 tests and no server.

## Legacy gate per pass

Gate from `ROUND3_EXECUTION.md`. Clause A is nominal tightest bound below 10.0% with handled share at least 35%. Clause B is handled accuracy at tau 0.8 at least 95%. Clause C is 10-bin ECE at most 0.06. The gate requires all three on every pass. The bound is a nominal calculation on the selection set. Cal180 selected earlier models, so it is not a post-selection guarantee.

| Model | Pass | State | Bound | Tau | Handled | Share | Handled@0.8 | Acc on handled | ECE | A | B | C | Pass |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---|---|---|---|
| SHIP | 1 | fresh | 10.371% | 0.90 | 63/180 | 35.0% | 48.3% (87) | 96.55% | 0.0404 | fail | pass | pass | fail |
| SHIP | 2 | warm | 10.371% | 0.90 | 63/180 | 35.0% | 49.4% (89) | 96.63% | 0.0518 | fail | pass | pass | fail |
| SHIP | 3 | fresh | 10.371% | 0.90 | 63/180 | 35.0% | 48.3% (87) | 96.55% | 0.0404 | fail | pass | pass | fail |
| SHIP | 4 | warm | 10.371% | 0.90 | 63/180 | 35.0% | 49.4% (89) | 96.63% | 0.0518 | fail | pass | pass | fail |
| V4gpuC | 1 | fresh | 9.783% | 0.88 | 67/180 | 37.2% | 54.4% (98) | 96.94% | 0.0595 | pass | pass | pass | pass |
| V4gpuC | 2 | warm | 9.646% | 0.88 | 68/180 | 37.8% | 55.6% (100) | 97.00% | 0.0663 | pass | pass | fail | fail |
| V4gpuC | 3 | fresh | 9.783% | 0.88 | 67/180 | 37.2% | 54.4% (98) | 96.94% | 0.0595 | pass | pass | pass | pass |
| V4gpuC | 4 | warm | 9.646% | 0.88 | 68/180 | 37.8% | 55.6% (100) | 97.00% | 0.0663 | pass | pass | fail | fail |
| R3E2 | 1 | fresh | 9.783% | 0.89 | 67/180 | 37.2% | 60.6% (109) | 97.25% | 0.0635 | pass | pass | fail | fail |
| R3E2 | 2 | warm | 9.384% | 0.89 | 70/180 | 38.9% | 61.1% (110) | 96.36% | 0.0558 | pass | pass | pass | pass |
| R3E2 | 3 | fresh | 9.783% | 0.89 | 67/180 | 37.2% | 60.6% (109) | 97.25% | 0.0635 | pass | pass | fail | fail |
| R3E2 | 4 | warm | 9.384% | 0.89 | 70/180 | 38.9% | 61.1% (110) | 96.36% | 0.0558 | pass | pass | pass | pass |

Reading the table without averaging is the point.

- SHIP fails clause A on all four passes. Its bound stays at 10.371% because it handles only 63 rows with zero errors at tau 0.90. It passes calibration on every pass. The shipping reference does not meet the stricter round-3 diagnostic bound, which is why the diagnostic cannot be read as shipping is broken. It is a historical comparison bar.
- V4gpuC passes both fresh passes and fails both warm passes on ECE by 0.0063. This reproduces the saved round-2 pattern.
- R3E2 inverts that pattern. It fails both fresh passes on ECE by 0.0035 and passes both warm passes. Its second epoch moved ECE across the server-state boundary instead of removing the failure. Averaging fresh and warm ECE to about 0.0597 would hide both failures and is not reported as a pass.
- Errors at the bound tau are zero on all twelve passes. Argmax errors before thresholding are SHIP 37 fresh and 36 warm, V4gpuC 35 on both states, R3E2 34 fresh and 35 warm. At tau 0.8, handled errors are SHIP 3, V4gpuC 3, and R3E2 3 fresh and 4 warm. The bound tau and tau 0.8 count different handled sets.

## Paired deltas

Deltas pair identical pass identities. Fresh compares to fresh and warm compares to warm. Positive bound delta means the candidate bound is larger and worse. Positive ECE delta means worse calibration.

| Comparison | Pass | State | Delta bound | Delta ECE | Delta handled@0.8 | Delta acc on handled | Delta argmax acc |
|---|---|---|---:|---:|---:|---:|---:|
| R3E2 vs SHIP | 1 | fresh | -0.59 pp | +0.0231 | +12.22 pp | +0.70 pp | +1.67 pp |
| R3E2 vs SHIP | 2 | warm | -0.99 pp | +0.0040 | +11.67 pp | -0.27 pp | +0.56 pp |
| R3E2 vs SHIP | 3 | fresh | -0.59 pp | +0.0231 | +12.22 pp | +0.70 pp | +1.67 pp |
| R3E2 vs SHIP | 4 | warm | -0.99 pp | +0.0040 | +11.67 pp | -0.27 pp | +0.56 pp |
| R3E2 vs V4gpuC | 1 | fresh | 0.00 pp | +0.0041 | +6.11 pp | +0.31 pp | +0.56 pp |
| R3E2 vs V4gpuC | 2 | warm | -0.26 pp | -0.0105 | +5.56 pp | -0.64 pp | 0.00 pp |
| R3E2 vs V4gpuC | 3 | fresh | 0.00 pp | +0.0041 | +6.11 pp | +0.31 pp | +0.56 pp |
| R3E2 vs V4gpuC | 4 | warm | -0.26 pp | -0.0105 | +5.56 pp | -0.64 pp | 0.00 pp |

What the deltas support. The second epoch raises handled share at tau 0.8 by about 6 points over the one-epoch model and about 12 points over shipping, with similar handled accuracy. It does not improve the nominal bound on fresh passes and improves it only slightly on warm passes. It trades fresh calibration for warm calibration. That is a server-state interaction, not a clean duration win. Fresh versus warm prediction changes are small. R3E2 changes one prediction between its own fresh and warm passes, with a maximum confidence shift of 0.055. It differs from V4gpuC on 9 of 180 fresh predictions and from SHIP on 20.

Per-type detail is saved in each summary. On fresh passes, R3E2 gets nudgeNow 11 of 15 correct against 9 for V4gpuC and 8 for SHIP. It still gets notificationTriage 10 of 15 and contactPick 10 of 15. No type is hidden by the mean in the raw files.

## Drift probe on the candidate

The 40-prompt drift set has 23 checkable answers. No model service or API was required beyond the same local llama-server, so the probe ran on the candidate only.

- Method. Same llama-server binary with `-t 4 -c 4096`. Each prompt was sent to `/completion` as the Llama 3.2 single-user chat string with the fixed 26 Jul 2024 date, greedy temperature 0, top_k 1, 96 predicted tokens, seed 0, and no prompt cache. Answer matching and collapse detection copy `eval/drift/run_drift_gguf.py`. The original script sends HF token ids from a tokenizer that is not installed here. Sending the rendered string is the minimal parameterization that fits this host. Context is 4096 here against 2048 in the original. Short prompts make that difference immaterial, but it is recorded.
- Result. 23 of 23 checkable correct and 0 collapse in 40 outputs. Raw outputs are in the r3e2 drift file below.
- Coverage. This covers general-answer smoke behavior on 40 hand-written prompts. It does not cover argument extraction, action execution, or phone behavior. Shipping scored the same 23 of 23 with 0 collapse in its saved GGUF run. The candidate matches that smoke result. Exact text matches shipping on 19 of 40 prompts. Wording differences do not change any checkable answer.

## Artifacts and rerun

Raw rows and summaries use the `r3e2_` prefix in `eval/experiments/`. The aggregate file holds all twelve summaries and eight paired deltas. Durable status, exact commands, and server logs are under `/tmp/pocket-glimmer-training-scale/r3e2-eval/`.

Rerun from the repo root. Each model command runs both fresh starts and both warm passes.

```
python3 training/round3/duration_eval.py --gguf models/SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf --name SHIP --port 8124
python3 training/round3/duration_eval.py --gguf /tmp/gencode/round2/V4-gpuC.gguf --name V4gpuC --port 8124
python3 training/round3/duration_eval.py --gguf /home/habib/.t3/worktrees/pocket-glimmer/t3-fc78b8a3/training/round2/out/R3E2-20261104/V4-R3E2-20261104.gguf --name R3E2 --port 8124
python3 training/round3/duration_eval.py --aggregate
python3 training/round3/duration_eval.py --drift-gguf /home/habib/.t3/worktrees/pocket-glimmer/t3-fc78b8a3/training/round2/out/R3E2-20261104/V4-R3E2-20261104.gguf --drift-label R3E2 --port 8124
```

## Limits

- Cal180 is reused selection data. Nominal bounds here cannot certify deployment error.
- The new source-separated benchmark does not exist yet. Its gate is still pending and must be frozen before candidate scores on it are examined.
- Linux CPU llama-server numbers do not establish iPhone tokenization, Metal behavior, latency, memory, or thermal results.
- Decision letters do not measure contact resolution, argument correctness, execution, delivery, or complete tasks.
- Two fresh starts reproduced identical fresh results in this run. That stability is observed here under contention. It does not remove the known fresh versus warm ECE sensitivity.

## Audit of the resumed parent continuation

Scope. Decision rows at 18:36 and 18:39 on November 4, parent thread activity after position 1890 in run 48, and the parent files those rows cite. Earlier rows were not re-audited. New parent docs were read read-only. A final training result is not available just because delegates are running.

What checks out.

- Pilot accounting. The per-app Modal rows for app `ap-FvDrvwYplrjYFYMOfI4SVH` sum to $0.18916778. H100 $0.183965, CPU $0.00313685, memory $0.00050449, egress $0.00156144. The pilot report, duration status, budget snapshot, and decision row agree. The $5 reservation is closed and $4.81083222 is released. The month metered figure of $20.10288506 in the resumed summary differs from the $20.31 in the pilot status because the snapshots refreshed differently. The budget file correctly warns not to derive pilot cost from that difference. Remaining credits stay user-reported at $110 Modal and $80 Baseten floor. They are not API-verified balances. Baseten billing still returns 403 and its last repo spend record is $16.62.
- Frozen inputs. `training/round3/inputs_manifest.json` freezes a 600-row anchor at 50 per type and the full 2,915 matched contexts in r2c order. Hashes verify here. Anchor `efea3ad2c53b8b93b4a7d5f4f39707de727dcfb8c9c4e1822c5f3c3be17685ed`. Full `f4bfe57be6ad9e013a3523ef64c76b14c3ae81399649211f52b2112053fd8c3e`. Source r2c `afcf82d78426f6a096fbc52774cb654f44faaaac7a3ec97b0cc3953fec7dd3b3`. Anchor rows are an exact subset of the full file. These are existing training contexts, never new held-out data.
- Assignments. Training delegates in the next-jobs file all use Muse `muse-wonder-1.0` with max reasoning on source `4bf72c9`. App recovery keeps River07 and privacy review keeps River08, both at max variant. No training task was substituted to another model. The parent kept its own chat settings.
- Allocations. Glimmer $20 Modal, Spark Open $25 Baseten, data and evaluation $0. Protected reserves remain $15 Modal and $20 Baseten. Planning balances after the pilot and new reservations are $89.81083222 Modal and $55 Baseten. Spark runs on a hosted endpoint whose GPU the caller does not control. The parent stated that limit to the user.
- Caveats kept. Shipping GGUF, priors, tau 0.90, prompt, and test120 stay frozen. The chart correction to 9 of 120 or 7.5% at tau 0.90 is now trailed with the risk file as evidence. The parent told the user the cloud path is implemented but not fully working end to end, with iPhone execution and recovery still unverified. That matches the ledger.

Attention items.

1. Two job files must be read together. `round3_jobs.json` closes at recovery on 18:36. `round3_next_jobs.json` in the parent checkout holds the six jobs dispatched from 18:42 with status running at dispatch. The ledger table does not yet list those six by task ID. A takeover that reads only the older file will miss live work. Record the next-jobs entries into the canonical trail with terminal states when they return. Running at dispatch is not a result.
2. Spark evidence lives outside the repo. The live status under `/tmp/pocket-glimmer-training-scale/spark-v2/` shows the reservation ledger working. At the last check here it held 600 anchor rows, 1,122 settled draws, $1.172311 billed against the $25 cap, and the anchor input hash matching the frozen manifest. The decision trail records the $25 reservation and the earlier zero-until-fixed gate, but not the implementation commit, ledger path, or pilot scope. Add those before any tranche beyond the anchor. Unknown outcomes must keep their reservation, and the 2026-10-31 Baseten rates in the status file still need a live re-check before larger spend.
3. Glimmer throughput is not yet measured. The Glimmer delegate was dispatched with instructions to validate tokenization, letter mass, and missing tokens before scaling, and to prefer a fast compatible GPU. No run ID, GPU choice, or throughput figure was in the trail at audit time. The teacher shift between local IQ2_M logits and Modal bf16 logits must be recorded per run. Do not compare those targets as if they were the same teacher without the anchor check.
4. No new benchmark gate exists yet. The data delegate owns source-separated splits, but no split file or hash was frozen at audit time. Until that lands, cal180 remains selection history and this R3E2 diagnostic cannot promote any candidate. The parent contract already says this. The trail should name the split owner and freeze hash as soon as they exist, before scores are examined.
5. Recovery patch base risk remains open. The preserved patch is based on `009430f` while the current base carries newer privacy repairs. The resume brief correctly requires a three-way apply that preserves those repairs and reruns the suite. The earlier 144-test run with four assertions failing on old privacy cases is not an integrated result. Privacy review likewise has passing logs but no final verdict. Both stay open.
6. Budget snapshot holds two Modal summaries. The top-level summary is still the pre-pilot $19.92 snapshot while the resumed summary is embedded below it. The accounting note explains which figure to use. A hurried reader can still quote the stale block. Refresh the top-level block or label it superseded in place when the trail is next pushed.

None of these items invalidates the pilot or this evaluation. They mark where the resumed trail is still a dispatch record rather than a result record.
