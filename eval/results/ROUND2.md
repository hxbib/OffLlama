# Round 2 retrain (Nov 4 2026): Muse Spark Open label expansion + LoRA sweep. PARTIAL, being updated

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
