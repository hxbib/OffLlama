# CLINC out-of-scope stress test: abstention (Nov 4 2026, box CPU x86 AVX2/AVX-512, not iPhone, $0)

**Headline (full set, N = 2000: 1000 route + 1000 answerability).** The false-confident rate is the share of OOS items where the model picks a "handle on device" option with confidence ≥ τ.

| model | τ 0.80 | τ 0.90 |
|---|---|---|
| shipping ep1 Q4_K_M | **7.3% (145/2000)** | **0.25% (5/2000)** |
| untrained base Llama 3.2 1B Instruct Q4_K_M | 0.0% (0/2000) | 0.0% (0/2000) |

The base model's 0% comes from blanket low confidence, not from recognizing OOS inputs (see Reading).

**This is not a gold-distribution eval.** The items have no gold labels, so the report gives no accuracy and makes no conformal claim. It measures how often the model is *confidently* willing to keep, on device, an utterance from CLINC150's out-of-scope bucket.

## Setup
- **Items:** `training/data_scale/out/clinc_oos_test_stress.jsonl`, all 2000 rows. These are 1000 CLINC150 `oos` test utterances, each rendered twice:
  - route: `Network: online\nUser: <utterance>`
  - answerability: `User: <utterance>`
  
  None of them appear in gold or in the training data. Both models ran on the full set. A first pass on the first 300 + 300 items is kept as a replicate.
- **Readout:** single-order **v2+cc**, byte-identical to `run_prompt_variants.py`, run through `eval/experiments/run_oos_stress.py`. That script imports `render`, `letter_logprobs` and `cf_logp` from the original. τ ∈ {0.80, 0.90}.
- **Models (llama.cpp 13ec8f6, llama-server, `-c 4096`):**
  - **shipping** = `models/SHIPPING-ep1-…Q4_K_M.gguf`, sha256 a5c60a88…82c2, port 8089, `-t 6`.
  - **base** = untrained Llama 3.2 1B Instruct Q4_K_M, downloaded from `bartowski/Llama-3.2-1B-Instruct-GGUF` into `/tmp/gencode/models/` (not committed), sha256 `6f85a640a97cf2bf5b8e764087b1e83da0fdb51d7c9fab7d0fece9385611df83`, port 8090, `-t 4`. Download took about 10 s.
- **False-confident** = conf ≥ τ and one of these picks:
  - route: `answer_local` or `tool`;
  - answerability: `yes` ("a small on-device model can answer this without the internet", i.e. answer from memory).
  
  Desired behavior on OOS: escalate_cloud, clarify or "no", or a low-confidence pick that the cascade escalates anyway.
- **Sources:**
  - Full-set rows and summaries: `eval/experiments/oos_ship_full2000.json`, `eval/experiments/oos_base_full2000.json`, each with a `summary` block and per-row `p`.
  - Replicate: `oos_ship_n300.json`, `oos_base_n300.json`.
  - Side-by-side summary: `eval/experiments/oos_stress_summary.json`, produced by `eval/experiments/summarize_oos.py`. It holds mean confidences, the replicate diff, and the listed τ 0.90 items.

## False-confident rate by type (full 2000)
| model | τ | route (N=1000) | answerability (N=1000) | combined (N=2000) |
|---|---|---|---|---|
| shipping ep1 | 0.80 | 8.3% (83) | 6.2% (62) | **7.3% (145)** |
| shipping ep1 | 0.90 | 0.3% (3) | 0.2% (2) | **0.25% (5)** |
| base untrained 1B | 0.80 | 0.0% (0) | 0.0% (0) | **0.0% (0)** |
| base untrained 1B | 0.90 | 0.0% (0) | 0.0% (0) | **0.0% (0)** |

Source: `summary.{route,answerability,all}.tau*.false_confident_{n,rate}` in each full2000 JSON.

The first-300 replicate (N=600) gives: shipping 9.2% (55/600) at τ 0.80 and 0.8% (5/600) at τ 0.90; base 0/600 at both τ (`*_n300.json` `summary.all`). Replaying the same 600 items inside the full run changed 12 shipping and 22 base argmax predictions (`n300_vs_full_same_items_pred_changed`). That is the llama-server run-to-run noise documented in REPRO_NOV4.md and PERM_AVG.md.

## Distributions (full 2000; argmax before the τ gate)
| | shipping | base |
|---|---|---|
| route argmax, escalate_cloud / tool / clarify / answer_local | 473 / 452 / 53 / 22 | 399 / 385 / 102 / 114 |
| route conf ≥ 0.8: share, then picks | 27.7%: escalate 188, tool 83, clarify 6 | 2.0%: escalate 19, clarify 1 |
| route conf ≥ 0.9: share, then picks | 10.3%: escalate 96, clarify 4, tool 3 | 0.3%: escalate 3 |
| answerability argmax, "yes, from memory" / "no, can't" | 774 / 226 | 554 / 446 |
| answerability conf ≥ 0.8: share, then picks | 6.9%: yes 62, no 7 | 0% |
| answerability conf ≥ 0.9: share, then picks | 0.3%: yes 2, no 1 | 0% |
| mean top-option confidence, route / answerability | 0.664 / 0.655 | 0.457 / 0.538 |

Source: `summary.<type>.pred_dist`, `summary.<type>.tau*.confident_share`, `confident_pred_dist`; mean confidence from `oos_stress_summary.json` `*.mean_conf`.

## Reading
1. **The base model's 0% does not mean it knows what it doesn't know.**
   - Its mean top-option confidence on OOS is 0.46 (route) and 0.54 (answerability).
   - On in-distribution gold it handles only 15% of test120 at τ 0.8 (LEDGER §6.1).
   - So it abstains on almost everything. Its argmax is also worse in the unsafe direction: it picks answer_local on 11.4% of OOS route items, against 2.2% for shipping.
2. **Distillation raised confidence on OOS inputs too.**
   - At τ 0.80 the shipping model keeps 7.3% of OOS items on device with a "handle locally" pick.
   - At **τ 0.90**, the threshold with the cal180 LTT bound, this falls to **0.25% (5/2000)**.
   - This is the measured price of the higher in-distribution coverage, and an argument for the τ 0.90 operating point over 0.80.
3. **When the shipping model is confident on an OOS route item, it mostly escalates.** At τ 0.90, 96 of 103 confident route picks are escalate_cloud, 4 are clarify and 3 are tool. At τ 0.80, 188 of 277 confident route picks are escalate_cloud.
4. **The shipping answerability argmax leans "yes" (77% vs 55% for base), but at low confidence.** Only 6.9% of these items clear 0.8, and the cascade escalates the rest whatever the argmax.
5. **"False-confident" is an upper bound on real errors.** CLINC "oos" means outside CLINC's 150 intents, not outside Pocket Glimmer's scope. Several confident "tool" or "yes" picks are reasonable under our labels (route `tool` = "Do a phone action: … look up a contact, recall a saved memory").
   
   The 5 shipping items at τ 0.90, verbatim from `oos_stress_summary.json` → `ship.full_false_confident_items_tau0.9`. The verdicts are the author's reading, not gold:
   - route-691 "Call the grocery store and get their operational hours" → tool 0.901. Starting a call is a phone action, but the hours need the internet. Mixed.
   - route-728 "Can you look at when the next iphone is due out" → tool 0.923. Needs web or news. **Wrong.**
   - route-765 "Organize my photos by date please" → tool 0.910. A phone action, though not one of our tools. Defensible.
   - answerability-222 "Remind me of the address for my workplace please" → yes 0.926. An on-device memory lookup. **Defensible.**
   - answerability-416 "Tell me what pokemon is" → yes 0.901. A short general-knowledge answer that a 1B model plausibly knows. Defensible.
   
   The full τ 0.80 list is in the JSON rows (`conf ≥ 0.8` and `pred` ∈ {tool, answer_local, yes}). In the first-300 pass these were mostly bank/phone-plan account actions, store hours, "what's playing" and car-status questions, which need the internet or account access and are wrong. Contact, voicemail and memory recalls, which are defensible, made up the rest.
6. **No guarantee applies here.** No conformal or selective-risk guarantee covers OOS inputs: the LTT bound assumes exchangeability with cal180, and these items violate it by construction.
