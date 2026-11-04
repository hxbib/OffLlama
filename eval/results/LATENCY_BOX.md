# Decision latency on the box (Nov 4 2026). Box CPU, not iPhone.

**Caveat: box CPU, not iPhone.** Hardware: AMD EPYC-Turin, 16 cores, x86 AVX2/AVX-512, 125 GB RAM. Server: llama.cpp 13ec8f6 `llama-server`, `-t 6 -c 4096`, 4 slots, unified KV, prompt cache on. Each request is an HTTP round trip on localhost through `/completion` with `n_predict 1, n_probs 40`. These numbers show *relative* cost (single order vs K-permutation averaging) and prompt size. They say nothing about phone TTFT; `[PHONE_*]` still needs an on-device measurement.

Source for everything below: `eval/experiments/latency_box.json`, written by `eval/experiments/summarize_latency.py`. Clean runs: `eval/experiments/latency_clean_t6_single_cal180.json` and `latency_clean_t6_perm_cal180.json`, using one server on the box with nothing else running.

## Clean (single server, no other load), cal180, N=180 decisions
| path | forward passes per decision | median ms | p90 ms | mean ms | prompt tokens per decision (median / p90) | uncached prompt tokens per decision (median / p90) |
|---|---|---|---|---|---|---|
| **single order v2+cc (shipping path)** | 1 | **175** | **288** | 218 | 356 / 649 | 78 / 116 |
| perm-avg rev (original + reversed) | 2 | 350 | 545 | 375 | 712 / 1298 | 132 / 212 |
| perm-avg cycall (all cyclic rotations) | 3.35 (mean) | 509 | 1225 | 649 | 1068 / 2896 | 204 / 438 |

Keys:
- `runs.clean_single.ms_per_decision`
- `runs.clean_rev/all_K.*`
- `runs.clean_cycall/all_K.*`
- Prompt tokens for one pass: `runs.clean_rev/order0.prompt_tokens` and `uncached_prompt_tokens`. These are server `tokens_evaluated` and `timings.prompt_n`.

Whole-pass wall time on cal180, including CF priors: rev 82 s, cycall 137 s (`wall_s_including_cf`).

## Notes
- **The prompt cache does most of the work.** The v2+cc prompt is about 356 tokens at the median: system prompt, few-shot turns, then the query. Only about 78 tokens are new per decision, because the system and few-shot prefix of the same type is reused from the KV cache. The single-token decode is negligible: server `predicted_ms` is about 0. So per-decision cost is almost all prompt prefill of the uncached suffix. The server-side `prompt_ms` median of 197 ms (rev order0) matches the HTTP median.
- **Cost of perm-avg.** It scales with K. On this box it costs 2.0× the median for K=2 and 2.9× for cycall, and the p90 grows more (4.3×) because 7-option toolChoice needs 7 rotations. Permuting the query's options does not invalidate the few-shot prefix cache, so the uncached tokens grow less than linearly: 78 → 132 → 204.
- **Under load (3 servers on 16 cores, the parallel T2/T3 phase).** Single-order medians were 330–334 ms (rep2–rep4) and K=2 took 490–761 ms (`runs.loaded_*`). The OOS stress runs, where two servers ran in parallel with one cal180 job, gave median / p90 of 450 / 717 ms for shipping and 511 / 802 ms for base over 2000 decisions each (`oos_runs.*`). The base model is slower in that setting because it ran with `-t 4`.
- **Determinism (`determinism_check`).** A *fresh* server given the same request sequence reproduced the T1 single-order rows and the perm replicate-1 distributions bit for bit (0 differing preds, max diff 0.0). Later passes on a warm server (rep2–rep4) differ on 7/180 predictions. So the known llama-server run-to-run noise depends on prompt-cache/KV-slot state and is deterministic given the request history. It is not random.
- Earlier reference: LEDGER §6.1 reports a median of 141 ms per decision on the Nov 1 box (llama.cpp ddf48f8). That is a different box state, so treat it as indicative only.
