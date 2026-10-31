# DRY RUN — local stand-in teacher (not real distillation data)

Run on 2026-10-31 (Linux box, CPU only, shared with another benchmark job). Purpose: prove the pipeline runs end to end.
No paid API was called.

- Teachers: **Llama-3.2-1B-Instruct-Q4_K_M via local llama-server**, twice: canonical option order and shuffled option order
  (mapped back). Real runs use Muse Spark Open (Baseten) + Muse Glimmer 30B (Modal).
- 240 seeded scenarios (seed 42), all 12 decision types.
- Merge (disagreement -> escalate): 166/240 escalated (teachers disagreed or agreed weakly < 0.6), 74 agreed,
  46 of those matched the generator's intended answer. A 1B model is position-biased, which the shuffle exposes:
  exactly why it is the student, not the teacher.
- Calibration on 48 held-out rows (student = same 1B): global T = 2.45, argmax accuracy vs merged target 0.44.
  Per-type n is 2–7, far too small; `calibration.json` here is for format checking only. Real target: ≥2k held-out rows.
- Wall time: 3 min 42 s for 480 teacher calls (≈460 ms/call through HTTP on a contended CPU).
