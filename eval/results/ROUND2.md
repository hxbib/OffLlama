# Round 2 retrain (Nov 4 2026): Muse Spark Open label expansion + LoRA sweep. FINAL (rejected; ep1 stays shipping)

> November 4 correction: earlier “certified” claims below are historical. Model selection reused cal180; the nominal bound is not a post-selection guarantee. See [evaluation limits](../../docs/EVALUATION_CLAIMS.md). Saved predictions are unchanged.

Status at 07:52 ET: labeling finished; 1 of 17 candidates evaluated. The final table and verdict come at the end of this file.

## What changed versus the brief (read first)
- **Modal GPUs are not available on this account.** Every GPU type (H100, A100-80GB, L40S, A10G, L4, T4) returned `Please add a payment method to use <GPU> GPU functions` (07:10 ET). The sweep therefore ran on **Modal CPU containers** (32 vCPU, 48 GiB, bf16), with one container per variant in parallel. A 1-epoch run took ~24 min on CPU instead of a few minutes on an H100. One container was preempted twice; Modal restarted it on the same input.
- **Baseten caps this key at 100 requests/min** (`X-Ratelimit-Limit-Requests: 100`), not just 2M TPM. Fixed-k=5 on 4,800 items (24k calls) could not fit the window. I switched to **adaptive k**: draw 2; if both agree (and parse), stop; otherwise draw up to 5. On the Nov 1 k=8 data, P(votes 3–5 agree | votes 1–2 agree) = 850/866 = 0.982. Mean k = 2.48. The run started at ~32 workers, hit the RPM cap (a 429 storm), and was restarted with a client-side 90–96 RPM throttle; after that there were 0 429s.
- Labeling: 1,790 new items (07:20 snapshot: 1,355 kept rows; the full set at the 07:30 stop: 1,750 kept). Weak types came first (nudgeNow, timing, contactPick, answerability), per the orchestrator's 06:59 instruction.

## Gate (LEDGER §0 + orchestrator noise rule)
On cal180, v2+cc, graded against gold: (a) LTT tightest bound (α 0.05, δ 0.1) below the box repro of 10.4% at a τ with handled share ≥ 35%, **and below 10.0% on every repeat run** to clear the 10.4–10.9% single-order noise band (PERM_AVG.md), or certify α 0.05; (b) acc-on-handled @τ0.8 ≥ 0.95; (c) ECE ≤ 0.06. test120 is run once, and only for a single winner.

## Results so far (cal180)
| model | rep | acc | handled@0.8 | acc-on-handled@0.8 | ECE | LTT tightest (τ, handled, err) | gate |
|---|---|---|---|---|---|---|---|
| SHIP (ep1, box repro) | 1, 2 | 0.794 | 0.483 (87) | 0.966 | 0.040 | 10.4% (0.90, 63 = 35%, 0) | reference |
| V1-s720 (pure KL, 07:20 labels) | 1, 2 | 0.800 | 0.211 (38) | 1.000 | **0.178** | 10.3% (0.67, 85 = 47%, 1) | ✗ (c), (a-strict) |

V1 shows the opposite failure to ep2/nv2/Spark-ep1: pure KL against vote-frequency targets smoothed with α=0.5 makes the student **under-confident**. Most k=2 unanimous rows get a top-option target of only 0.71–0.83.


## FINAL (written 08:25 ET by the orchestrating agent from the JSONs on disk; the previous agent's session was cut off after finishing the repeat runs)

**Verdict: REJECTED under the pre-registered gate. ep1 stays shipping. Round 2 is the strongest candidate so far and a documented near-miss.**

Correction to the paragraph above: Modal GPUs were unavailable only until 07:58 ET (Habib added a payment method); the `-gpu`, `-gpuB`, `-gpuC` runs below were trained on **Modal H100** in parallel (one container per variant, bf16, ~1–2 min of training each). `V1-s720` was the earlier CPU-container run.

### All variants, cal180, v2+cc vs gold (every row from `eval/experiments/round2_<model>_cal*.json` + `_summary.json`)
| model | run | recipe | train file | acc | handled @0.8 | acc on handled @0.8 | ECE | LTT tightest (τ, handled, err) | gate |
|---|---|---|---|---|---|---|---|---|---|
| SHIP | 1 | ep1 shipping (reference) | r2a | 0.794 | 0.48 | 0.966 | 0.040 | 10.4% @0.9 (63/180 = 35%, 0 err) | ✗ a |
| SHIP | 2 | ep1 shipping (reference) | r2a | 0.794 | 0.48 | 0.966 | 0.040 | 10.4% @0.9 (63/180 = 35%, 0 err) | ✗ a |
| SHIP | 3 | ep1 shipping (reference) | r2a | 0.794 | 0.48 | 0.966 | 0.040 | 10.4% @0.9 (63/180 = 35%, 0 err) | ✗ a |
| SHIP | 4 | ep1 shipping (reference) | r2a | 0.800 | 0.49 | 0.966 | 0.052 | 10.4% @0.9 (63/180 = 35%, 0 err) | ✗ a |
| V0-gpu | 1 | floor recipe (KL+0.5CE, r16, lr 2e-4, 1 ep) | r2a (07:20 snapshot, 2,139 rows) | 0.789 | 0.36 | 0.969 | 0.158 | 10.0% @0.66 (108/180 = 60%, 2 err) | ✗ c |
| V0B-gpuB | 1 | V0B | r2b | 0.817 | 0.39 | 0.972 | 0.109 | 12.3% @0.71 (101/180 = 56%, 3 err) | ✗ a,c |
| V0C-gpuC | 1 | V0C | r2c (full, 2,915 rows: 892 Glimmer + 273 Spark Nov 1 + 1,750 Spark r2) | 0.800 | 0.47 | 0.964 | 0.088 | 11.3% @0.69 (110/180 = 61%, 3 err) | ✗ a,c |
| V0C-gpuC | 2 | V0C | r2c (full, 2,915 rows: 892 Glimmer + 273 Spark Nov 1 + 1,750 Spark r2) | 0.800 | 0.47 | 0.964 | 0.088 | 11.3% @0.69 (110/180 = 61%, 3 err) | ✗ a,c |
| V1-s720 | 1 | pure KL (no CE), r16, lr 2e-4 | r2a (07:20 snapshot) | 0.800 | 0.21 | 1.000 | 0.178 | 10.3% @0.67 (85/180 = 47%, 1 err) | ✗ a,c |
| V1-s720 | 2 | pure KL (no CE), r16, lr 2e-4 | r2a (07:20 snapshot) | 0.800 | 0.21 | 1.000 | 0.178 | 10.3% @0.67 (85/180 = 47%, 1 err) | ✗ a,c |
| V2g-gpu | 1 | KL+0.5CE, r32, lr 1e-4 | r2a (07:20 snapshot, 2,139 rows) | 0.817 | 0.40 | 1.000 | 0.131 | 9.1% @0.8 (72/180 = 40%, 0 err) | ✗ c |
| V2g-gpuC2 | 1 | KL+0.5CE, r32, lr 1e-4 | r2c | 0.811 | 0.46 | 0.988 | 0.098 | 9.6% @0.78 (92/180 = 51%, 1 err) | ✗ c |
| V3g-gpu | 1 | KL only, smoothed 0.05, 2 ep | r2a (07:20 snapshot, 2,139 rows) | 0.833 | 0.31 | 0.982 | 0.160 | 10.9% @0.6 (115/180 = 64%, 3 err) | ✗ a,c |
| V3g-gpuC2 | 1 | KL only, smoothed 0.05, 2 ep | r2c | 0.811 | 0.41 | 0.986 | 0.139 | 9.6% @0.75 (92/180 = 51%, 1 err) | ✗ c |
| V4-gpu | 1 | KL+0.5CE, teacher-confidence-weighted, lr 1e-4 | r2a (07:20 snapshot, 2,139 rows) | 0.811 | 0.34 | 0.968 | 0.121 | 12.2% @0.75 (87/180 = 48%, 2 err) | ✗ a,c |
| V4-gpuB | 1 | KL+0.5CE, teacher-confidence-weighted, lr 1e-4 | r2b | 0.806 | 0.44 | 0.987 | 0.097 | 10.7% @0.79 (82/180 = 46%, 1 err) | ✗ a,c |
| V4-gpuC | 1 | KL+0.5CE, teacher-confidence-weighted, lr 1e-4 | r2c (full, 2,915 rows: 892 Glimmer + 273 Spark Nov 1 + 1,750 Spark r2) | 0.806 | 0.54 | 0.969 | 0.059 | 9.8% @0.88 (67/180 = 37%, 0 err) | PASS |
| V4-gpuC | 2 | KL+0.5CE, teacher-confidence-weighted, lr 1e-4 | r2c (full, 2,915 rows: 892 Glimmer + 273 Spark Nov 1 + 1,750 Spark r2) | 0.806 | 0.54 | 0.969 | 0.059 | 9.8% @0.88 (67/180 = 37%, 0 err) | PASS |
| V4-gpuC | 3 | KL+0.5CE, teacher-confidence-weighted, lr 1e-4 | r2c (full, 2,915 rows: 892 Glimmer + 273 Spark Nov 1 + 1,750 Spark r2) | 0.806 | 0.56 | 0.970 | 0.066 | 9.6% @0.88 (68/180 = 38%, 0 err) | ✗ c |
| V4-gpuC | 4 | KL+0.5CE, teacher-confidence-weighted, lr 1e-4 | r2c (full, 2,915 rows: 892 Glimmer + 273 Spark Nov 1 + 1,750 Spark r2) | 0.806 | 0.56 | 0.970 | 0.066 | 9.6% @0.88 (68/180 = 38%, 0 err) | ✗ c |
| V6g-gpu | 1 | V4 + entropy bonus 0.1 | r2a (07:20 snapshot, 2,139 rows) | 0.806 | 0.28 | 1.000 | 0.136 | 12.7% @0.8 (51/180 = 28%, 0 err) | ✗ a,c |
| V6g-gpuC | 1 | V4 + entropy bonus 0.1 | r2c (full, 2,915 rows: 892 Glimmer + 273 Spark Nov 1 + 1,750 Spark r2) | 0.817 | 0.52 | 0.989 | 0.068 | 8.7% @0.84 (76/180 = 42%, 0 err) | ✗ c |
| V6g-gpuC | 2 | V4 + entropy bonus 0.1 | r2c (full, 2,915 rows: 892 Glimmer + 273 Spark Nov 1 + 1,750 Spark r2) | 0.817 | 0.52 | 0.989 | 0.068 | 8.7% @0.84 (76/180 = 42%, 0 err) | ✗ c |
| V6g-gpuC | 3 | V4 + entropy bonus 0.1 | r2c (full, 2,915 rows: 892 Glimmer + 273 Spark Nov 1 + 1,750 Spark r2) | 0.817 | 0.52 | 0.979 | 0.067 | 8.9% @0.84 (74/180 = 41%, 0 err) | ✗ c |
| V6g-gpuC | 4 | V4 + entropy bonus 0.1 | r2c (full, 2,915 rows: 892 Glimmer + 273 Spark Nov 1 + 1,750 Spark r2) | 0.817 | 0.52 | 0.979 | 0.067 | 8.9% @0.84 (74/180 = 41%, 0 err) | ✗ c |

Gate clauses: (a) LTT tightest bound < 10.0% at handled share ≥ 35% on every run; (b) acc-on-handled @τ0.8 ≥ 0.95; (c) 10-bin ECE ≤ 0.06. Runs 1–2 of each finalist are fresh-server starts (identical, as expected from PERM_AVG.md's noise analysis); runs 3–4 are warm-server repeats, which is where the shipping model itself spans ECE 0.040–0.056.

### Finalists
- **V4-gpuC** (KL + 0.5 CE, teacher-confidence-weighted, lr 1e-4, r2c): bound **9.6–9.8% @τ0.88** (67–68/180 handled, 0 errors) vs ep1's 10.4% @0.90 (63/180); handled @0.8 **0.54–0.56** vs 0.48; acc-on-handled 0.969–0.970 vs 0.966; **ECE 0.059 (fresh) / 0.066 (warm) vs 0.040.** Passes on the two fresh runs, fails clause (c) by 0.006 on both warm runs. Under the rule as written (every run), it does not ship. It is the first retrain in this project that improves the certified bound AND coverage without losing accuracy on handled decisions; the ECE drift is the only thing between it and shipping.
- **V6g-gpuC** (V4 + entropy bonus 0.1): best bound of the day, **8.7–8.9% @τ0.84** (74–76/180 = 41–42%, 0 errors), acc-on-handled 0.979–0.989, but ECE 0.067–0.068 on all four runs → fails (c).
- V2g-gpuC2 (r32): bound 9.6% but at τ0.78 with 1 error and ECE 0.098 → fails (c).
- Everything trained on the 07:20 snapshot (`-gpu`, `-s720`) or on r2b was worse than its r2c twin: more labels helped on every axis.

No test120 run was made for round 2 (no winner; the frozen split stays untouched). No file in models/ changed.

### What we learned (only what the numbers support)
1. Pure KL on vote-frequency targets (Laplace-smoothed) makes the student under-confident (V1: handled 0.21, ECE 0.178). The 0.5·CE term is load-bearing.
2. Teacher-confidence weighting + lr 1e-4 (V4) is the best recipe tried: better bound, more coverage, same accuracy on handled.
3. An entropy bonus (V6g) buys the best certified bound but pushes ECE the wrong way at this data size.
4. ECE drifts with llama-server warm state by ~0.007 for every model; a gate set at 0.060 with a candidate at 0.059 was always going to be decided by that noise. Next time: pre-register the ECE clause as a band relative to the shipping model's own noise, or add cal rows so the LTT bound dominates.
5. 1,790 more Spark Open labels at ~$5.56 moved the certified bound by ~0.7 points; data, not recipe, is the cheapest remaining lever.

### Labels and spend
- New labels: 1,790 items via Muse Spark Open on Baseten (`meta-models/muse-spark-open-1026`, adaptive k 2→5, mean k 2.48, reasoning_effort low, temperature 1.0), weak types first; kept rows after the ≥0.6 top-vote filter: 1,750 (`training/round2/out/build_stats_r2c.json`).
- Baseten this run: $5.56; **cumulative $16.62** (training/spark_teacher/spend.jsonl).
- Modal: saved billing snapshot at 2026-11-04 13:19 UTC totals **$17.82792011 for pg-round2** and **$0.25687086 for pg-glimmer**, $18.08479097 combined. This supersedes the earlier “< $10” estimate and is not a current bill. Snapshot SHA-256: `bb773d928457c1fcaf186bb213392b59dbc4bc623b06457fef3b922dd2708209`.
- Meta Model API: separate (multimodal smoke tests, eval/meta_api/spend.jsonl).

### If this ships later (not today)
Attribution for a Spark-labeled student would read "Built with Llama" + "Built with Muse Spark Open" (docs/LICENSING.md). The adapters and GGUFs are in the Modal volume and /tmp/gencode/round2/ on the build box; the recipe is `training/round2/modal_round2.py` variant V4 on `r2c_train.jsonl`.
