# Headline repro on cal180, Nov 4 2026 (box CPU, x86 AVX2/AVX-512, not iPhone, $0)

**Result: the shipping headline reproduces within the known llama-server noise.** 5/180 cal predictions differ from the Nov 1 rows. The tightest LTT bound is 10.4% at τ 0.90 (63/180 handled, 0 errors), against 10.2% (64/180, 0 errors) on Nov 1. 5% is still not certified.

## Setup
- Model: `models/SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf`. I checked the sha256 on this box: `a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2`, which matches LEDGER §15.
- Server: llama.cpp **13ec8f6** (`llama-server --version`: 0.8.0-dev, built at /tmp/gencode/llama.cpp, latest master). The Nov 1/2 numbers used **ddf48f8**. Flags mirror `eval/quant/run_quant_eval.sh`: `-c 4096 -t 6 --port 8088`. This build defaults to 4 slots with a unified KV cache. CPU: AMD EPYC-Turin, 16 cores. A second server for the OOS stress test (port 8089, `-t 6`) was started at the same time and sat idle while T1 ran (05:57–05:58 ET). The base-model server and the OOS jobs started after T1 finished. A later clean single-server re-run reproduced T1 bit-for-bit (see LATENCY_BOX.md), timing included.
- Pipeline: `python3 eval/experiments/run_prompt_variants.py --sets cal --variants v2+cc` (script unchanged, so the prompt is byte-identical), graded against the `gold` field in `eval/gold/gold_calibration.jsonl`. ECE is `training/reliability.py` `ece()` with 10 bins. LTT is `pg_train.conformal` (α 0.05, δ 0.1, tightest bound over the fixed grid). There is no temperature scaling.
- Raw rows: `eval/experiments/repro_nov4_cal180_v2cc.json`. Metrics and the row-level diff: `eval/experiments/repro_nov4_cal180_summary.json`, produced by `eval/experiments/summarize_repro.py`. The reference rows are `eval/results/after_floor.calibration_split.json` (Nov 1).

## Results (cal180, v2+cc, single option order)
| metric | Nov 1 ref (ddf48f8) | Nov 4 box (13ec8f6) | source |
|---|---|---|---|
| acc | 0.783 (141/180) | **0.794** (143/180) | summary.json `box.acc`, `ref_metrics.acc` |
| handled @ τ 0.8 | 0.494 (89) | **0.483** (87) | `handled_at_0.8` |
| acc on handled @ 0.8 | 0.955 | **0.966** | `acc_on_handled_at_0.8` |
| ECE (10 bins) | 0.042 | **0.040** | `ece_10bin` |
| LTT tightest bound (δ 0.1) | 10.2% @ τ 0.90, 64/180 (36%), 0 err | **10.4% @ τ 0.90, 63/180 (35%), 0 err** | `ltt_tightest` |
| LTT α 0.05 certified τ | none (needs 135 handled, 0 err) | none (needs 135 handled, 0 err) | `ltt_alpha05` |
| nudgeNow correct | 7/15 | 8/15 | `nudgeNow_correct` |
| median / p90 ms per decision (HTTP) | 146 / 226 (Nov 1 box) | 177 / 281 (other servers idle; clean re-run 175 / 288) | `median_ms`, `p90_ms`; clean: `eval/experiments/latency_box.json` |

Row-level diff against Nov 1 (`diff_vs_ref`): **5/180 predictions changed**, 4 of which flipped correctness. The largest confidence change is 0.072 and the mean is 0.015. Gold and type order are identical. Against the Nov 2 `q4ship` re-run (`eval/quant/q4ship.calibration_split.json`, ddf48f8), 3/180 predictions differ (max confidence change 0.092).

## Reading
- The drift is over the brief's 2-item threshold (5 changed predictions, net +2 correct). It is still the same size as the ±4-item run-to-run noise QUANT_IDENTITY.md measured on the *same* binary. It also coincides with a llama.cpp version change (ddf48f8 → 13ec8f6) and a different slot/KV layout (this build runs 4 slots on a unified KV cache). I did not chase it, per the brief.
- **The noise is state-dependent, not random.** A fresh server given the same request sequence reproduces this T1 run exactly (`eval/experiments/latency_clean_t6_single_cal180.json`: 0/180 preds differ, max conf diff 0.0). Three further passes on a warm server (`repro_nov4_cal180_v2cc_rep{2,3,4}.json`) agree with each other and differ from T1 on 7/180 preds. On those passes acc is 0.789, ECE 0.056 and the bound 10.9% @ τ 0.91 (60/180, 0 err). So on this binary the single-order cal180 numbers span **ECE 0.040–0.056 and bound 10.4–10.9%**, depending on prompt-cache/KV-slot state (`eval/experiments/perm_avg_cal180_summary.json` `single_order_spread`).
- Nothing material moves. The bound is 10.2% vs 10.4% (one fewer item above τ 0.90), ECE is 0.042 vs 0.040, and acc-on-handled is 0.955 vs 0.966. The shipping headline numbers stand as published from the Nov 1 run. These box numbers are a reproduction check, not a replacement.
