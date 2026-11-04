# models/ (Git LFS)
- `SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf`: the SHIPPING System 1 model (1-epoch floor LoRA merged, Q4_K_M, 808 MB). sha256 a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2
- `lora-ep1-SHIPPING/`: the 1-epoch LoRA adapter behind the shipping GGUF. adapter sha256 24731befe64645b379fd2378ba1801f1f4d07967fa687aa0c6c1925efd918e59
- `lora-ep2-REJECTED/`: 2-epoch adapter, measured and rejected (eval/results/AFTER_FLOOR_EP2.md). Kept for reference only.
Also measured and rejected on cal180 (not stored here): nv2 (nudge_v2 relabel retrain, eval/results/AFTER_FLOOR_NV2.md) and the Muse Spark Open teacher retrain (eval/results/SPARK_TEACHER.md). The quant ladder f16 / Q8_0 / Q3_K_M / Q2_K of ep1 all lose to Q4_K_M on the certified bound (eval/results/QUANT_IDENTITY.md).
Fetch: `git lfs install && git lfs pull`. Same files are also in release `artifacts-2026-11-01`.
