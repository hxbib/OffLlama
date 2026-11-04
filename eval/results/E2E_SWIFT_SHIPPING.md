# Swift-core end-to-end suite on the shipping GGUF (`pg-cli e2e`, 18 decisions)

Run: 2026-11-04 ~06:05 ET, by the orchestrating agent. Box CPU (x86 AVX2, 16 vCPU), **not an iPhone**.

This is the Swift production code path (PocketCore `Reflex.decide` → `DecisionPrompt.llama3` fewShot → letter
logits → raw confidence vs τ), not the Python eval pipeline. It is an independent check that the **Swift app
code** reads the same shipping model the way the headline eval does. The 18 cases are hard-coded in
`core/Sources/pg-cli/main.swift` (one or two per decision type); they are *not* the gold set and are not a
headline number.

- Model: `models/SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf` (sha256 verified `a5c60a88…82c2`).
- Server: llama.cpp master (built 2026-11-04 from https://github.com/ggml-org/llama.cpp), `llama-server -c 4096 -t 6`.
- Client: `swift run pg-cli e2e --url http://127.0.0.1:8089 --tau 0.9` inside `swift:6.1-noble` (Linux), prior correction off.
- Raw output: `/tmp/gencode/e2e_tau09.txt`, `/tmp/gencode/e2e_tau08.txt` (box-local; summary reproduced below).

| Run | argmax accuracy | handled on device (conf ≥ τ) | correct on handled | median ms (HTTP round trip, box CPU) |
|---|---|---|---|---|
| Untrained Llama 3.2 1B Q4_K_M, τ=0.8 (README "Earlier measurements", 2026-10-31, 2 threads) | 9/18 | 3/18 | 3/3 | 501 |
| **Shipping Llama-Reflex-1B Q4_K_M, τ=0.9** | **14/18** | **10/18** | **10/10** | 207 |
| Shipping Llama-Reflex-1B Q4_K_M, τ=0.8 | 14/18 | 10/18 | 10/10 | 209 |

Per-case (τ=0.9): the four argmax misses are `route` clarify→answer_local (conf 0.41), `rememberOrNot` no→remember_fact
(0.51), `timing` recurring→at_time (0.78) and `nudgeNow` nudge→skip (0.53). **All four misses sit below τ and are
escalated**, which is the behaviour the design asks for: zero wrong decisions were kept on device in this suite.
The first call of each type pays prompt-eval (~0.8–1.4 s on this CPU); subsequent calls are ~170–450 ms.

Caveats: N=18 is a smoke test. Latency is a Linux CPU HTTP round trip, not Metal on an A19 Pro. The headline
numbers remain the frozen test120 / cal180 figures in `LEDGER.md` section 6.

## Addendum: with the bundled `calibration.json` (contextual-calibration priors, τ=0.90)

The headline eval is `v2+cc`: few-shot prompt **plus** contextual-calibration priors (Zhao et al. 2021). The Swift
`Reflex` applies those priors only if a `CalibrationProfile` with `prior` entries is loaded; the app bundle had none,
so the first run above (and the phone, until now) was fewShot *without* cc. I generated the priors from the shipping
GGUF with `pg-cli priors` (24 sets) and committed them as `app/PocketGlimmer/Resources/Models/calibration.json` with
`defaultTau: 0.90`. Same 18 cases, same server, `--calibration` pointed at that file
(`eval/results/e2e_swift_shipping_tau090_cc.txt` vs `e2e_swift_shipping_tau090_nocc.txt`):

| Swift e2e (18), shipping GGUF | argmax | handled @τ0.9 | correct on handled |
|---|---|---|---|
| fewShot, no priors | 14/18 | 10/18 | 10/10 |
| **fewShot + cc priors (what the app now bundles)** | **16/18** | 10/18 | **10/10** |

With priors, `rememberOrNot` "no" (0.49, escalated) and `nudgeNow` "nudge" (0.68, escalated) become correct at argmax;
the two remaining misses (`route` clarify 0.40, `timing` recurring 0.66) stay below τ and escalate. The median ms in
the cc run (1067) is higher only because a concurrent eval job was sharing the box CPU during that run; it is not a
property of the priors (the correction is a vector subtraction).
