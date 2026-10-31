# eval/

- `gold_decisions.jsonl` — 36 hand-labeled Reflex decisions covering all 12 decision types (written for this project).
- `score_decisions.py` — scores any student/teacher: accuracy, ECE, coverage at tau, accuracy on covered, latency.
- `run_system2.py` + `system2_items.py` — System 2 answer quality (15 Q&A items adapted from the Gate-1 eval written this week).

Baseline (untrained Llama-3.2-1B-Instruct Q4_K_M, tau 0.8, 2026-10-31, Linux CPU shared with another job): see `results/`.
