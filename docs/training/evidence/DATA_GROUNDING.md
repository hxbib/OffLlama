# Data grounding for training scale-up (research only, no training run)

Date: 2026-11-04. Source checkpoint 79e0884 (training source identical to 4b92321).
Scope: read-only repo inspection plus small samples in `/tmp/pocket-glimmer-training-scale/samples/`.
No paid inference, no cloud jobs, no source edits, no synthetic examples or labels authored here.
Shipping GGUF, priors, tau, prompt, cal180 and test120 were not changed. Test120 rows were
never read to invent examples; overlap checks below are automated counts only.

## Verdict: ISSUES (proceed only with the exclusions and re-join below)

The expansion pool is real and mostly clean against the current eval files, but its headline
count overstates independent data, 66 unlabeled rows duplicate older training contexts, the
original MASSIVE/CLINC/SNIPS labels were thrown away so Pocket assignments cannot be audited
from `pool.jsonl` alone, and the current label script caps prevent labeling the full remainder
without a deliberate cap change. None of this blocks a focused post-training tranche. It does
block treating "8,245 rows" as 8,245 independent tasks or labeling the remainder blind.

Evidence labels used below: **[measured]** = counted or downloaded in this pass;
**[publisher]** = stated on the publisher/HF/GitHub primary card; **[estimate]** = arithmetic
from measured unit costs, not a new measurement.

## 1. Existing pool: verified counts

| Quantity | Count | Status |
|---|---:|---|
| `training/data_scale/out/pool.jsonl` | 8,245 | [measured] |
| Synthetic / MASSIVE / CLINC / SNIPS in pool | 5,997 / 1,249 / 699 / 300 | [measured] |
| `training/round2/out/labels_round2.jsonl` | 1,790 | [measured] |
| Labeled synthetic / MASSIVE / CLINC / SNIPS | 1,573 / 108 / 101 / 8 | [measured] |
| Pool IDs absent from label file | 6,455 | [measured] |
| Absent synthetic / MASSIVE / CLINC / SNIPS | 4,424 / 1,141 / 598 / 292 | [measured] |
| Kept after build filter (top-share >= 0.6) in r2c | 1,750 of 1,790 | [measured] `build_stats_r2c.json` |
| Full r2c train file (Glimmer 892 + Nov-1 extra 273 + r2 1,750) | 2,915 | [measured] SHA-256 `afcf82d7...fec7dd3b3` per ledger |

The task brief's 8,245 / 1,790 / 6,455 (4,424 / 1,141 / 598 / 292) accounting is exact.

Unlabeled remainder by Pocket type [measured]: route 1,556; nudgeNow 993; toolChoice 831;
answerability 681; contactPick 541; timing 462; notificationTriage 331; rememberOrNot 264;
eventPick 229; confirmBeforeAct 227; sensitivity 183; memoryConflict 157. The remainder is
therefore dominated by `route`, the type with the weakest original-label support (see §3).

### 1a. Dedupe against eval and CLINC OOS stress

- Re-running `training/local_teacher/dedupe.py` (`norm` exact on full context and on user
  utterance, plus char-5-gram Jaccard >= 0.8) for all 8,245 pool rows against all 636
  `eval/**/*.jsonl` rows with a context returns **kept 8,245, dropped 0** [measured].
  Exact-overlap count alone is also 0. The pool does not duplicate cal180/test120 rows
  under the project's own guard. This is a row/utterance guarantee only, not a family one.
- CLINC OOS stress (`clinc_oos_test_stress.jsonl`, 2,000 rows = 1,000 test OOS utterances x
  route/answerability): exact utterance overlap with the pool is 0, and pool-CLINC vs
  stress-route near-duplicates (Jaccard >= 0.8) are 0 [measured]. Train/test split hygiene
  holds at row level. Family leakage remains: pool CLINC OOS-train and stress OOS-test are
  the same publisher OOS distribution, so stress measures in-distribution abstention, not a
  new family. Keep stress report-only; never train on CLINC test or validation if stress
  stays an eval (see §5).

### 1b. Older training contexts (the brief's extra exclusion)

`label_round2.py` excludes by exact `context` against Glimmer/Spark/cal/gold files before
labeling, so the 1,790 labeled rows are already clean. The **unlabeled** remainder is not:

| Older file | Unlabeled pool rows whose context already appears there |
|---|---:|
| `distill_train.jsonl` (Glimmer 892) | 66 rows / 65 distinct contexts [measured] |
| Union of distill + train_labels + extra + cal + gold_all seen-set (1,577 contexts) | 83 rows [measured] |

Action: before any new labeling, drop unlabeled rows by **context** (not ID) against that
union. Labelable remainder is then 6,455 - 83 = **6,372 rows**, before family caps. Any
brief that says "label the 6,455" without this step double-trains 83 contexts.

### 1c. Source-family inflation (why row count is not task count)

- Synthetic: 5,997 rows collapse to **2,919 distinct utterances** and **1,194 distinct
  core contexts** after stripping the `Now:`/location envelope [measured]. One notification
  core repeats 56 times; 363 utterance groups cover 3,441 pool rows. `pg_train/scenarios.py`
  draws from 12 names, 8 places, 7 items, 6 times, 7 notifications: paraphrase volume, not
  new tasks. Cap synthetic per core template (recommend <= 4 per core in train, 0 cores
  shared across train/dev/final) or added synthetic rows will mostly re-teach templates.
- HF rows behave oppositely: MASSIVE 1,249/1,249, CLINC 699/699, SNIPS 300/300 distinct
  utterances [measured]. New independent data must come from HF/publisher utterances and
  dialogue turns, not from more `scenarios.py` samples.
- Hint vs teacher agreement on labeled synthetic [measured, `label_qc.json`]: timing 1.000,
  contactPick 0.993, eventPick 0.90, notificationTriage 0.872, nudgeNow 0.842, overall 0.921.
  Disagreement concentrates exactly where the decision is genuinely contextual (nudge,
  notification). Hints are generator intent, never gold; do not train on hints.

### 1d. Label-script caps bind

`label_round2.py` CAPS total 4,783 selections (e.g. route 500 vs 1,556 unlabeled route rows;
toolChoice 450 vs 831). A naive re-run reselects a capped shuffled subset minus done IDs; it
cannot label the full remainder. Raising caps is a deliberate mixture decision (route would
swamp weak types), not a bug fix. State the per-type tranche explicitly in the run brief.

## 2. What the current trainer can and cannot absorb

The student learns one letter per Pocket decision type (`training/pg_train/prompts.py`,
`training/config/option_sets.json`: route, toolChoice, contactPick, eventPick, rememberOrNot,
memoryConflict, notificationTriage, confirmBeforeAct, nudgeNow, timing, sensitivity,
answerability). Any new dataset must be transformed into (context, candidates?, Pocket type)
plus a target letter with recorded provenance. Free-text answers cannot enter this trainer
as targets unless a separate generative SFT path is built and evaluated separately; mixing
generative targets into the letter loss without a new eval would fool the decision metrics.
General instruction/tool competence is therefore a **probe track** (§4, rows marked probe),
not a claim the letter model gains from more letters alone.

## 3. Incorrectly mapped labels and where teacher labels are still required

Root cause [measured]: `training/data_scale/build_pool.py` discards every original label.
It assigns Pocket types by slice position (first 450 tooly MASSIVE -> toolChoice, next
550 -> route, next 250 -> answerability; CLINC OOS/in-scope slices -> route/answerability;
SNIPS 300 -> route). `pool.jsonl` keeps only context/type/source, so the original intent is
unrecoverable from the pool. Re-join by normalized utterance text to the publisher files
before auditing or expanding; do not "fix" mappings from pool rows alone. The raw downloads
(`/workspace/hfdata/`) are absent in this checkout and `build_pool.py` recorded no upstream
revision, so byte-exact reconstruction of the Nov-2 snapshot is impossible; re-download at
the pinned revisions in the manifest and re-run dedupe instead of trusting the old snapshot.

Concrete mapping failures in already-labeled rows [measured examples]:

- MASSIVE `toolChoice` "Have i got any alarms set" -> teacher `none`. Pocket has no alarm
  tool; the original alarm-query intent has no honest Pocket target. Alarm/media/IoT intents
  (play music, playlists, volume, coffee) recur across MASSIVE/SNIPS and force the teacher to
  improvise among `none`/`answer_local`/`escalate_cloud`/`tool`. Exclude intents with no
  Pocket tool from toolChoice; route them only if the route label is the research question.
- MASSIVE `toolChoice` "Delete all events and tasks for today" / "cancel business meeting"
  -> `none` (no delete tool), while the safety-relevant Pocket home for deletion is
  `confirmBeforeAct=confirm`. Deletion/cancel utterances need a confirm envelope or
  exclusion, not toolChoice.
- CLINC `answerability` "Turn your vocals down" -> teacher `yes`; MASSIVE `answerability`
  "Make coffee at six am" -> `yes` at top-share 0.6. Device-control actions scored as
  "a 1B can answer this" teach answerability the wrong boundary. Answerability training
  utterances must be questions/requests for text, not device actions.
- MASSIVE labeled mix: of 71 MASSIVE answerability rows, teacher said `no` 52 times;
  CLINC answerability 72/87 `no` [measured]. In-scope assistant commands wrapped as
  answerability mostly teach "command -> no", colliding with route/toolChoice. Prefer
  SQuAD-style answerable/unanswerable text questions for answerability (§4) and keep
  command-like utterances in route/toolChoice only.

Programmatically verifiable vs teacher-required:

| Pocket decision | Programmatic source of truth | Still needs Meta teacher? |
|---|---|---|
| timing (now/at_time/on_arrival/recurring) | Explicit time/place/recurrence markers; MASSIVE datetime slots; SGD slot values. Hint agreement 1.000 supports rules + spot audit. | Only for implicit times ("after lunch", "later") |
| contactPick / eventPick | Named relation/name/time matches exactly one candidate (generator + SGD/MultiWOZ entity lists) | Only when two candidates match (must be `ask`) or reference is indirect |
| toolChoice (supported tools only) | MASSIVE scenario+intent and SGD service/intent map deterministically to the 6 Pocket tools + `none` | Yes for paraphrases outside the map; never for alarms/media (exclude) |
| answerability | SQuAD v2: answer span present = yes, no-answer = no (publisher label) | Yes for Pocket's narrower "1B offline" boundary (short factual vs deep reasoning) |
| memoryConflict | SNLI entailment/neutral/contradiction as a noisy prior (keep_both/update/ignore_new is not identical to NLI) | Yes; NLI labels alone would mislabel jokes/restatements |
| route, sensitivity, confirmBeforeAct, nudgeNow, notificationTriage, rememberOrNot | No complete programmatic truth; rules cover only clear cases | **Yes, authorized Meta teacher (Spark Open / Glimmer) for every kept row** |

Licensing is not label correctness: a CC-BY utterance with a discarded intent is an
unlabeled input, not a gold Pocket example. Every kept decision row still needs either a
deterministic map (audited) or a Meta-teacher label with vote shares retained.

## 4. Focused additional original datasets (verified this pass)

All HF revisions are commit SHAs from the HF API on 2026-11-04; samples are in
`samples/` with SHA-256 in `source-manifest.json`. "Train-use" means inputs (plus
programmatic map where stated) with Meta-teacher letters. No row below authorizes using a
non-Meta model's answer text as a target. Full table columns: Source | Revision | License |
Origin | Train-use | Eval-use | Transform.

| Source | Revision | License | Origin | Train-use | Eval-use | Transform |
|---|---|---|---|---|---|---|
| MASSIVE 1.1 en-US, `AmazonScience/massive` (expand) | `ff6bd8e4b27c` | CC-BY-4.0 [publisher] | SLURP human assistant utterances, localized [publisher] | Yes: unused train utterances | Yes: dev/test partitions as new dev/final families | Direct S3 JSONL (`amazon-massive-dataset-1.1.tar.gz`, `1.1/data/en-US.jsonl`); **do not** use the HF script loader (trust_remote_code). Map scenario/intent -> Pocket, exclude no-tool intents |
| CLINC150 plus, `clinc/clinc_oos` (expand) | `155b9c710419` | CC-BY-3.0 [publisher] | Crowd intent utterances + OOS [publisher] | Yes: unused plus-train only | Validation as dev; test in-scope as final only if OOS stress retired for that family | Parquet native (`plus/*.parquet`, no script). Keep intent column this time; OOS -> route clarify / answerability no only via teacher |
| SNIPS 2017, `s3prl/SNIPS` + publisher `sonos/nlu-benchmark` | HF `12b3fec40a13`; publisher repo unpinned | Publisher CC0 1.0 per repo LICENSE (HF mirror says MIT; follow publisher) [publisher] | Human voice-assistant queries, 7 intents [publisher] | Limited: unused train for route only | Small dev slice | Unzip publisher data; 7-intent domain is narrow (music/weather/booking). Do not scale route on SNIPS alone |
| BANKING77, `PolyAI/banking77` (new) | `1846984189f2` | CC-BY-4.0 [publisher] | Expert human banking queries, 77 intents [publisher] | Yes: train split (10,003) sampled for ambiguity/route | **Test split (3,080) as held-out final family** | Parquet native (downloaded, hash in manifest). Fine-grained near-duplicate intents are the point: teacher decides tool vs escalate vs clarify; never map 77 labels 1:1 to Pocket tools |
| SGD, `GEM/schema_guided_dialog` + GitHub `dstc8-schema-guided-dialogue` | HF `f272b927123b`; GitHub train/ 128 JSON files [measured] | CC-BY-SA-4.0 [publisher] | Simulator-outlined, crowd-paraphrased task dialogues, 20 domains [publisher] | Yes: train dialogues (16,142) user turns for toolChoice/timing/event/confirm contexts | Dev (2,482) as dev; test (4,201, unseen services) as final family | Use GitHub JSON directly (GEM HF needs its loader script). Extract user turn + service/intent/slots as context; system turns are never targets |
| MultiWOZ 2.2, GitHub `budzianowski/multiwoz` (new) | GitHub `data/MultiWOZ_2.2/` (unpinned; pin commit at download) | MIT per dataset docs [publisher secondary; confirm LICENSE in zip at build] | Human-human booking dialogues, 8 domains [publisher] | Yes: train dialogues user turns (events, times, constraints) | Dev/test dialogues as dev/final | Download GitHub zip JSON, not HF `multi_woz_v22.py` script loader. Single-turn extraction only; keep dialogue ID grouping |
| SQuAD v2, `rajpurkar/squad_v2` (new) | `3ffb306f725f` | CC-BY-SA-4.0 [publisher] | Human Wikipedia questions incl. unanswerable [publisher] | Yes: train sample for answerability (span present/absent) | Validation sample as answerability dev | Parquet native. Context passage + question -> answerability; Pocket boundary still teacher-checked on a sample (long passages must be truncated to phone context budget) |
| SNLI, `stanfordnlp/snli` (new, probe) | `cdb5c3d5eed6` | CC-BY-SA-4.0 [publisher] | Human premise/hypothesis NLI [publisher] | Probe only: memoryConflict prior, small sample | Validation as conflict dev probe | Parquet native. Premise="Existing memory", hypothesis="New statement"; NLI label is a prior, teacher makes the Pocket call |
| Dolly-15k, `databricks/databricks-dolly-15k` (new, inputs only) | `bdd27f4d94b9` | CC-BY-SA-3.0 [publisher] | Databricks-employee human instructions/responses, no generative AI per card [publisher] | Inputs only: instruction (+context) -> route/answerability via teacher. Human `response` text is **not** a Reflex target | Category-stratified dev slice | JSONL native (13 MB single file; sample via rows API). Closed-QA contexts are Wikipedia excerpts; strip citation markers |
| BFCL v3, `gorilla-llm/Berkeley-Function-Calling-Leaderboard` (new) | `61fc0608cfd8` | Apache-2.0 [publisher] | Expert/user-contributed function-calling cases [publisher] | Restricted: simple/multiple user queries as toolChoice contexts (functions renamed to Pocket tools) | **Preferred as eval**: irrelevance (239 rows downloaded [measured]) + live irrelevance as abstention final | Plain JSON lines (card explicitly says do not use `load_dataset`). Expected calls are AST-checkable for the probe track; Pocket letters still need mapping |
| ConfAIde, GitHub `skywalker023/confaide` (eval only) | GitHub benchmark/ 8 txt files [measured] | MIT [publisher] | Human-designed contextual-privacy scenarios, 4 tiers [publisher] | **No** (tiny benchmark; training on it destroys its eval value) | Privacy/sensitivity held-out eval | Plain txt scenarios -> sensitivity contexts, teacher/human rubric scoring offline. Never mix into train |
| OpenMathInstruct-2, `nvidia/OpenMathInstruct-2` (probe only) | `469216e3f46f` | CC-BY-4.0 [publisher] | **Meta-generated**: Llama 3.1 405B solutions to GSM8K/MATH problems [publisher] | Probe only: tiny generative-SFT comparison arm, math only | No decision-eval use | Parquet native but 20 GB full; stream `train_1M` shard sample only. The only large Meta-generated set found; it does not teach phone decisions |

Publisher split sizes relied on above [publisher/datasets-server]: CLINC plus train
15,250 / validation 3,100 / test 5,500; BANKING77 train 10,003 / test 3,080; SGD train
16,142 / dev 2,482 / test 4,201 dialogues; SQuAD v2 train 130,319 / validation 11,873;
SNLI train 550,152. MASSIVE en-US train is ~11.5k utterances (pool used 1,249), CLINC pool
used 699 of 15,250, SNIPS pool used 300 of ~13k: the cheapest "new" data is the unused
majority of already-cleared sources, re-joined with intents, before any exotic source.

Coverage check against the brief: device intent routing/ambiguity = MASSIVE + CLINC +
BANKING77 + HWU-held (§7); contacts/events/time = SGD + MultiWOZ user turns + MASSIVE
calendar/datetime slots (Pocket candidates still synthetic/contextual; no publisher set
supplies Pocket-style contact candidate lists, so contactPick/eventPick stay generator +
dialogue-entity transforms with teacher labels); privacy/abstention = ConfAIde eval +
BFCL irrelevance eval + CLINC OOS; answerability = SQuAD v2 + Dolly inputs; memory
contradictions = SNLI probe + generator; general tool formats = BFCL + SGD schemas as
probe-track AST/state checks, kept out of the letter loss.

## 5. Proposed source-family split (cal180/test120 untouched)

Principle: split by **publisher family + intent/scenario/dialogue group**, never by random
rows. The same normalized utterance, synthetic core template, dialogue, or MASSIVE
intent x scenario cell must sit in exactly one split. Freeze this before labeling tranche 1.

| Split | Families (all new; no cal180/test120 rows) | Role |
|---|---|---|
| Train | MASSIVE train subset, CLINC plus-train subset, BANKING77 train subset, SGD train turns, MultiWOZ train turns, SQuAD train sample, Dolly train inputs, capped synthetic (<=4/core) | Teacher-labeled decision training |
| Dev-new (selection) | MASSIVE dev partition, CLINC plus validation, SGD dev, SQuAD validation sample, Dolly category holdout (whole categories out) | Threshold/recipe selection; replaces cal180 for *new* choices so cal180 stops being reused |
| Final-new (report once) | MASSIVE test partition, BANKING77 test, SGD test (unseen services), BFCL irrelevance/live, ConfAIde tiers | One-shot reporting per frozen candidate; never tuned on, never trained on |
| Frozen legacy | cal180 (selection history), test120 (report-only history), CLINC OOS stress | Unchanged; reported alongside, never mixed into the splits above |

Two cautions. (1) If CLINC plus test in-scope joins Final-new, its OOS siblings overlap the
existing OOS stress family; either retire stress as "final" and demote it to dev, or keep
CLINC test out of Final-new. Do not report both as independent finals. (2) MASSIVE locales
are parallel translations; en-US only for train/dev/final here, or the same utterance leaks
across splits in another language.

## 6. Throughput, cost and what $80 / $105 actually buys

Measured Baseten labeling [measured from `labels_round2.jsonl` + `spend.jsonl`]: 1,790
rows, 4,442 calls (adaptive k 2->5, mean 2.48), 1,147,418 input + 910,935 output tokens,
$5.31 recomputed at $1.25/$4.25 per 1M ($5.56 logged with in-flight allowance) =
**$0.0030/row**. Wall span 54 min including killed sessions = ~33 rows/min observed; the
100 RPM key cap (`label_round2.py` throttles to 94 RPM) bounds throughput at
94 / 2.48 = **~38 rows/min** regardless of workers. Fixed k=5 would cost ~$0.0060/row
[estimate from per-call 258 in / 205 out tokens].

| Job | Rows | Baseten [estimate] | Wall at 94 RPM [estimate] |
|---|---:|---:|---:|
| Label cleaned remainder (6,372) | 6,372 | ~$19 | ~2.8-3.2 h |
| Tranche 1 new tranche (§8, ~8k) | 8,000 | ~$24 | ~3.5-4 h |
| Ambitious combined (~20k) | 20,000 | ~$60 adaptive / ~$120 fixed-k5 | ~9-10 h |

$80 Baseten therefore covers the remainder **or** one new tranche comfortably, and both
only adaptively with the >=0.6 filter retained. Longer SGD/dialogue contexts will cost
more per row than the 258-token average; re-measure on 100 rows before committing (the
repo's own rule). Reserve at least $15 of the $80 for re-labels, QC double-labeling and
final-eval teacher checks; do not allocate the full $80 to first-pass labels.

Measured Modal training [measured `V4-gpu.json`]: 2,915 rows, 365 steps, 37.6 s train,
94.6 s total on H100. At $3.95/H100-hour [Modal rates file] that is ~$0.10 compute per run.
Even 20k rows x 2 epochs stays in low dollars; **$105 Modal is not the bottleneck for
focused LoRA post-training**. It is the budget for Glimmer-teacher serving or repeated
eval serving if those are chosen, and each such use needs its own reservation. The $5 pilot
reservation (two-epoch V4 on r2c) stands as the controlled duration test; do not fold new
data into that pilot.

Honest feasibility: broad pretraining or "general competence" for the 1B from these credits
is not achievable. $105 buys ~26 H100-hours; meaningful continued pretraining needs orders
of magnitude more tokens than that serves, and letter-task SFT does not create general
instruction ability. What is achievable: (a) a 15-25k-row focused decision post-train with
genuinely new families, (b) a small generative probe arm (Dolly inputs + Meta teacher, or
OpenMathInstruct-2 sample) evaluated separately, (c) new dev/final families that stop the
cal180-reuse problem. Report (b) as a probe with its own metrics, never as Reflex gains.

## 7. Exclusions and holds (with reasons)

Excluded as training targets by the Meta-only teacher rule (permissive license does not
cure provenance): UltraChat / UltraInteract, OpenHermes-2.5, WizardLM evol-instruct,
CodeAlpaca, Orca / Orca-AgentInstruct, Tulu-3 mixtures, XLAM function-calling (also gated
`auto`), Magicoder evol (GPT-generated per card), SmolTalk (mixed provenance without a
clean Meta-only subset split). Their *prompts* are still not needed; Dolly/SGD/BFCL cover
the prompt need with cleaner provenance. Muse API outputs (including this agent's) are
likewise not training targets.

Excluded or eval-only on license/scale grounds: NoRobots (CC-BY-NC-4.0, non-commercial;
do not train a shippable student on it), ANLI (CC-BY-NC-4.0), `facebook/natural_reasoning`
(CC-BY-NC-4.0), OpenJev-class NC weights noted in `docs/LICENSING.md`. ConfAIde and BFCL
irrelevance are eval-only by design (small benchmarks; training on them inflates the very
abstention numbers they would report). HWU64 (`FastFit/hwu_64`, HF sha `9fb5bff1`) is a
**hold**: 8,954/1,076/1,076 splits and 64 assistant intents fit the need, but the HF card
declares no license (secondary literature claims CC-BY-4.0); confirm from the publisher
before any download-for-training. MultiWOZ license must be confirmed from the downloaded
zip's LICENSE file at build time for the same reason. Belebele (Meta, CC-BY-SA-4.0) was
checked and deprioritized: translated reading comprehension, low transfer to phone
decisions; use only if a multilingual probe is explicitly wanted.

Also excluded: any further `scenarios.py` volume beyond family caps, any CLINC test/
validation row in train while stress/final uses it, any MASSIVE non-en-US locale in this
tranche, and any row whose context matches the §1b seen-union or fails dedupe vs all eval
plus Dev-new/Final-new families.

## 8. Concrete next data-building brief (for the parent to dispatch)

1. Re-download at manifest revisions (MASSIVE S3 1.1 JSONL, CLINC plus parquet, BANKING77
   parquet, SGD GitHub JSON, SQuAD/SNLI parquet samples, Dolly JSONL). Record SHA-256 per
   file. Keep original intent/scenario/slot columns; never repeat the strip-labels step.
2. Build `pool2` with per-row provenance (publisher, split, original label, Pocket map
   rule or `needs-teacher`). Drop §1b seen-contexts, run dedupe vs all eval + Dev-new +
   Final-new families, cap synthetic at 4/core, exclude no-tool MASSIVE/SNIPS intents from
   toolChoice and device-actions from answerability.
3. Freeze Dev-new/Final-new ID lists (§5) **before** labeling. Publish the freeze hash.
4. Pilot-label 100 rows per new family with Spark Open adaptive k; verify per-row cost and
   94-RPM wall time; only then label Tranche 1 (~8k: remainder weak types first, then
   MASSIVE/CLINC unused train, BANKING train sample, SGD turns; SQuAD/SNLI/Dolly as capped
   minorities). Retain votes, shares and the >=0.6 filter; double-label a 200-row QC slice
   and report teacher-vs-programmatic agreement per §3.
5. Train candidates only after the $5 two-epoch pilot reports; keep target construction
   fixed when comparing data tranches (r2a vs r2c confound must not recur). Evaluate on
   Dev-new for selection, Final-new once, cal180/test120 read-only. Log app ID, input/output
   hashes, reservations and actuals per `ORCHESTRATOR_LEDGER.md` resume procedure.

Open risks: MASSIVE/SGD "human" text is paraphrased/simulator-outlined to different degrees
(cards say so); teacher labels remain model opinions except where §3 gives programmatic
truth; BANKING77's 77-way nearness may teach escalate-everything if over-sampled; SGD
system-style contexts exceed phone prompt budgets and need truncation checks. None of these
is resolved by buying more rows.

Artifacts: this file plus `source-manifest.json` (machine-readable sources, sample hashes)
and `samples/` (792 KB total) and `audit-existing.log` in the same directory. No repo files
were created or modified.


