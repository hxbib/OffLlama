# models/ (Git LFS)

`SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf` is the only on-device model in OffLlama. It is Llama 3.2 1B Instruct with the 1-epoch LoRA merged, quantized to Q4_K_M, 807,694,080 bytes, sha256 `a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2`. The installed build `4376810` bundles this exact file.

Rejected candidates are documented in `eval/results/` (for example `AFTER_FLOOR_EP2.md`, `AFTER_FLOOR_NV2.md`, `SPARK_TEACHER.md`, `ROUND2.md`) but their weights are not distributed. The quant ladder f16 / Q8_0 / Q3_K_M / Q2_K of ep1 all lose to Q4_K_M on the nominal selection-set calculation (`eval/results/QUANT_IDENTITY.md`). Model selection reused that set, so this is not a certified error guarantee; see [evaluation limits](../docs/EVALUATION_CLAIMS.md).

Fetch with `git lfs install && git lfs pull`, or download the same file from the [OffLlama shipping model release](https://github.com/hxbib/OffLlama/releases/tag/artifacts-2026-11-01) and check it against its `SHA256SUMS`.
