# Round 3 phone training (phone-training-v1)

Verdict. NO PROMOTION. Eight Q4_K_M candidates were trained and exported.
Every GGUF loads with complete finite-logit coverage on held-out phone
dev/calfit. The best dev accuracy (C3, Glimmer full set) does not carry
calibration across dev and calfit, Spark vote targets are sharply
mis-calibrated, and the frozen report-split gate was never run. Shipping
GGUF, priors, tau 0.90, prompts, and test120 stay frozen and untouched.

Teachers and student. Teacher labels are open-weight only: Muse Glimmer
30B bf16 on B200 (raw next-token letter distributions, revision `main`
with template/file-size identity, never the old IQ2_M teacher) and Muse
Spark Open fixed-k vote frequencies (empirical samples, never logits).
Student is Llama-3.2-1B-Instruct (unsloth mirror) + LoRA r16, Q4_K_M.
No Meta API, no Baseten spend in this allocation, no agent prose targets.

## Data

Phone v2 inputs: 4,604 developer-contract-template rows over all 38
compiled contracts (v2, one unavailable), 991 independent groups.
Train 3,174 rows / 668 groups SHA `3b544c0f…`, dev 702 / 166 SHA
`062ee507…`, calfit 728 / 157 SHA `a6a913fe…`. Grouping unions v1
siblings with identical canonical keys (wrapper-free context,
candidate-canonical; skillPick distractor-invariant). Parent audit
`passes_exact_overlap_gate=true`; v1 splits leak and are rejected.
Sparse truth: many contracts hold 1–6 independent groups, so per-contract
dev/calfit is mostly NOT MEASURED. Provenance is developer templates,
not human gold and not iPhone traces.

Labels (usable / prompts): controlled 2,915 Glimmer bf16 (prior $20
allocation, billed $1.89, reused at $0 here); phone 4,604 rows from
4,525 distinct prompts (duplicate prompts share one readout by hash);
broader `data_train` 3,964 Glimmer bf16; Spark legacy 2,778 kept of
2,915 (134 incomplete-valid and 3 low-share dropped, never imputed);
Spark phone 3,173 v2 rows + 2,345 generated rows (alpha-0.5 smoothed
k=3 frequencies, verified: 0 convention violations, 0 canonical
held-out overlap, all v2 ids in train). Generated Spark candidates use
short titles, a disclosed label-format difference.

Datasets (SHA-256 in `train/matrix.json`): D_CTRL 2,915; D_PHONE 6,089;
D_FULL 10,053; D_SPARK 2,778; D_SPARKPAIRED 6,088; D_SPARKFULL 8,433.

## Candidates (all B200, 1 epoch, V4 recipe unless noted)

| Candidate | Data | Steps | GGUF SHA-256 (16) | Dev acc/ECE | Calfit acc/ECE |
|---|---|---|---|---|---|
| PG-C1-CTRL-V4-s0 | D_CTRL | 365 | `f70f38989fb9737e` | 0.808 / 0.079 | — |
| PG-C2-PHONE-V4-s0 | D_PHONE | 762 | `cdd6629536826392` | 0.843 / 0.067 | 0.853 / 0.092 |
| PG-C3-FULL-V4-s0 | D_FULL | 1,257 | `d86797fa896c82b4` | 0.870 / 0.066 | 0.879 / 0.102 |
| PG-C4-PHONE-V4-s1 | D_PHONE seed 1 | 762 | `18e4295c4bbd1620` | 0.841 / 0.055 | 0.890 / 0.119 |
| PG-C5-PHONE-CE0-s0 | D_PHONE, CE 0 | 762 | `436f8f42c6e309f0` | 0.833 / 0.090 | — |
| PG-C6-SPARK-V4-s0 | D_SPARK | 348 | `a32863aa8151f2fe` | 0.798 / 0.234 | — |
| PG-C7-SPARKPAIRED-V4-s0 | D_SPARKPAIRED | 761 | `f2163c7f50416631` | 0.832 / 0.220 | — |
| PG-C8-SPARKFULL-V4-s0 | D_SPARKFULL | 1,055 | `fbda8cdd0fe471d6` | 0.858 / 0.217 | — |

Evaluation is raw-GGUF zeroShot letter readout on held-out groups with
Glimmer-top gold (selection diagnostic, not human gold). Censored
letters fail coverage; every run above had complete coverage and
finite logits. Readings: phone data helps over control (C2 vs C1);
broader data helps accuracy further (C3) with worse calfit ECE; seed 1
trades the same way; removing hard CE hurts ECE (C5); Spark vote
targets keep accuracy but destroy calibration (C6–C8 ECE ≈ 0.22),
confirming vote frequency is not teacher probability. Dev
confirmBeforeAct has only 20 group-correlated rows (most candidates
0/20, C8 20/20) and is reported as sparsity, not signal.

## Spend ($100 Modal cap for this job)

Provider-reconciled billed total **$6.09**, all envelopes closed, zero
open attempts, every phone Modal app stopped with 0 tasks. Labels
$4.05 (smoke $0.55, phone $1.78, broader $1.72 across two apps);
training $2.03 (five-candidate run $1.25, C6 $0.23, C7/C8 $0.55, crashed
prepare attempts $0.00). Per-attempt allocation pro-rates each app bill
by wall estimate; the aggregate is the provider bill. Ledger:
`/tmp/pocket-glimmer-training-scale/phone-training-v1/ledger.jsonl`.
Failed attempts retained: terminated smoke 1 ($0.0003 billed),
IndexError smoke 2 ($0.001), crashed train prepare ($0.00).

## Limits and drift

- Gold is teacher-top on developer templates. No human gold, no iPhone
  latency/memory/thermal or delivery evidence follows.
- App master now carries v3 datetime contracts (time/recipient repair);
  this tranche froze v2 contracts. Datetime candidate behavior must be
  re-checked against v3 before any app claim. Contract drift reported,
  not silently retrained.
- The two-turn clarification failure (`text Dana` → chat) is app
  sequencing work owned elsewhere. No training target here encodes it.
- Promotion still needs the frozen report-split gate, real-model
  routing/action/clarification benchmarks, and phone verification.
  None was run; no candidate is promoted.
