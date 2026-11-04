# eval/

- `gold_decisions.jsonl` — 36 hand-labeled Reflex decisions covering all 12 decision types (written for this project).
- `score_decisions.py` — scores any student/teacher: accuracy, ECE, coverage at tau, accuracy on covered, latency.
- `run_system2.py` + `system2_items.py` — System 2 answer quality (15 Q&A items adapted from the Gate-1 eval written this week).

Baseline (untrained Llama-3.2-1B-Instruct Q4_K_M, tau 0.8, 2026-10-31, Linux CPU shared with another job): see `results/`.

## Gold set v3 (300 decisions, hand-labeled)
`gold/gold_all.jsonl`: 25 per decision type × 12 types. Labeling rules are in `gold/LABELING_RULES.md`; no model labeled anything.
It includes the original 36 (`gold_decisions.jsonl`) plus 264 new items, and none overlap the few-shot exemplars.
Stratified seeded split (seed 20261031): `gold/gold_calibration.jsonl` has 180 rows (15/type) for tau / conformal risk control;
`gold/gold_test.jsonl` has 120 rows (10/type) for the held-out distillation chart. Never tune on the test split.

## Prompt-only debiasing (no training), frozen test split

Untrained Llama-3.2-1B-Instruct Q4_K_M, CPU, 2 threads, `gold/gold_test.jsonl` (120 hand-labeled items, 10 per type, seed 20261031). Priors and τ come from the calibration split or content-free inputs only, never from test.

| Variant | acc | coverage @ τ=0.8 | acc @ coverage | mean ms |
|---|---|---|---|---|
| v0 (original prompt) | 0.51 | 0.15 | 0.72 | 657 |
| v2 labels + few-shot + contextual calibration | **0.74** | 0.15 | **0.89** | 1050 |

v0 sent every route prediction to "clarify" on earlier sets; v2+cc removes that bias. Raw numbers: `experiments/test120_results.json`, log from `run_prompt_variants.py`.

## 2026-11-04: box re-checks, permutation averaging, OOS stress, latency (box CPU x86, not iPhone, $0, no training)
New scripts:
- `experiments/run_perm_avg.py`: option-order permutation averaging over v2+cc. It reuses `run_prompt_variants.py`, which is unchanged.
- `experiments/run_oos_stress.py`: CLINC out-of-scope abstention with single-order v2+cc.
- Summarizers: `experiments/summarize_repro.py`, `summarize_perm.py`, `summarize_oos.py`, `summarize_latency.py`.

New reports in `results/`, all run on llama.cpp 13ec8f6 with the shipping Q4_K_M (sha256 a5c60a88…82c2). Every number cites a JSON in `experiments/`.
- `REPRO_NOV4.md`: cal180 reproduces within llama-server noise. acc 0.794, handled@0.8 0.48, acc-on-handled 0.966, ECE 0.040, LTT bound 10.4% at τ 0.90 (63/180, 0 errors). The Nov 1 run gave 10.2% (64/180), and 5 of the 180 predictions changed.
- `PERM_AVG.md`: does not ship. Full cyclic averaging tightens the bound to 7.8% at 47% handled but under-confidence pushes ECE up by 0.03–0.06. K=2 is borderline on cal180 and did not confirm on its single test120 run (pre-commit in `experiments/perm_test120_precommit.txt`).
- `OOS_STRESS.md`: 2000 CLINC OOS items. Shipping false-confident rate is 7.3% at τ 0.80 and 0.25% at τ 0.90. Base is 0%, but only because it is almost never confident.
- `LATENCY_BOX.md`: per-decision HTTP latency and prompt tokens.

The test120 split was touched once in total, for perm-avg K=2, report only. All selection used cal180.
