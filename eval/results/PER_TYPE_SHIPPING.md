# Per-decision-type results, shipping 1-epoch adapter (report only)

Model: out/lora-llama1b-glimmer (1 epoch, Q4_K_M), same run as eval/results/AFTER_FLOOR.md. Prompt v2+cc. Frozen test split eval/gold/gold_test.jsonl, N=120. Source: existing per-item file eval/results/after_floor.test.json (no rerun). Handled = conf ≥ 0.8.

Report only: nothing (prompt, threshold, checkpoint) was selected on these numbers. Small n per type: one item is 10 points at n=10.

| Type | n | Accuracy | Handled at τ0.8 | Accuracy on handled |
|---|---|---|---|---|
| answerability | 10 | 0.90 (9/10) | 0.50 (5/10) | 1.00 (5/5) |
| confirmBeforeAct | 10 | 1.00 (10/10) | 0.60 (6/10) | 1.00 (6/6) |
| contactPick | 10 | 0.90 (9/10) | 0.90 (9/10) | 0.89 (8/9) |
| eventPick | 10 | 0.90 (9/10) | 0.90 (9/10) | 0.89 (8/9) |
| memoryConflict | 10 | 0.90 (9/10) | 0.10 (1/10) | 1.00 (1/1) |
| notificationTriage | 10 | 0.80 (8/10) | 0.40 (4/10) | 0.75 (3/4) |
| nudgeNow | 10 | 0.30 (3/10) | 0.00 (0/10) | n/a (0 handled) |
| rememberOrNot | 10 | 0.70 (7/10) | 0.10 (1/10) | 1.00 (1/1) |
| route | 10 | 0.80 (8/10) | 0.70 (7/10) | 1.00 (7/7) |
| sensitivity | 10 | 1.00 (10/10) | 0.70 (7/10) | 1.00 (7/7) |
| timing | 10 | 0.80 (8/10) | 0.50 (5/10) | 0.80 (4/5) |
| toolChoice | 10 | 0.80 (8/10) | 0.70 (7/10) | 0.86 (6/7) |
| **All** | 120 | 0.82 (98/120) | 0.51 (61/120) | 0.92 (56/61) |
