# Late WebGPU and Kernel Hub assessment

Checked 2026-11-04 during continuation run 54. Read-only evaluation; no model,
runtime, kernel, calibration, or provider substitution was made.

## Sources actually inspected

- [Xenova's post](https://x.com/xenovacom/status/2118024537812217962).
  X returned 403. Its text was recovered through the FxTwitter API mirror; this
  is an attributed author report, not independently reproduced performance.
  It describes LFM3-Omni on iPhone 18 Pro Max via custom WebGPU and React Native,
  and reports approximately 80 tok/s. Neither our iPhone 17 Pro nor our model was tested.
- [LiquidAI Space source](https://huggingface.co/spaces/LiquidAI/LFM3-Omni-2B-WebGPU/tree/main).
  The HF API listed README, index.html, and Lfm3OmniForConditionalGeneration.js.
  Read the actual index and model implementation. The index selects
  LiquidAI/LFM3-Omni-2B-GGUF, checks WebGPU availability, creates a model session,
  and supports streamed text/audio, cancellation and bounded tool rounds.
  The model file contains embedded WGSL kernels, GGUF handling, quantization
  dispatch, device feature checks, caching and timing code. This is substantial
  model-specific implementation, not a browser setting that accelerates our app.
- [Kernel Hub](https://huggingface.co/kernels?sort=trending), including
  [ggml-attn](https://huggingface.co/kernels/ggml-org/ggml-attn),
  [ggml-quantization](https://huggingface.co/kernels/ggml-org/ggml-quantization),
  [ggml-gated-delta-net](https://huggingface.co/kernels/ggml-org/ggml-gated-delta-net),
  and [MLX quantization](https://huggingface.co/kernels/kernels-community/mlx-quantization-metal-kernels).
  Checked both rendered cards and the dedicated /api/kernels tree endpoint.
  The listed GGML builds target macOS/aarch64/PyTorch. Attention and gated-delta
  cards have no published benchmark. Metal as a backend does not by itself
  establish an iOS build or compatibility with our pinned llama.cpp framework.
- [Transformers kernel documentation](https://huggingface.co/docs/transformers/main/kernel_doc/overview)
  describes optional platform-specific kernels and possible numerical differences.

## Decisions for this project

1. Keep the Meta model and current native runtime. LFM3 is a different model
   family, so adopting it would change the user's selected Meta-model project.
   The public browser demo also does not contain proof of the posted native
   React Native integration or device performance on our hardware.
2. Borrow behavioral ideas: streaming responsiveness, explicit interruption,
   bounded tool rounds, distinct first-text/first-audio/decode timing, and
   runtime capability checks. Our action path must still verify arguments,
   permissions, confirmation and observed results independently of generation.
3. Investigate GGML attention/quantization upstream changes as a separate native
   experiment when the Mac returns. Do not swap prebuilt Python/macOS binaries
   into the Swift app. Gated-delta kernels are not automatically applicable to
   the shipped Llama transformer architecture.
4. Before a kernel change can ship: build iOS arm64, compare identical GGUF and
   prompts against the current backend, verify finite logits/decision agreement
   and calibration in fresh and warm runs, then measure phone startup, latency,
   peak memory and sustained thermals. A desktop/browsing demo cannot substitute.

No model weights were downloaded, no paid job was started for this assessment,
and no speedup or new local multimodal capability is claimed.
