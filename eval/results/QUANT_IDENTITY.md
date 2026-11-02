# Quant identity and quant ladder for the shipping ep1 model (2026-11-02, box CPU, $0)

## 1. Which file produced the headline numbers
**The shipping Q4_K_M GGUF (sha256 a5c60a88…82c2), served by llama.cpp `llama-server`. They did not come from bf16 PyTorch.**
- `training/local_teacher/run_after_eval.sh` merges base+ep1, exports f16 GGUF → `llama-quantize Q4_K_M`, starts `llama-server -m …/lora-llama1b-glimmer-merged/Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf --port 8088`, then runs `eval/experiments/run_prompt_variants.py` (v2+cc). That script gets the confidence from `/completion` `n_probs=40` label-letter logprobs.
- The GGUF mtime is 2026-11-01 12:14:17 ET. `eval/results/after_floor.test.json` was written at 12:15:19 ET. The sha256 of the file today matches the LFS pointer (a5c60a88…). AFTER_FLOOR.md also says "Merged and quantized to Q4_K_M (808 MB GGUF), served by llama-server".
- The only bf16 number is lora_cpu.py's own HF readout (0.558→0.825), which AFTER_FLOOR.md labels "not the headline".
- **Correction to the task brief:** this pipeline has **no temperature scaling**. ECE is computed on the raw letter-softmax confidence. I reproduced it exactly as it is (no scaling added).

## 2. Method
- For every file: `eval/quant/run_quant_eval.sh <label> <gguf>` runs the same commands as run_after_eval.sh: v2+cc on cal180 + frozen test120, graded against the gold field in eval/gold (Spark labels are never used); `training/reliability.py` with 10 bins; `pg_train.conformal` with alpha 0.05, delta 0.1. Server: llama.cpp ddf48f8, `-t 6 -c 4096`.
- Table: `eval/quant/summarize.py`. ECE uses reliability.py's `ece()` (10 equal-width bins); cal ECE is new. nudgeNow is the number correct out of the nudgeNow items.
- Other GGUFs: built from the existing merged ep1 safetensors (`lora-llama1b-glimmer-merged/model.safetensors`, fp16) with the same `convert_hf_to_gguf.py --outtype f16` + `llama-quantize` tools used for the shipping export. They are on the box at `/workspace/quant-ggufs/` and are not committed. I didn't re-run export_gguf.sh (which, note, passes trust_remote_code=True), so no new merge and no trust_remote_code.
- I did not build IQ2_M, because it needs an imatrix and `llama-imatrix` isn't built on the box. **Q2_K was used instead.**
- The "bf16" column is the **f16 GGUF** through the same llama.cpp pipeline (the bf16→f16 merge is the same one the shipping export used). I did this so the comparison isolates quantization.

## 3. Results
| file | MB | cal acc | cal handled@0.8 | cal acc-on-handled | cal ECE | cal bound | cal nudgeNow | test acc | test ECE | test handled@0.8 | test acc-on-handled | test nudgeNow |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Q4_K_M headline (Nov 1) | 808 | 0.783 | 0.49 | 0.955 | 0.042 | 10.2% @tau 0.9 (36% handled) | 7/15 | 0.817 | 0.064 | 0.51 | 0.918 | 3/10 |
| f16 | 2480 | 0.767 | 0.51 | 0.945 | 0.031 | 14.5% @tau 0.95 (24% handled) | 7/15 | 0.808 | 0.083 | 0.53 | 0.938 | 3/10 |
| q8 | 1321 | 0.756 | 0.51 | 0.946 | 0.069 | 13.9% @tau 0.94 (26% handled) | 7/15 | 0.808 | 0.092 | 0.53 | 0.953 | 3/10 |
| q4ship | 808 | 0.794 | 0.51 | 0.956 | 0.046 | 10.7% @tau 0.91 (34% handled) | 8/15 | 0.808 | 0.054 | 0.50 | 0.917 | 3/10 |
| q3km | 691 | 0.722 | 0.38 | 0.956 | 0.053 | 13.9% @tau 0.84 (34% handled) | 5/15 | 0.758 | 0.061 | 0.42 | 0.920 | 3/10 |
| q2k | 581 | 0.661 | 0.07 | 1.000 | 0.130 | 30.4% @tau 0.72 (11% handled) | 10/15 | 0.508 | 0.054 | 0.09 | 0.909 | 3/10 |

"Q4_K_M headline" = the original Nov 1 files. "q4ship" = the same file, same binary, re-run today. **The re-run is not bit-identical:** 2/120 test and 4/180 cal predictions changed, and the maximum confidence difference was 0.08. So run-to-run noise in llama-server (prompt-cache/batch numerics) is about ±0.01 acc, ±0.01 ECE and ±0.5 pt bound. Differences smaller than that are noise.

## 4. Selection (cal only; a smaller or larger quant must match or beat Q4_K_M on cal acc-on-handled, bound, handled%, and cal ECE)
- **Q8_0 (1.32 GB): not a win.** On cal it is worse on bound (13.9% vs 10.2/10.7%), on ECE (0.069 vs 0.042/0.046) and on accuracy. Even f16 doesn't beat Q4_K_M on cal (bound 14.5%). The Q4 advantage is probably noise or luck in the confidence tail, but nothing above Q4 is clearly better.
- **Q3_K_M (691 MB, −117 MB): does not match.** Cal acc drops to 0.72, handled to 38% and the bound rises to 13.9%. ECE (0.053) is also worse than 0.042/0.046.
- **Q2_K (581 MB, −227 MB): broken.** Cal acc is 0.66, handled is 7%, the bound is 30.4% and cal ECE is 0.130. Test acc is 0.51.
- **Recommendation: ship Q4_K_M as it is.**
