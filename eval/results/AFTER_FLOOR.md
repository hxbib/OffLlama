# After distillation, floor run (Nov 1 2026, box CPU)

> November 4 correction: earlier “certified” claims below are historical. Model selection reused cal180; the nominal bound is not a post-selection guarantee. See [evaluation limits](../../docs/EVALUATION_CLAIMS.md). Saved predictions are unchanged.

Student: Llama 3.2 1B Instruct + LoRA r=16, 1 epoch over 892 Muse Glimmer teacher labels (bf16, micro-batch 2, grad accumulation to 8, gradient checkpointing; 112 steps, 502 s). Merged and quantized to Q4_K_M (808 MB GGUF), served by llama-server.
Eval: identical pipeline to the locked baseline (eval/experiments/run_prompt_variants.py, variant v2+cc, frozen gold_test N=120; calibration split N=180; training/reliability.py 10 bins; pg_train.conformal alpha 0.05 delta 0.1).

| Frozen test N=120, v2+cc | Before (untrained) | After (floor) |
|---|---|---|
| Accuracy | 0.74 | 0.82 |
| Handled on device at tau 0.8 | 0.15 | 0.51 |
| Accuracy on handled | 0.89 | 0.92 |
| ECE (10 bins) | 0.150 | 0.064 |
| Median latency per decision (box CPU) | 1050 ms | 141 ms |

Calibration split v2+cc: acc 0.78, handled 0.49 at tau 0.8, acc on handled 0.96.
Conformal (alpha 0.05, delta 0.1, N=180): still no certified tau (needs 135 handled with zero errors). Tightest: tau 0.90 handles 36% with 0 errors, error bound 10.2% (baseline tightest: tau 0.64, 29%, 3 errors, bound 22.4%).
Per type after (test): nudgeNow stays at 0.3 (47 of its teacher labels were dropped as low-confidence); confirmBeforeAct 1.0, sensitivity 1.0, memoryConflict 0.6 to 0.9, toolChoice 0.6 to 0.8.
lora_cpu.py's own HF bf16 zero-shot readout (not the headline): 0.558 to 0.825.
Latency note: the before figure came from an earlier server session; the after prompt cache/server flags may differ, so treat speed as indicative only until measured on phone.
Files: eval/experiments/after_floor_results.json, eval/results/after_floor.*.json, docs/img/reliability_after_floor_test120_v2cc.png, eval/results/conformal_after_floor.calib_split.json.
