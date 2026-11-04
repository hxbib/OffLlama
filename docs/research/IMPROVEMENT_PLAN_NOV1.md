# Pocket Glimmer: Improvement Plan (written Sun Nov 1 2026, 7:30 PM ET)

Scope: a research plan only. No code was changed. The budget is about 30–40 h of mostly unattended RTX 3080 Ti (12 GB) time before the Nov 3 demo recording, with little of Habib's attention. The iPhone build and the video come first.
Rules that apply to every item: headline numbers come only from frozen test120, models are selected on cal180 only, only Meta models are used, there is no paid API use, and there is no trust_remote_code.

Evidence labels: **[E]** = published or measured evidence exists (URL given). **[S]** = speculative for this task and this data size.

## Key facts checked this session
- Muse Glimmer is a 30B **dense** model (52 layers, 202k vocab). Meta publishes a "K-Quant-17GB" build and a **DFlash drafter head** for speculative decoding. https://huggingface.co/meta-models/Muse-Glimmer-30B , https://research.meta.ai/blog/introducing-muse-glimmer-open-agentic-model
  - Implication: a Q4_K_M / Q5 teacher (about 17–21 GB) does **not** fit in 12 GB VRAM. It needs partial CPU offload (`-ngl` of about 30–35 of 52 layers) with 32 GB RAM, which is tight under WSL. Expect roughly 3–8 prompt-eval-dominated labels per second, not 50+. Labels need only one forward pass (prompt + 1 token logprobs), so throughput is still fine. This is an estimate, not a measurement: benchmark 20 items first.
- Muse Spark Open (816B/42B-active, Oct 15 2026) is open-weight but needs at least 700 GB of VRAM, so it is irrelevant locally. It is available on third-party APIs (Groq, Fireworks, etc.), but those cost money, so they are out unless approved. https://research.meta.ai/blog/muse-spark-open
- I could not verify any new Meta release that changes System 1 (for example a newer small Llama) in the Oct 26–Nov 4 window. Treat this as "none found", not "none exists".

## Ranked ideas

| # | Idea | Expected gain (evidence) | GPU-h | Habib time | Demo risk | By Nov 3? |
|---|------|--------------------------|-------|------------|-----------|-----------|
| 1 | **nudge_v2 relabel (300) + targeted "later" coverage**, merged into train only | Fixes a data hole: 0 "later" examples means the class cannot be predicted. This is the largest single expected gain (nudgeNow 3/10 should rise substantially). [E, basic: a model cannot learn an absent class] | 1–3 (labeling) | 15 min (spot-check 20 labels) | none (offline) | Yes, tonight |
| 2 | **Post-hoc temperature scaling (single T, fit on cal180)**, optionally per-head (intent vs nudge) | ECE drops reliably with no change to accuracy. Guo et al. found TS the best simple method. https://arxiv.org/abs/1706.04599 With ECE already at 0.064 the gain is small, but it is free. Vector/matrix scaling overfits on 180 rows. [E] | ~0 (CPU) | 10 min | none: one scalar applied to logits in the app | Yes |
| 3 | **Grammar-constrained single-token decision + prompt/KV caching + shorter prompt on the phone** | Read the option letter from one forward pass over the logits (no generation). llama.cpp GBNF grammars and prefix/state save-restore (`llama_state_*`) reuse the fixed system prompt, so latency becomes about prefill of the user-specific suffix only. https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md , https://github.com/ggml-org/llama.cpp/tree/master/examples/save-load-state [E: mechanism; speedup size is S until measured] | 0 | 1–2 h in app (only if not already done) | low–medium (touches the app; do it before recording or not at all) | Yes, if small |
| 4 | **Teacher-label refresh at a higher-precision Glimmer quant + self-consistency** (K prompt permutations / option-order shuffles, averaged probs) | Option-order permutation averaging reduces position bias in multiple-choice LLM scoring. https://arxiv.org/abs/2309.03882 (Zheng et al., "Large Language Models Are Not Robust Multiple Choice Selectors", PriDe; see also Pezeshkpour & Hruschka, arXiv:2308.11483; citation corrected Nov 4). Measured Nov 4: it tightens the cal180 bound (10.4%→7.8%) but makes the student under-confident (ECE 0.040→0.084), so it did not ship under the pre-registered rule, see eval/results/PERM_AVG.md. IQ2_M→Q4 quantization error is real (ppl/KLD tables: https://github.com/ggml-org/llama.cpp/discussions/5962), but the gain in *student* accuracy is [S]. The labels were already ~good (0.82). | 8–15 for 892 + 300 items × 3 permutations with offload | 30 min setup | none (offline) | Yes, if started tonight |
| 5 | **Retrain LoRA once on refreshed + nudge_v2 labels (1 epoch, r16 or r32, KL soft-label loss)** | Soft-label KD: https://arxiv.org/abs/1503.02531 . Higher rank: LoRA ≈ full FT on small data, and gains from rank are minor at this scale. https://arxiv.org/abs/2405.09673 ("LoRA Learns Less and Forgets Less"). Expect +0–4 pts [S]. Keep 1 epoch (2 epochs already overfit). | 1–2 per run on the 3080 Ti (1B, bf16) | 20 min | none until swapped into the app | Yes; swap only if cal180 improves |
| 6 | **Mondrian (class-conditional) conformal / LTT per decision head** | Gives per-class guarantees, so "later"/"nudge" stop being drowned by majority classes. https://arxiv.org/abs/2110.01052 (LTT), Vovk Mondrian CP https://arxiv.org/abs/2209.15145 (class-conditional; see also https://arxiv.org/abs/2306.09335). **Honest caveat:** with 180 cal rows split by class, each stratum has tens of rows, so bounds get *wider*, not tighter. It is useful mainly as a correctness/fairness story, not as a coverage gain. [E mechanism, S benefit] | 0 | 30 min | none (offline numbers) | Yes |
| 7 | **Hard-example mining near τ** (generate scenarios where student conf is 0.6–0.9, label with Glimmer, add to train) | Classic active learning / uncertainty sampling. It sharpens the escalation boundary [S at this data size]. Must stay disjoint from test120: dedupe by embedding/string. | 3–6 | 30 min | none | Possible by Nov 3 only if steps 1–5 finish early |
| 8 | **Quant choice for the phone: Q4_0 (ARM repack) vs Q4_K_M vs IQ4_NL** | On Apple, llama.cpp runs on **Metal**, where the CPU ARM repack (Q4_0_4_4/8_8 → online repack) does not apply. Speed differences on Metal for a 1B are small; Q4_0 is often slightly faster, and K-quants are slightly more accurate. https://github.com/ggml-org/llama.cpp/pull/9921 (online repacking, CPU only). [E] Gain: maybe 5–15% tok/s, irrelevant for single-token decisions. | 0 | 30 min to bench | low | Optional; skip unless measured latency is a problem |
| 9 | **Conformal sample-size fix: grow the calibration set** with new Glimmer-labeled scenarios (cal only) | 5% certification needs ~135 zero-error rows at τ; more cal rows tighten the bound directly (binomial/Hoeffding-Bentkus in LTT). [E] Caveat: the new cal items must be from the same distribution as test, or the guarantee is weakened. | shares #4/#7 labeling | 15 min | none | Yes, if labels are generated in the same batch |

## Mondrian / per-bucket conformal: sample-size check (added per guardrail)
Back-solving the current result: 0 errors in about 65 handled rows (36% of 180) gives a 10.2% bound. That implies an effective δ of about 9e-4 after grid correction, because (1−0.102)^65 ≈ 9e-4. The same δ gives n≈136 for 5%, which matches the ~135 already quoted. For a zero-error bucket of n handled rows, the best achievable bound is 1 − δ^(1/n):

| handled rows in bucket | best bound (0 errors) |
|---|---|
| 10 | ~50% (vacuous) |
| 20 | ~30% (vacuous for a 10% target) |
| 30 | ~21% |
| 45 | ~15% |
| 65 | ~10% |
| 135 | ~5% |

With 180 cal items total:
- **Splitting by intent/action category** (several classes) gives tens of rows per class, and fewer handled. Every bucket comes out vacuous or above 20%. **Do not do this.**
- **Splitting by decision type** (intent head vs nudgeNow head) is borderline. If nudge items are a minority of cal180, the nudge bucket will be vacuous.
- **Splitting nudgeNow by class** (skip/nudge/later), with "later" currently ~0 in train and probably a handful in cal: vacuous. Choosing per-bucket τ on so few rows also overfits the cal split.
- **What to do instead:** keep one *global* LTT guarantee. Report per-class empirical coverage/error on cal as a diagnostic only, with no per-class guarantee. Alternatively, use a simple policy rule: always escalate nudgeNow until its bucket has at least ~65 calibration rows. Mondrian becomes worthwhile only after ~65–135 handled cal rows per bucket, which is a post-hackathon data-collection item. Do not take cal rows from test120.

## Ideas to skip (and why)
- **Llama 3.2 3B as System 1: lowest priority, skip for this hackathon.** It would be recommended only if all three hold: (a) it comfortably fits the phone's working set alongside the app (Q4_K_M ≈ 2 GB weights + KV), (b) it clearly beats the 1B on cal180 (beyond the noise of ±1–2 items), and (c) the 1B remains the shipping fallback regardless. (b) cannot be established without a full train/quant/cal cycle, which displaces steps 2–4. So it stays here. A Q4_K_M is about 2 GB, so it fits on an iPhone 17 Pro, but it means ~3× the training time, a new app binary, re-calibration, and re-testing two days before recording. The accuracy gain on a 1-token classification task is [S]. Demo risk is high. Post-hackathon only.
- **Full fine-tune of 1B.** Biderman et al. show the gains over LoRA show up mostly at large data sizes, and 892 rows overfit already. https://arxiv.org/abs/2405.09673
- **Speculative decoding on the phone.** Decisions are a single token, so there is nothing to speculate. On System 2, generation is server-side at Meta, so it is not controllable. (Glimmer's DFlash drafter only helps the *teacher* if it generates long outputs, which labeling does not.)
- **Vector/matrix scaling.** Too many parameters for 180 cal rows. TS is the safe choice. https://arxiv.org/abs/1706.04599
- **2+ epochs or LR sweeps larger than 3 configs.** This was already shown to hurt cal, and wide sweeps on cal180 invite selection overfitting.
- **Muse Spark Open via paid third-party APIs as a better teacher.** It costs money, and the credits are reserved.
- **Changing the System 2 model or route.** To make System 2 *faster*, the only free levers are a shorter prompt, structured output limited to the decision fields, `max_tokens` small, and streaming the first token to the UI. Do this in the app only if trivial.

## Recommended sequence (tonight → Nov 3)
1. **Tonight (Sun):** run nudge_v2 (already queued) with option-order permutations ×3 if it is cheap. In parallel on CPU, fit temperature scaling on cal180 for the current shipping model. Then re-run LTT and report the T-scaled ECE on test120 once. *(Unattended ~3 h.)*
2. **Overnight Sun→Mon:** bench Glimmer Q4_K_M with partial offload on 20 items. If it runs at least ~2 items/s, relabel the 892 train items plus ~300–500 *new* scenarios (including near-τ hard examples and extra cal rows, deduped against test120) with 3 permutations, keeping full soft distributions. *(Unattended 8–15 h.)*
3. **Mon:** train at most 3 LoRA runs (r16 vs r32, old vs refreshed labels, all 1 epoch, +nudge_v2). Select on cal180 only. Evaluate the winner once on test120. *(Unattended 3–6 h; Habib ~30 min.)*
4. **Mon night:** quantize the winner to Q4_K_M (same pipeline as the shipping model), refit T, re-run LTT and Mondrian-by-nudge-class, and freeze. Swap it into the app **only** if cal180 wins and a phone smoke test passes. Otherwise ship the current 808 MB model plus T-scaling. *(1 h.)*
5. **In the app, only if not already done:** single-token logit readout with a cached system-prompt prefix. Measure latency before and after for the video.

Deadline rule: if step 3 isn't done by **Tue Nov 3 noon ET**, record the demo with the current model, and report new numbers in the writeup only if they are finished and honest.

## Honesty notes
- The expected magnitude of every gain beyond fixing the "later" class and T-scaling is speculative at n=892 and test n=120. On 120 items, one item is 0.83 pts, so the 95% CI on 0.82 is about ±7 pts. Do not claim small improvements as real.
- The Glimmer offload throughput above is an estimate. Measure it before committing the night to it.
