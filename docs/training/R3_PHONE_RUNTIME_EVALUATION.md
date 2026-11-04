# Round 3 phone runtime evaluation (phone-runtime-v2)

Verdict. NO PROMOTION, and no new training epoch is justified by the
evidence below. The best candidate (C3, Glimmer full set) is underconfident,
not overconfident. A candidate-only temperature fitted on calfit fixes most
of its measured calibration error on dev. Shipping contextual priors hurt
the trained candidate and must not be copied onto it. The frozen report
gate was not run, repeated passes were not completed, and the shipping
runtime context differs from this harness in one documented way, so no
candidate qualifies. Shipping stays untouched.

## Premise tested first (attack-the-premise, explain-the-number)

Premise P. "Candidates, Spark above all, are unusable because confidence
is mis-calibrated (raw ECE about 0.22), so more training data is the fix."

P assumed raw zeroShot ECE, with no temperature, no priors, and no tau,
measures the deployable calibrated model. The test re-measured per-row
letter logits locally at $0, fit calibration on calfit only (728 rows),
and selected on dev only (702 rows). Report and test120 stayed sealed.

Harness validity. The harness reproduces the prior worker's C3 numbers
exactly on both splits. Calfit accuracy 0.8791208791, ECE 0.1018045153.
Dev accuracy 0.8703703704, ECE 0.0658513135. Complete finite coverage on
every scored row. No censored letter was ever filled.

## C3 results (PG-C3-FULL-V4-s0, GGUF d86797fa896c82b4…e538c4)

Gold is Glimmer-top on developer templates. Agreement, not human accuracy.

| Dev readout (n=702) | Acc | ECE | NLL | Mean conf |
|---|---|---|---|---|
| Raw zeroShot | 0.8704 | 0.0659 | 0.3766 | 0.8053 |
| Temperature only (calfit T) | 0.8704 | 0.0431 | 0.3495 | 0.8991 |
| Priors only | 0.8390 | 0.0422 | 0.5676 | 0.8468 |
| Temperature + priors | 0.8390 | 0.0825 | 0.7149 | 0.9203 |

Fitted temperatures sit below 1 (global 0.605, skillPick 0.612). The model
is underconfident. Sharpening helps. Priors flip correct dynamic picks.
ContactPick falls 45/51 to 38/51 and eventPick 21/25 to 12/25 under the
combined profile. The shipping prior vectors were fit for an untrained
base model geometry. They double-correct a trained student.

Calfit-fitted tau for 0.95 handled accuracy is 0.990. On dev it handles
367/702 rows (0.523 share) at 0.929 handled accuracy, below the 0.95
target. That fails a strict handled-accuracy reading on this diagnostic.

Per-type raw dev denominators. skillPick 414/481, timing 89/89,
contactPick 45/51, eventPick 21/25, sensitivity 18/18,
notificationTriage 11/11, route 7/7, confirmBeforeAct 6/20. The
confirmBeforeAct slice is 20 group-correlated rows. It is sparsity, not
signal, exactly as the prior report warned.

## Spark candidate (PG-C8-SPARKFULL-V4-s0, GGUF fbda8cdd0fe471d6…ca92d8)

Complete coverage on calfit (728) and dev (702). Its training targets
were verified directly. Soft targets are alpha-0.5 smoothed k=3 vote
frequencies (file SHA-256 a4b150b5…b010 for v2 rows, 8ab4a204…94b5 for
generated rows). The top target mass caps near 0.50. That trains
confidence down by construction, so raw ECE confounded target scale
with model quality. The premise fails for Spark too.

| C8 dev readout (n=702) | Acc | ECE | NLL | Mean conf |
|---|---|---|---|---|
| Raw zeroShot | 0.8575 | 0.2169 | 0.6776 | 0.6407 |
| Temperature only (calfit T 0.565) | 0.8575 | 0.0488 | 0.5379 | not printed |
| Priors only | 0.8519 | 0.1985 | 0.8254 | not printed |
| Temperature + priors | 0.8519 | 0.0649 | 0.8445 | 0.8463 |

Spark did not destroy calibration. It trained confidence down. One
calfit-fitted temperature recovers most of the gap at unchanged accuracy.
Its calfit tau (0.966) handles only 118/702 dev rows (0.168 share) at
0.898 handled accuracy, so C8 still fails handled-share and
handled-accuracy readings. C3 remains the stronger candidate. Neither
qualifies without the frozen report gate.

## App-facing fixtures (deterministic developer gold, 9 fixtures)

C3 zeroShot, model-only decisions. 6 of 9 correct. Repeated explicit
message before generation passed (conf 0.983) and after generation passed
(0.964). Contact/method ambiguity correctly asked (0.431). Chart request
passed (0.910). Time guard choice passed (0.654). Confirmation choice
passed (0.823).

Three failures are safeguard-critical, not model-promotable. App name
inside the body failed (0.589). Group message chose a single-contact send
at 0.986 confidence. Shared-doc screening chose cloud-ok at 0.957. The
deterministic app safeguards named in the fixtures must catch all three.
These fixtures are fresh developer fixtures, labelled as such, never
human gold. FakeEffects contract proof lives in PocketCore tests owned
elsewhere. No iPhone execution is claimed.

## Context alignment (important limitation)

This harness renders the frozen phone eval contexts as stored. No memory
block is added. A parallel investigation measured that the current
shipping Assistant.swift decision context prepends a "Known about the
user" block, and that block moved the shipping model on synthetic Linux
CPU prompts (route rows clearing 0.90 fell from 4/13 to 1/13). No gold,
calibration, or training row contains that block. So this harness matches
the candidate training geometry and a memory-free runtime geometry. It
does not reproduce the current shipping context when memory exists. That
repair belongs to the application investigation. It is a root-cause
candidate, not proof about private phone turns, and no threshold change
by guess follows from it.

Shipping incumbent through this harness. Scoring was started and stopped
to protect the candidate deadline (137/728 calfit zeroShot rows, 37/702
dev fewShot rows retained as partial artifacts). No shipping number is
reported from partial passes. The Mac device evidence (71 aggregate-only
rows, build 7857cd68) stays a shipping-runtime observation, not a
candidate score.

## Frozen gate status

Frozen criteria from eval/round3/protocol.json were preserved, not
replaced. Report split scored zero times. Promotion requires the report
handled-group Wilson gate, at least 135 handled groups, handled share at
least 0.35, no measured L2/L3/L4 regression, and required categories at
30 groups each. None of that was run for these candidates. Repeated
two-start fresh/warm passes were not completed. NOT MEASURED categories
block promotion. They are not passes.

## Budget

Cap $100 Modal total, carried over and never reset. Prior settled billed
$6.08616426 across 66 BILLED entries, Decimal recomputed, matching the
old budget.json. Remaining cap $93.91383574. This follow-on spent $0.
All evaluation ran on local CPU. Live Modal check found every
pg-phone-train app stopped with 0 tasks. The deployed pg-glimmer-vllm app
belongs to another owner and was not touched. New ledger in the output
root carries the old ledger SHA-256
ce18f9bf5c47521a8f6ae5b0a2776bef001a7eb5c4836af262e079abbdf29b28.
No Baseten and no Meta API spend. No paid process was started, so none
needed stopping.

## Artifacts and hashes

Output root /tmp/pocket-glimmer-training-scale/phone-runtime-v2. It holds
per-row scored JSONL, priors, reports, fixtures, the premise note, and
the carryover ledger. Giant artifacts stay out of Git. Shipping GGUF
SHA-256 a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2.
Candidate full hashes are recorded in the output manifest.

## Tests

phone_runtime_tests 4 passed. Existing suites passed. data validation 7,
duration eval 11, spark label 18, glimmer 9, graders 7. Benchmark
validation passes with overlap, corruption, and missing-label fixtures
correctly rejected. Swift PocketCore tests could not run here. No Swift
toolchain is installed in this Linux environment.

## Next phone gate

Exact next gate. Run the frozen report protocol once for a frozen
candidate plus its candidate-only temperature (no shipping priors), with
two fresh server starts and fresh/warm passes, after the application
context repair lands and is re-measured. Then Mac-side phone
latency, memory, and thermal verification. Nothing in this document
supports a demo accuracy claim. Only measured shipping results may
appear in the demo.
