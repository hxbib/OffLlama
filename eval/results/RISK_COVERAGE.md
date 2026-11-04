# Risk–coverage (selective prediction) on the frozen test split, baseline vs shipping

Produced 2026-11-04 ~06:15 ET by `eval/risk_coverage.py` from the saved per-item predictions of the headline
pipeline (v2+cc, frozen test N=120). No model was re-run; this is a re-analysis of existing rows.
Source JSON: `eval/results/risk_coverage_test120.json`. Figure: `docs/img/risk_coverage_test120.png`.

The curve is the standard selective-classification view (Geifman & El-Yaniv 2017): sort decisions by confidence,
keep the top share ("coverage" = handled on device), and plot the error rate among the kept decisions
("selective risk"). AURC = area under that curve (lower is better; it summarises the whole threshold range,
so it is less sensitive to the choice of τ than any single operating point).

| Model (frozen test120, v2+cc) | Accuracy | **AURC** | cov / risk @ τ=0.8 | cov / risk @ τ=0.9 | cov / risk @ τ=0.95 |
|---|---|---|---|---|---|
| Untrained Llama 3.2 1B Q4_K_M + prompt debiasing (`eval/experiments/test120_results.json` test/v2+cc) | 0.742 | 0.148 | 0.15 / 0.111 | 0.07 / 0.000 | 0.04 / 0.000 |
| **Llama-Reflex-1B ep1 Q4_K_M, shipping** (`eval/results/after_floor.test.json`) | **0.817** | **0.085** | **0.51 / 0.082** | **0.37 / 0.068** | 0.20 / 0.042 |

Reading it: the shipping curve sits below the baseline at essentially every coverage level, so the gain is not an
artefact of one threshold. At the certified operating point τ=0.90 (chosen on cal180, LEDGER 6.2) the shipping model
keeps 37% of the frozen-test decisions on device with 6.8% selective risk; at τ=0.80 it keeps 51% with 8.2%. The
untrained model can only reach similar risk by keeping ≤15% on device.

Caveats: N=120 (one item = 0.83 pts; the curves are step functions and the 95% CI on a single point is wide, see
LEDGER 0). Confidence is the raw letter-softmax probability; no temperature scaling. Predictions were produced by
llama-server on a Linux x86 CPU; the same GGUF ships on the phone, so the probabilities (not the latencies) carry
over up to Metal/CPU numerical noise. The conformal certificate remains the cal180 statement (≤10.2% at τ=0.90
under exchangeability); the test120 risk at τ=0.90 (6.8%) is consistent with it but is not itself a certificate.
