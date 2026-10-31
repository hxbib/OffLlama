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
