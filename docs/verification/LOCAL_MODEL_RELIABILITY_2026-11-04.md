# OffLlama local-model reliability (2026-11-04)

Investigator: Claude Opus 5.5 (user assignment), worktree `t3-64f5de26`, base `f87567b`, branch
`t3/offllama-route-context-calibration`. Zero paid inference and zero GPU spend. Every model number below comes from local CPU
runs of the shipping GGUF on my own `llama-server` (127.0.0.1:8299, llama.cpp `13ec8f6`, `-t 4 -c 4096`). Linux CPU
numbers are not iPhone Metal numbers. No private prompt text was read. All utterances are synthetic or come from
the frozen cal180 split. test120 was not used.

Artifacts and their hashes:

| Artifact | SHA-256 |
|---|---|
| `models/SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf` | `a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2` (verified) |
| `app/PocketGlimmer/Resources/Models/calibration.json` | `b9ce25b5223103944803c2668784c484ac7eee75b33aa984e62185728970a8f1` (fewShot, defaultTau 0.90, cc priors, T empty) |

## Summary for the product decision

1. **Train/serve skew in the route decision (measured, fixed on this branch).** `Assistant.handle` prepended the
   retrieved-memory block ("Known about the user:\n- …") to every Reflex context. No gold, calibration or training row
   has that block. That covers `eval/gold/*.jsonl` and every `*.jsonl` in the repo (0 hits), plus a read-only grep of the
   R3 phone-training data (0 hits). On a phone with saved memories, route therefore ran outside the regime where
   tau 0.90 was measured. In the benchmark (63 route rows), the block cut route rows handled at tau from 28 to 17 (2 facts)
   and 15.3 (4 facts). Action requests handled went from 9/24 to 2 and 1. There were no confident errors either way. The fix gives only the
   route decision the exact calibrated row shape. Memory stays everywhere else.
2. **The model is still weak on route for messages (measured, not fixable at runtime).** With a clean context, "text mia
   hii" has route argmax answer_local at 0.599. "Text Sam I'm running late" is tool at 0.751. On the same inputs
   toolChoice says send_message at 0.95 to 0.99. Master's deterministic explicit-message parse already covers this case,
   but the installed 7857cd68 does not have it. Fixing it in the model takes training, and no candidate is promoted.
3. **Fallback semantics (code reading, not changed).** A route below tau takes the `escalate_cloud` fallback. Offline,
   that means the answerability decision, then 1B chat generation or an offline notice. Only explicit messages, email and
   explicit app words are intercepted before that point. A reminder, calendar or contact request whose route lands
   below tau still ends in chat or "I can't answer that offline" on master. This is the product-level reason "an action
   turns into a conversational answer".
4. **Engine (code reading, no defect found, not runnable on Linux).** See the engine section.

## What changed in code

`core/Sources/PocketCore/Assistant.swift`:

```swift
let routeCtx = "Network: \(online ? "online" : "offline")\nUser: \(utterance)"
let ctx = mem + routeCtx
...
let route = try await reflex.decide(OptionSets.route, context: routeCtx)
```

`ctx` still carries memories into toolChoice, contactPick, eventPick, skillPick, confirmBeforeAct and the message path.
Answerability and local generation also keep memory. The DecisionPrompt format, calibration, priors, tau, the model,
AppModel, Views, Conversations and ActionPlan are untouched.

Why only route. Memory lowered route confidence in every probed case, and in 56 (2 facts) and 57 (4 facts) of 63 benchmark rows. When I made
this change, toolChoice looked mixed from 9 single probes. The later benchmark shows memory also costs toolChoice on
average (see below), so the toolChoice decision deserves a follow-up. Memory flipped "Remind
me to call mom at 5pm" from create_reminder to send_message (0.52) and dropped lookup_contact from 0.948 to 0.796. It
also lifted a memory-referenced event from 0.863 to 0.974. contactPick genuinely uses relationship memory. Removing memory
from those decisions would trade measured gains for measured losses, so they keep it.

Tests (`core/Tests/PocketCoreTests/AssistantTests.swift`):

- `testRouteSeesCalibrationRowWhileLocalAnswerKeepsMemories` checks two things with a saved memory. The route context
  recorded in telemetry is exactly `Network: offline\nUser: …`, and the local answer prompt still contains the
  memory. Red on `f87567b` (the recorded context began with `Known about the user:\n- Linda is the user's mom`), green on
  the fix.
- `testContactPickStillSeesRelationshipMemory` checks that the contactPick context still contains "Sam is the user's
  brother" while route has the bare row. It guards against widening the change later.
- Full core suite, Docker `swift:6.1-noble`, `swift test`: **377 executed, 1 skipped, 0 failures**
  (`local_model_reliability_2026-11-04/core-suite-summary.txt`).
- The parent integrated `645fd44` as `22e67a6` and strengthened the Linda test so the name appears only in memory. The
  parent reports a full core pass of 385 tests. I did not rerun that integration.

## Parent's requested memory-dependent cases (shipping GGUF, bare vs with memory)

Source: `local_model_reliability_2026-11-04/memory_cases_probe.json` (it includes raw letter log-probs). An asterisk marks
conf at or above tau 0.90.

| Case | Decision | Gold | Bare | With memory | Effect of route-only change |
|---|---|---|---|---|---|
| "text my brother I'm on my way" (memory: Sam Ortiz is the brother) | route | tool | tool 0.760 | tool 0.627 | route conf goes up; both below tau |
| same | toolChoice | send_message | 0.981* | 0.965* | unchanged (keeps memory) |
| "What's my brother Sam's number?" (Sam Lee, Sam Ortiz) | contactPick | c1 | c0 0.712 | c1 0.996* | unchanged (keeps memory) |
| "What's Sam's number?" (no hint) | contactPick | ask | c0 0.661 | c1 0.996* | unchanged. **Risk:** memory makes a confident pick where asking is right |
| "When is my dentist appointment?" (memory: dentist is Dr. Park) | route | tool | 0.877 | 0.837 | route conf goes up; both below tau |
| same | toolChoice | find_event | 0.863 | 0.974* | unchanged (keeps memory; memory helps here) |
| same | eventPick | e0 | 0.917* | 0.922* | unchanged |
| "What's my mom's name?" (memory: Linda) | route | tool | clarify 0.462 | answer_local 0.640 | both below tau, so the same fallback |
| same | toolChoice | search_memory | lookup_contact 0.878 | lookup_contact 0.348 | pre-existing model error |
| same | answerability | yes | 0.878 | 0.877 | unchanged (keeps memory) |

Genuine loss from the route-only change: none found in these cases. Memory Q&A reaches the same reply either way (route
below tau, then answerability below tau, then the "Here's what I know: …" memory text).

## Benchmark: does a memory block in the decision context change what the shipping model does?

**Question.** On the shipping GGUF with the shipped runtime contract (fewShot prompt, cc priors, T=1, tau 0.90), does
prepending a retrieved-memory block to a decision context, as `Assistant` did before this branch, change route and
toolChoice behaviour? The branch removes the block from route only. So for route, "bare" is the behaviour after the
fix and "mem2/mem4" is the behaviour before it on a phone with saved memories. For toolChoice, which the branch does not
change, the table measures the cost of the memory block that toolChoice still receives.

**Data. Two sources, always reported separately and then together.**

- cal180 route and toolChoice rows (15 + 15) from `eval/gold/gold_calibration.jsonl`. This is **diagnostic reuse**:
  this split fitted the priors and selected tau, so it is not held out. The bare numbers are in-sample for calibration.
- 48 offline route utterances plus 20 toolChoice labels that **I wrote for this benchmark** (`AUTHORED` in
  `memory_context_bench.py`). The labels are mine. They are not frozen, not teacher-checked, and nobody else reviewed them.
  Mix: 20 tool, 10 answer_local, 10 escalate_cloud, 8 clarify.
- test120 and the report split were not used.

**Conditions.** bare = the row as stored. mem2/mem4 = 2 or 4 facts sampled from a fixed pool of 12 synthetic facts and
rendered exactly as `MemoryDisclosure.local.render` does. There are 3 seeds per row, and the seed is fixed per
(seed, row). On a real phone, retrieval ranks facts by relevance (k=4, cosine >= 0.15). Random facts are therefore an
approximation of weakly relevant memories, not a replay of device retrieval.

**Method.** `memory_context_bench.py` mirrors `Reflex.decide`. `training/pg_train/prompts.llama3` is tested
byte-equal to `DecisionPrompt.llama3`. Readout is `n_probs 40`, missing letters are floored at min - 2, the prior is
subtracted, softmax runs at T=1, and the gate is tau 0.90. In total 686 decisions over 98 rows: 63 route rows and 35
toolChoice rows, each run as bare x1, mem2 x3 and mem4 x3.

**Statistics.** The unit is the row. Seeds are never pooled as independent examples. Per-seed metrics are computed over
rows and shown as mean [min, max] across seeds. Paired changes average each row's three seeds first. A cluster bootstrap
resamples rows (4000 draws, fixed RNG) for the 95% CI, and an exact two-sided sign test runs over rows.

**Run-to-run variance (measured, `repeat_check.py`).** I repeated the 15 cal180 route rows bare, plus mem4 seed 1 with
the identical facts, against the same server: 30 decisions in total. Max absolute confidence change was 0.037, mean
0.009. There were 0 argmax changes and 0 rows that changed side of tau. The raw letter log-probs for those 30
decisions are in `repeat_check.json`. A separate run of the Swift `pg-cli e2e`, compared with the saved 2026-11-04
file (a different llama.cpp build and session), differed by up to 0.046 with one coin-flip argmax change. That
comparison spans builds and is not same-server variance. Both sit well below the memory effect: route confidence fell by
0.104 per row on average with 4 facts.

### Plain-language result

- **Action requests (gold tool, 24 rows):** with a clean context the model sends 9 of 24 straight to the action path
  above tau. With 2 memories it sends 2 of 24, and with 4 memories it sends 1 on average (range 0 to 2 across seeds).
  Every one of the 24 rows lost confidence (24 down, 0 up, p = 1.2e-7).
- **Greetings and small talk (gold answer_local, 13 rows):** 4 of 13 handled on device with a clean context. With
  memory, 0 of 13. All 13 rows lost confidence, by 0.22 to 0.28 on average.
- **Cloud-worthy requests (15 rows):** almost unaffected (-0.03 confidence). They stay above tau.
- **Vague requests (gold clarify, 11 rows):** below tau in every condition. The model never handles clarify locally, with
  or without memory.
- **No confident errors in any condition.** Memory does not make the model wrong while sure. It makes it unsure, which
  sends more requests into the fallback.
- **Argmax accuracy barely moves** (route: 48/63 bare vs 48.7 and 47.7 with memory). The damage is to confidence, and
  therefore to how often the app acts on the model's choice.
- **toolChoice is also hurt on average, and this branch leaves it unchanged.** Handled at tau falls from 26/35 to 15 and
  13.3 (-0.31 and -0.36 per row; the 95% CI excludes 0). Argmax correct falls from 31/35 to about 29. That contradicts
  my earlier single-probe reading that toolChoice was "mixed". The memory-referenced event case is a genuine gain, but in
  aggregate memory costs toolChoice. Recommended follow-up, not done here: give toolChoice the bare row too, once a test
  covers memory-referenced events. That is a product trade-off for the parent to decide.

### Full tables


#### route, cal180 (calibration split, diagnostic reuse: it fitted priors/tau, so not held out) (n = 15 rows)

| condition | argmax correct | handled at tau | correct of handled | confident errors | ECE | mean conf |
|---|---|---|---|---|---|---|
| bare | 12/15 | 7/15 | 7 | 0 | 0.127 | 0.820 |
| mem2 | 12 [12, 12]/15 | 5 [5, 5]/15 | 5 [5, 5] | 0 [0, 0] | 0.178 [0.140, 0.244] | 0.729 [0.712, 0.752] |
| mem4 | 11.7 [11, 12]/15 | 4.7 [4, 5]/15 | 4.7 [4, 5] | 0 [0, 0] | 0.135 [0.131, 0.138] | 0.715 [0.701, 0.725] |

#### route, authored (48 offline utterances written for this bench; labels are mine, not frozen or teacher-checked) (n = 48 rows)

| condition | argmax correct | handled at tau | correct of handled | confident errors | ECE | mean conf |
|---|---|---|---|---|---|---|
| bare | 36/48 | 21/48 | 21 | 0 | 0.108 | 0.760 |
| mem2 | 36.7 [36, 38]/48 | 12 [12, 12]/48 | 12 [12, 12] | 0 [0, 0] | 0.130 [0.091, 0.152] | 0.680 [0.674, 0.692] |
| mem4 | 36 [35, 37]/48 | 10.7 [10, 12]/48 | 10.7 [10, 12] | 0 [0, 0] | 0.111 [0.093, 0.127] | 0.656 [0.649, 0.662] |

#### route, all rows (n = 63 rows)

| condition | argmax correct | handled at tau | correct of handled | confident errors | ECE | mean conf |
|---|---|---|---|---|---|---|
| bare | 48/63 | 28/63 | 28 | 0 | 0.113 | 0.774 |
| mem2 | 48.7 [48, 50]/63 | 17 [17, 17]/63 | 17 [17, 17] | 0 [0, 0] | 0.116 [0.100, 0.135] | 0.692 [0.684, 0.699] |
| mem4 | 47.7 [46, 49]/63 | 15.3 [14, 17]/63 | 15.3 [14, 17] | 0 [0, 0] | 0.101 [0.078, 0.120] | 0.670 [0.667, 0.675] |

#### toolChoice, cal180 (calibration split, diagnostic reuse: it fitted priors/tau, so not held out) (n = 15 rows)

| condition | argmax correct | handled at tau | correct of handled | confident errors | ECE | mean conf |
|---|---|---|---|---|---|---|
| bare | 12/15 | 12/15 | 12 | 0 | 0.102 | 0.843 |
| mem2 | 12 [12, 12]/15 | 5.7 [5, 6]/15 | 5.7 [5, 6] | 0 [0, 0] | 0.186 [0.177, 0.202] | 0.774 [0.755, 0.791] |
| mem4 | 12 [12, 12]/15 | 5.7 [5, 7]/15 | 5.7 [5, 7] | 0 [0, 0] | 0.208 [0.195, 0.224] | 0.731 [0.720, 0.751] |

#### toolChoice, authored (48 offline utterances written for this bench; labels are mine, not frozen or teacher-checked) (n = 20 rows)

| condition | argmax correct | handled at tau | correct of handled | confident errors | ECE | mean conf |
|---|---|---|---|---|---|---|
| bare | 19/20 | 14/20 | 14 | 0 | 0.112 | 0.871 |
| mem2 | 17.3 [17, 18]/20 | 9.3 [9, 10]/20 | 9.3 [9, 10] | 0 [0, 0] | 0.166 [0.157, 0.174] | 0.825 [0.819, 0.831] |
| mem4 | 17 [17, 17]/20 | 7.7 [7, 8]/20 | 7.7 [7, 8] | 0 [0, 0] | 0.135 [0.112, 0.170] | 0.811 [0.809, 0.814] |

#### toolChoice, all rows (n = 35 rows)

| condition | argmax correct | handled at tau | correct of handled | confident errors | ECE | mean conf |
|---|---|---|---|---|---|---|
| bare | 31/35 | 26/35 | 26 | 0 | 0.108 | 0.859 |
| mem2 | 29.3 [29, 30]/35 | 15 [14, 16]/35 | 15 [14, 16] | 0 [0, 0] | 0.145 [0.139, 0.153] | 0.803 [0.798, 0.807] |
| mem4 | 29 [29, 29]/35 | 13.3 [12, 15]/35 | 13.3 [12, 15] | 0 [0, 0] | 0.145 [0.112, 0.174] | 0.777 [0.771, 0.785] |

#### Paired change vs bare (all rows; per-row seed mean; cluster bootstrap over rows, 4000 resamples, 95% CI; exact sign test over rows)

| decision | gold class | condition | metric | mean change per row | 95% CI | rows down / up / same | sign-test p |
|---|---|---|---|---|---|---|---|
| route | all (n=63) | mem2 | confidence | -0.082 | [-0.108, -0.056] | 56 / 7 / 0 | 1.4e-10 |
| route | all (n=63) | mem2 | handled at tau | -0.175 | [-0.270, -0.090] | 12 / 0 / 51 | 0.00049 |
| route | all (n=63) | mem2 | argmax correct | +0.011 | [-0.032, +0.058] | 3 / 3 / 57 | 1 |
| route | all (n=63) | mem4 | confidence | -0.104 | [-0.135, -0.074] | 57 / 6 / 0 | 1.6e-11 |
| route | all (n=63) | mem4 | handled at tau | -0.201 | [-0.296, -0.111] | 15 / 0 / 48 | 6.1e-05 |
| route | all (n=63) | mem4 | argmax correct | -0.005 | [-0.063, +0.053] | 5 / 4 / 54 | 1 |
| route | tool (n=24) | mem2 | confidence | -0.087 | [-0.107, -0.069] | 24 / 0 / 0 | 1.2e-07 |
| route | tool (n=24) | mem2 | handled at tau | -0.292 | [-0.472, -0.125] | 8 / 0 / 16 | 0.0078 |
| route | tool (n=24) | mem4 | confidence | -0.118 | [-0.145, -0.094] | 24 / 0 / 0 | 1.2e-07 |
| route | tool (n=24) | mem4 | handled at tau | -0.333 | [-0.528, -0.167] | 9 / 0 / 15 | 0.0039 |
| route | answer_local (n=13) | mem2 | confidence | -0.222 | [-0.272, -0.172] | 13 / 0 / 0 | 0.00024 |
| route | answer_local (n=13) | mem2 | handled at tau | -0.308 | [-0.538, -0.077] | 4 / 0 / 9 | 0.12 |
| route | answer_local (n=13) | mem4 | confidence | -0.275 | [-0.323, -0.227] | 13 / 0 / 0 | 0.00024 |
| route | answer_local (n=13) | mem4 | handled at tau | -0.308 | [-0.538, -0.077] | 4 / 0 / 9 | 0.12 |
| route | escalate_cloud (n=15) | mem2 | confidence | -0.024 | [-0.029, -0.019] | 15 / 0 / 0 | 6.1e-05 |
| route | escalate_cloud (n=15) | mem2 | handled at tau | +0.000 | [+0.000, +0.000] | 0 / 0 / 15 | 1 |
| route | escalate_cloud (n=15) | mem4 | confidence | -0.029 | [-0.036, -0.023] | 15 / 0 / 0 | 6.1e-05 |
| route | escalate_cloud (n=15) | mem4 | handled at tau | -0.044 | [-0.111, +0.000] | 2 / 0 / 13 | 0.5 |
| route | clarify (n=11) | mem2 | confidence | +0.014 | [-0.042, +0.063] | 4 / 7 / 0 | 0.55 |
| route | clarify (n=11) | mem2 | handled at tau | +0.000 | [+0.000, +0.000] | 0 / 0 / 11 | 1 |
| route | clarify (n=11) | mem4 | confidence | +0.027 | [-0.018, +0.075] | 5 / 6 / 0 | 1 |
| route | clarify (n=11) | mem4 | handled at tau | +0.000 | [+0.000, +0.000] | 0 / 0 / 11 | 1 |
| toolChoice | all (n=35) | mem2 | confidence | -0.056 | [-0.092, -0.018] | 28 / 7 / 0 | 0.00051 |
| toolChoice | all (n=35) | mem2 | handled at tau | -0.314 | [-0.476, -0.152] | 14 / 1 / 20 | 0.00098 |
| toolChoice | all (n=35) | mem2 | argmax correct | -0.048 | [-0.124, +0.000] | 2 / 0 / 33 | 0.5 |
| toolChoice | all (n=35) | mem4 | confidence | -0.082 | [-0.124, -0.037] | 32 / 3 / 0 | 4.2e-07 |
| toolChoice | all (n=35) | mem4 | handled at tau | -0.362 | [-0.533, -0.200] | 15 / 1 / 19 | 0.00052 |
| toolChoice | all (n=35) | mem4 | argmax correct | -0.057 | [-0.143, +0.000] | 2 / 0 / 33 | 0.5 |

#### What the route decision does with each request (offline, all rows)

Model acts: conf >= tau and argmax is the gold option. Falls back: conf < tau. The app then takes the escalate_cloud fallback (offline: the answerability decision, then chat or an offline notice) unless a deterministic rule intercepts first. Wrong and confident: conf >= tau with the wrong option. mem2/mem4 counts are rows, mean [min, max] over 3 seeds.

| gold route | rows | condition | model acts | falls back | wrong and confident |
|---|---|---|---|---|---|
| tool | 24 | bare | 9 | 15 | 0 |
| tool | 24 | mem2 | 2 [2, 2] | 22 [22, 22] | 0 [0, 0] |
| tool | 24 | mem4 | 1 [0, 2] | 23 [22, 24] | 0 [0, 0] |
| answer_local | 13 | bare | 4 | 9 | 0 |
| answer_local | 13 | mem2 | 0 [0, 0] | 13 [13, 13] | 0 [0, 0] |
| answer_local | 13 | mem4 | 0 [0, 0] | 13 [13, 13] | 0 [0, 0] |
| escalate_cloud | 15 | bare | 15 | 0 | 0 |
| escalate_cloud | 15 | mem2 | 15 [15, 15] | 0 [0, 0] | 0 [0, 0] |
| escalate_cloud | 15 | mem4 | 14.3 [14, 15] | 0.7 [0, 1] | 0 [0, 0] |
| clarify | 11 | bare | 0 | 11 | 0 |
| clarify | 11 | mem2 | 0 [0, 0] | 11 [11, 11] | 0 [0, 0] |
| clarify | 11 | mem4 | 0 [0, 0] | 11 [11, 11] | 0 [0, 0] |


### Limits

- Linux CPU llama.cpp `13ec8f6`, not iPhone Metal. The `ios-arm64` framework cannot run here.
- 63 route rows and 35 toolChoice rows. The CIs above are wide for per-class handled counts (for example answer_local
  n=13).
- The memory facts are synthetic and randomly sampled, not relevance-ranked retrieval.
- The authored labels are mine. cal180 is in-sample for calibration.
- The main benchmark JSON stores argmax and confidence per decision but not raw log-probs. Raw letter log-probs are kept
  for `memory_cases_probe.json` (10 paired cases) and `repeat_check.json` (30 decisions).
- None of this measures delivery on the phone, the native handoff, or the deterministic master repairs. It measures
  only the route and toolChoice decisions.

### Independent corroboration (read-only)

The training evaluator's `docs/training/R3_PHONE_RUNTIME_EVALUATION.md` (`origin/t3/phone-runtime-v2-evaluation`,
`68795be`) added a paired with-memory condition: first 200 dev rows, 3-fact block. C3 held accuracy (0.755 to 0.755,
mean confidence 0.765 to 0.749). C8 degraded (0.695 to 0.670, confidence 0.579 to 0.499). It states that its harness has
no memory block and that no candidate qualifies.


## Engine trace (code reading)

`LlamaCppEngine.nextTokenLogits` tokenizes the decision prompt with `addBOS: true`, giving `<BOS><BOS>…`, the same
stream as llama-server's string prompt. It prefills with common-prefix reuse, reads the last-token logits, keeps letter
variants (" A", "A") only inside the vocabulary top-40, and log-sum-exps them. That is the same contract as
`LlamaServerEngine` (`n_probs 40`). `Reflex.decide` floors missing letters at min - 2, subtracts the per-set prior,
applies softmax at T=1, and gates on conf >= tau.

Can a chat reply corrupt the next decision? On the default path I found no mechanism.

- `generate` tokenizes with a single BOS, and decisions use a double BOS. After a chat reply the common prefix is
  therefore 1 token. `prefill` calls `llama_memory_seq_rm(mem, 0, 1, -1)` and re-decodes from position 1. Positions are
  inferred from the sequence's max position, so they are correct after the truncation.
- `cached` is updated after every successful single-token decode, so it matches the KV contents when generation stops
  on EOG or on budget.
- Decisions that share a prefix (rememberOrNot, then route) reuse the KV prefix, which is correct for causal attention.
- Prefix reuse across sequences (`pg_kv_prefix`) is off by default and was not analyzed further.
- One edge: if `llama_decode` fails mid-generation, `cached` stays at the previous tokens, and the KV state after a
  failed decode is not re-validated. That is rare and not linked to any reported symptom.

None of this ran on Linux, because the llama xcframework is `ios-arm64` only. Metal numeric drift relative to CPU is
unmeasured.

Swift-path parity on Linux (measured). `pg-cli e2e` (the real `Reflex` plus `LlamaServerEngine`) with the shipped
calibration gave 15/18 argmax and 10/18 handled, all 10 correct. The saved `eval/results/e2e_swift_shipping_tau090_cc.txt`
has 16/18 and 10/18 with 10/10. Confidence differs by up to 0.046 (nudgeNow 0.680 vs 0.634). The one argmax change is a
coin-flip row (rememberOrNot 0.491 "no" vs 0.512). The handled set is identical. The Python mirror used for the probes
matches the Swift path on identical contexts within 0.007 with the same argmax (`parity_check.py`): 0.940/0.940,
0.772/0.776, 0.739/0.739, 0.423/0.416, 0.994/0.994. Measured same-server repeat variance is in the benchmark section
(max 0.037 over 30 decisions).

## Training vs runtime vs product

| Problem | Kind | Evidence | Fix |
|---|---|---|---|
| Memory block in route context | runtime | measured above | this branch |
| Route unsure on message phrasings ("text mia hii") | model | bare-context probe | deterministic parse on master now; training later |
| Low-confidence action falls into chat offline | product/runtime policy | code path | see plan item 2 |
| toolChoice picks lookup_contact for memory Q&A | model | probe | training data; not a runtime patch |
| contactPick over-confident with relationship memory | model + context | probe | product: confirm the recipient on cards (already the case for messages) |
| Group names becoming individual contacts | deterministic parse | master repairs (not reinstalled yet) | install master |

R3 boundary. `docs/training/R3_PHONE_TRAINING.md` (read-only copy in worktree `t3-18e15aaa`) says **NO PROMOTION**.
C3's dev 0.870 / ECE 0.066 and calfit 0.879 / ECE 0.102 are raw-GGUF **zeroShot** letter readouts. The app runs
**fewShot** with cc priors, and the frozen report-split gate was never run. They are not frozen-app measurements. The R3
data also has no memory blocks, so a promoted candidate would meet the same route-context shift unless this fix ships.

## Ranked next-hour plan

1. **Install master plus this branch on the phone** (cost: one build and install; gate: Mac reviewer's build and the
   demo checklist). Payoff: the deterministic message/group/chart repairs plus the route fix, where both apply. Expected
   effect on phones with saved memories: route behaves like the bare rows in the benchmark. Even then, 15 of 24 action
   requests stay below tau, so the deterministic rules still carry most actions. The size is measured on CPU only.
2. **Decide the offline action-fallback policy (product call, about 30 min including tests).** Today a below-tau
   tool route offline becomes chat. One option: when route argmax is `tool`, run toolChoice. If toolChoice clears tau,
   take the action path. Every effect still goes through the ledger's confirmation floor, and messages always confirm.
   This is a new joint gate, and it is not calibrated. It would need a measured coverage/error table on cal180 before
   anyone claims safety. I did not implement it.
3. **Training (not this hour).** Add memory-prefixed contexts and casual message phrasings to the training mix. The
   Wonder evaluator owns any candidate evaluation. My raw probes were sent to it.
4. **toolChoice context follow-up (code, about 20 min, parent's call).** The benchmark shows the memory block also costs
   toolChoice (handled -0.31 to -0.36 per row). Needs a test for memory-referenced events before changing it.
5. **Do not lower tau.** Nothing measured here justifies it. The memory shift caused no confident errors, so the problem is
   coverage, not safety.

## Commands

```
llama-server -m models/SHIPPING-ep1-…Q4_K_M.gguf --port 8299 -t 4 -c 4096 --host 127.0.0.1
python3 -I docs/verification/local_model_reliability_2026-11-04/route_probe.py <root> route
python3 -I docs/verification/local_model_reliability_2026-11-04/route_probe.py <root> toolChoice
python3 -I docs/verification/local_model_reliability_2026-11-04/memory_cases_probe.py <root> <out.json>
python3 -I docs/verification/local_model_reliability_2026-11-04/memory_context_bench.py <root> <out.json>
python3 -I docs/verification/local_model_reliability_2026-11-04/analyze_bench.py <bench.json>
python3 -I docs/verification/local_model_reliability_2026-11-04/parity_check.py <root>
python3 -I docs/verification/local_model_reliability_2026-11-04/repeat_check.py <root> <bench.json> <out.json>
docker run --rm --network host -v $PWD/core:/src -w /src swift:6.1-noble swift test
docker run … pg-cli e2e --url http://127.0.0.1:8299 --calibration app/PocketGlimmer/Resources/Models/calibration.json
```

## Evidence file hashes (SHA-256)

| File | SHA-256 |
|---|---|
| `analyze_bench.py` | `77a49d3cae97ee6f66b35c948bdb18446358e08a7fde8ab65abc11619d9542b9` |
| `core-suite-summary.txt` | `2a5d3c470fe1391bbad799c3332d0ee41d860700bda38a44445b5f922192417e` |
| `memory_cases_probe.json` | `d5371c9b543bfef8ff7b8938e5c13b49e9d9959f878305424c860cb3ae49cf0c` |
| `memory_cases_probe.py` | `9a6cc1818183cc37fbdb689d1eb59784680a7e5448fb6eb218a8bb068afe48ed` |
| `memory_context_bench.json` | `f11ac79141ff04b55b0b97988255e168fa62b0a87ae363081fc4b72068189a0b` |
| `memory_context_bench.py` | `1e6f7747d563a4d5359cef913bf117f0ead9c42cbcd42b31cd4a1b6f59d6d0c7` |
| `memory_context_bench_summary.md` | `225fb3d1224f22a3bd041620159d462068d03160bcf0fec15978b914ecadf764` |
| `parity_check.py` | `2b1cdb89b53b76eae2f19d740928107dd32a7c339673b60aa4eebab527ddea30` |
| `repeat_check.json` | `04198dfec5786fbbeacaebe1e5af7d7cf356258d4c3b1badfac8513ea9cef7ff` |
| `repeat_check.py` | `3cd6681a3ad9a823b52d79b255a0ef91d8a93b74e05a69e645775d687f4b9711` |
| `route_probe.py` | `f572182733a2963f6eaa3d06f96050786076d50a7d6ca6872169d03a524a8757` |
| `route_probe.txt` | `1e1b3ea88d5fc76067ed4a11d99e88851b6a99595d7087454568e24a6c725fe4` |
| `toolchoice_probe.txt` | `7324db19070db762ec3fc2e68af64007c5cf4c853c3c254035d684629b6f0381` |

Server cleanup and spend. My llama-server on 127.0.0.1:8299 was stopped after the last run. I never touched the servers on 8241/8242. Paid inference, GPU and provider spend for this work: $0.
