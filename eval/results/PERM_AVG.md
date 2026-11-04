# Option-order permutation averaging on cal180 (Nov 4 2026, box CPU x86 AVX2/AVX-512, not iPhone, $0)

**Verdict: does not ship.**
- **Full-K cyclic averaging (cycall/cyc4) loses clearly on cal180.** The LTT bound is better (7.8% vs 10.4%, 47% vs 35% handled), but ECE gets worse by 0.03–0.06 in both replicates, because averaging makes the model under-confident. test120 was not run for it.
- **K=2 (original + reversed, arithmetic mean) is borderline on cal180.** Under the pre-registered rule against T1 it loses on replicate 1 (ECE +0.012, over the 0.01 allowance by 0.002) and wins on replicate 2 (ECE +0.001). Both replicates sit inside the single-order ECE noise band. I wrote a pre-commit and then ran test120 **once** for K=2, report only. **test120 did not confirm it:** ECE was 0.087 against 0.047 for the identity order in the same run, and at the cal-selected τ it handled more items with more errors.
- Nothing changes in the shipping pipeline.

## Method
- Script: `eval/experiments/run_perm_avg.py` (new). It imports `render`, `relabel`, `softmax`, `load` and `CF_CONTEXTS` from `run_prompt_variants.py`, which is unchanged. For each item the v2+cc readout runs under K orders of the **query** item's options; the few-shot exemplars keep their order. Each letter distribution is mapped back to option ids, then the K distributions are combined two ways: arithmetic **mean**, and normalized **geometric mean (geo)**. The contextual-calibration prior is recomputed per (type, n_options, permutation), because the positional prior moves with the order. Permutation 0 is the identity, so its prompt is byte-identical to single-order v2+cc.
- Modes:
  - **rev**: K=2, original + reversed.
  - **cycall**: all n cyclic rotations, so K=n (2, 3, 4 or 7 options). Mean K is 3.35 on cal180.
  - **cyc4**: the first min(n,4) rotations, derived offline from the cycall per-permutation distributions. Mean K is 3.10.
- Server: the shipping Q4_K_M (sha256 a5c60a88…82c2) on llama.cpp 13ec8f6, `-t 6 -c 4096`, port 8088. Two other servers were running on the same 16-core box at the same time (see LATENCY_BOX.md).
- Selection rule (fixed in the brief before any results): perm-avg wins iff [the cal180 LTT tightest bound improves, OR the bound is equal and the handled share is higher] AND ECE ≤ baseline ECE + 0.01. The baseline is the T1 single-order run (`eval/experiments/repro_nov4_cal180_v2cc.json`). The rule is implemented in `eval/experiments/summarize_perm.py` as `verdict_vs_T1`. A post-hoc sensitivity check, `verdict_paired_vs_same_run_order0`, compares against the identity order from the same run. It is labeled post hoc and is not used for the verdict.
- Sources:
  - Replicate 1 raw per-item, per-permutation distributions: `eval/experiments/perm_avg_cal180.json`; metrics: `eval/experiments/perm_avg_cal180_summary.json`.
  - Replicate 2 raw: `perm_avg_cal180_rev_rep2.json` and `perm_avg_cal180_cycall_rep2.json`; metrics: the matching `*_summary.json`.
  - test120: `perm_avg_test120_rev_ONCE.json` and `perm_avg_test120_rev_ONCE_summary.json`.
  - Pre-commit: `eval/experiments/perm_test120_precommit.txt`.
- AURC is the area under the risk–coverage curve; lower means better confidence ranking. It is a diagnostic, not a selection criterion.

## Results: cal180 (N=180, graded against gold), replicate 1 (`perm_avg_cal180_summary.json`)
| variant | K | acc | handled @0.8 | acc on handled @0.8 | ECE | AURC | LTT tightest bound (τ*, handled, errors) | median / p90 ms | rule vs T1 |
|---|---|---|---|---|---|---|---|---|---|
| **single order (T1 baseline)** | 1 | 0.794 | 0.483 (87) | 0.966 | **0.040** | 0.0673 | 10.4% (0.90, 63 = 35%, 0) | 177 / 281 | baseline |
| rev / mean | 2 | 0.767 | 0.411 (74) | 1.000 | 0.052 | 0.0700 | 8.9% (0.80, 74 = 41%, 0) | 490 / 704 | bound ✓, ECE +0.012 ✗ → **lose** |
| rev / geo | 2 | 0.761 | 0.456 (82) | 0.976 | 0.053 | 0.0748 | 11.2% (0.83, 78 = 43%, 1) | 490 / 704 | bound ✗ → lose |
| cyc4 / mean | 3.10 | 0.789 | 0.367 (66) | 1.000 | 0.098 | 0.0582 | 8.8% (0.77, 75 = 42%, 0) | 859 / 1855 | ECE +0.058 ✗ → lose |
| cyc4 / geo | 3.10 | 0.783 | 0.417 (75) | 1.000 | 0.082 | 0.0583 | 7.8% (0.77, 85 = 47%, 0) | 859 / 1855 | ECE +0.042 ✗ → lose |
| cycall / mean | 3.35 | 0.789 | 0.367 (66) | 1.000 | 0.101 | 0.0579 | 8.8% (0.77, 75 = 42%, 0) | 859 / 2196 | ECE +0.060 ✗ → lose |
| cycall / geo | 3.35 | 0.789 | 0.417 (75) | 1.000 | 0.084 | **0.0577** | **7.8% (0.77, 85 = 47%, 0)** | 859 / 2196 | ECE +0.044 ✗ → lose |

## Replicate 2 (same commands, rerun; `perm_avg_cal180_rev_rep2_summary.json`, `perm_avg_cal180_cycall_rep2_summary.json`)
| variant | acc | handled @0.8 | acc on handled | ECE | AURC | LTT tightest | rule vs T1 |
|---|---|---|---|---|---|---|---|
| identity order (same run) | 0.789 | 88 | 0.943 | 0.056 | 0.0687 | 10.9% (0.91, 60, 0) | n/a |
| rev / mean | 0.767 | 75 | 0.987 | 0.041 | 0.0695 | 9.1% (0.82, 72 = 40%, 0) | bound ✓, ECE +0.001 ✓ → **win** |
| rev / geo | 0.761 | 82 | 0.976 | 0.046 | 0.0738 | 11.6% (0.84, 75, 1) | lose |
| cycall / mean | 0.789 | 66 | 1.000 | 0.095 | 0.0577 | 8.9% (0.77, 74, 0) | ECE +0.055 → lose |
| cycall / geo | 0.789 | 75 | 1.000 | 0.072 | 0.0577 | 7.8% (0.77, 85, 0) | ECE +0.032 → lose |
| cyc4 / geo | 0.783 | 75 | 1.000 | 0.073 | 0.0583 | 7.8% (0.77, 85, 0) | ECE +0.033 → lose |
At α 0.05, LTT certifies no τ for any variant in either replicate (`ltt_alpha05_tau` is null throughout), so 5% is still not certified.

## Noise floor (single order, same prompt, same server)
Six single-order passes of the identical v2+cc prompt (T1, rep2–rep4 in `repro_nov4_cal180_v2cc_rep*.json`, plus the identity permutation inside each replicate-1 perm run) give: **ECE 0.040–0.056, bound 10.4%–10.9%, AURC 0.0673–0.0701** (`perm_avg_cal180_summary.json` `single_order_spread`).
- rep2, rep3 and rep4 are identical to each other: ECE 0.056, bound 10.9% @0.91 with 60 handled.
- T1, the first pass after server start, differs from them on 7/180 predictions. This is the same llama-server prompt-cache/slot numerics effect that QUANT_IDENTITY.md documented.
- T1 is therefore the *low* end of the ECE band, and the rule compares against it. rev/mean's ECE of 0.041 and 0.052 both lie inside the single-order band, so its pass/fail on ECE is noise. Its bound gain (8.9–9.1% vs 10.4–10.9%) is small but appears in both replicates.
- cycall/cyc4 are outside the noise band on all three axes in both replicates:
  - AURC is about 0.058 vs ≥0.067, so ranking is better.
  - The bound is 7.8% vs ≥10.4%, which is better.
  - ECE is 0.072–0.101 vs ≤0.056, which is worse.
- The ECE loss is systematic **under**-confidence. Mean confidence is 0.723 for cycall/geo and 0.697 for cycall/mean, against accuracy 0.789. Single order has mean confidence 0.761 against accuracy 0.794 (`variants.*.mean_conf`).

## test120, run ONCE for mode rev (report only; `perm_avg_test120_rev_ONCE_summary.json`)
Disclosure: on replicate 1, the run the brief's rule was written for, rev/mean lost by 0.002 ECE. I ran test120 anyway, because replicate 2 flipped the verdict inside the noise band. Before the run I wrote `perm_test120_precommit.txt`: rev only, once, report only, no shipping change whatever the result. cycall/cyc4 were not run on test120.
| test120 (N=120) | acc | handled @0.8 | acc on handled @0.8 | ECE | AURC | at the τ* chosen on cal180 |
|---|---|---|---|---|---|---|
| Nov 1 shipping headline rows (`eval/results/after_floor.test.json`) | 0.817 | 61 | 0.918 | 0.064 | 0.0853 | τ 0.90: 44 handled (37%), 3 errors (6.8%) |
| identity order, same run | 0.800 | 62 | 0.919 | 0.047 | 0.0867 | τ 0.90: 45 handled (38%), 3 errors (6.7%) |
| rev / mean (K=2) | 0.800 | 56 | 0.911 | **0.087** | 0.0951 | τ 0.80 (rep1): 56 (47%), 5 errors (8.9%); τ 0.82 (rep2): 51 (43%), 4 errors (7.8%) |
| rev / geo (K=2) | 0.792 | 59 | 0.915 | 0.073 | 0.0952 | τ 0.83/0.84: 55 (46%), 4 errors (7.3%) |
Source: the `baseline_T1` (Nov 1 rows here), `variants` and `test_at_cal_selected_tau` blocks. The test-side `ltt_tightest` in that JSON picks τ on test itself, so it is a diagnostic only, not a certificate.

How to read test120:
- K=2 averaging made test ECE worse: 0.087 vs 0.047 paired, and vs the 0.064 headline. It also made ranking worse (AURC 0.095 vs 0.087).
- At the cal-selected τ it hands more items to the phone (43–47% vs 37%) at a higher empirical error (7.8–8.9% vs 6.7%). That error is still at or under its cal180 bound (8.9–9.1%), but it is not a better operating point than single order at τ 0.90.
- One test item is 0.83 pts, so none of these differences is significant. They do not support a change.

## Cost
Each decision costs K forward passes, plus a one-time CF prior per (type, n, permutation).

Clean timings come from a single server with nothing else running. That clean re-run reproduced the replicate-1 per-permutation distributions bit-for-bit, so the accuracy numbers above are unaffected (`eval/experiments/latency_box.json`).

| variant | median / p90 ms per decision | prompt tokens per decision (median) |
|---|---|---|
| single order | 175 / 288 | 356 (78 uncached) |
| rev, K=2 | 350 / 545 | 712 (132 uncached) |
| cycall, K≈3.35 | 509 / 1225 | 1068 (204 uncached) |

Under the parallel load of the T2/T3 phase the same paths took a median of 177–334 / 490–761 / 859–953 ms (LATENCY_BOX.md).

Clean wall time for a full cal180 pass including CF priors: rev 82 s, cycall 137 s.

On a phone, K× means roughly 2–3× the decision latency. The p90 is worse, because 7-option toolChoice needs 7 rotations.

## Takeaways
- Pre-registered rule: cycall/cyc4 lose (ECE). rev/mean is a coin flip on cal180 and fails to confirm on test120. **Ship nothing.** The model and pipeline are frozen.
- Worth keeping for after the hackathon: **cyclic position-averaging ranks items better.** It reached AURC 0.058 vs 0.067–0.070 and an LTT bound of 7.8% at 47% handled vs 10.4% at 35%, reproduced in both cal replicates. The LTT certificate depends only on ranking plus τ, not on calibration. Adopting it would need:
  - a new rule decided in advance that does not penalize under-confidence;
  - its own single test120 report;
  - a 2–3× decision-latency budget on the phone.
- No scaling parameter was fit anywhere. Never describe this as temperature scaling.
