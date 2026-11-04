# Round-3 phone benchmark and iPhone train tranche

Frozen 2026-11-04 before any new-set scores. Base `4bf72c9`. Spend $0, paid calls 0.
Shipping GGUF, priors, tau, DecisionPrompt, and test120 were not touched.
cal180 stays historical. test120 stays report-only and was not used for selection.

## Verdict

ISSUES with a usable tranche. The cleaned train pool is smaller than the row
headline because groups, not rows, are the unit. Six Pocket types have no new
train groups left after prior-train group exclusion. Those gaps are reported,
not filled with invented examples. No public iPhone interaction gold was found;
iPhone specificity comes from the Pocket skill registry and Apple platform
specifications, both labelled for what they are.

## New train pool for the parent (teachers expand from here)

Path: `training/round3/data_train.jsonl` (3,964 rows, 3,789 groups, all
`needs_label`, sha256 `661bad5a54862212bf6e262c9ddf75f770585ffe77aa25308897ced0d30770fb`).
Both teachers label this file after integration. No labels were created here.
Held-out files: `training/round3/data_dev.jsonl` (500 rows, 500 groups,
sha256 `58ff640d828f228d19434503001876d9e10153e959ce91fb5335d0d61026f4f4`),
`training/round3/data_calfit.jsonl` (255 rows, 255 groups,
sha256 `2670d6340134492f833115a68c0df0b7a682b76e3776adfa86cf54b0df904da2`),
`training/round3/data_report.jsonl` (899 rows, 889 groups,
sha256 `1fad11d9ca052ee5cbc6a1e39edd953bb69aec691fb070b71d895f74bfc29892`).
Builder: `training/round3/data_build.py`. Sources: `training/round3/data_sources.json`
(sha256 `64629880011fafbe54e0d96a25b28976112d62ca6d7667d4f6fae1ec66a44671`).
Protocol: `eval/round3/protocol.json` (sha256 `574060ad421ec8db6af4029edac8b7f9a01f31c55076fc127dd99eceb77788cf`).
Any hash change invalidates the freeze.

## What was rechecked, not assumed

- The old 83 duplicate claim was recomputed. This run finds 79 unlabeled pool
  contexts already present in the seen union (round-2 train files, Glimmer
  distill, Spark label files, round-3 matched inputs). The difference from 83
  is the union definition; both counts are recorded and the 79 were dropped.
- Prior-train group exclusion dropped 1,654 further rows. Their wrapper-free
  cores already appear in prior training, mostly synthetic templates.
- Synthetic template excess dropped 2,158 rows at a cap of 4 per core.
  Train keeps 906 distinct synthetic cores.
- MASSIVE intent rejoin is unresolved. The datasets-server returns 500 for
  that script dataset and the S3 tarball was not pulled. MASSIVE pool rows
  stay `needs_label` inputs with no gold and no eval use.
- SQuAD fetches hit HTTP 429 twice. One build used the local sample fallback
  (5 rows). The frozen dev file carries the successful 150-row pull; cal-fit
  carries only the 5-row fallback slice. Both facts are in
  `data_manifest.json` notes.
- A full 15,250-row CLINC train pull hit HTTP 429. The builder caps that pull
  at 3,000 rows and reuses the same code path for larger pulls.
- ShortcutsBench was inspected through its GitHub API and README only
  (Apache-2.0 repo, 88 apps, 1,414 APIs, 7,628 shortcuts). Its queries are
  machine-generated and the shortcut rights chain runs through gallery sites.
  No shortcut was downloaded or executed and no rows were imported.

## Coverage (groups, not rows)

Train groups by type: route 2,628; toolChoice 484; answerability 391;
nudgeNow 268; contactPick 14; timing 6. Zero new groups: eventPick,
rememberOrNot, memoryConflict, notificationTriage, confirmBeforeAct,
sensitivity, skillPick. Dev and cal-fit cover route and answerability only.
Report covers route (831 groups) and skillPick (59 groups). Every other
category is NOT MEASURED until labels or fixtures exist. The ~8k target was
not met because independent groups, not rows, justify scale: 3,789 groups is
the honest tranche.

## Layered action schema (choice is not success)

- L1 choice (`graders.grade_choice`): route, tool, or skill selection.
- L2 slots (`graders.grade_slots`): exact argument binding. Timezone and
  contact-method are explicit fixture keys and fail like any other slot.
- L3 feasibility (`graders.grade_feasibility`): permission, confirmation,
  and offline expectations from the fixture contract.
- L4 outcome (`graders.grade_outcome` + `FakeExecutor`): committed effect
  match, no effect on refusal, and recovery after a transient failure.
  These are simulated effects. They never claim EventKit, Contacts,
  Messages, or Shortcuts delivery. Real behaviour stays covered by the
  existing PocketCore contract tests; the parent contract manifest in
  `eval/action_contracts/` will supply per-action fixtures into this frame.

Unrepresented action families are listed in `eval/round3/graders.py`
(`ALL_FAMILIES`). Handoff families (Shortcuts, URL schemes, social DMs) have
no outcome proof by construction. Any family under 30 deterministic groups
reports NOT MEASURED. No gold or threshold was invented to fill a slot.

## The one frozen gate (replaces 'zero errors OR optimized bound')

That wording is void for new candidates. Promotion requires all of: report
handled-group Wilson upper bound below 0.10 with at least 135 handled groups;
handled share at least 0.35; no measured L2/L3/L4 regression versus the paired
baseline; sub-threshold categories reported NOT MEASURED. Threshold fitting
uses cal-fit only. Zero errors on a small set establishes nothing: 0/64 still
allows an upper bound near 0.10 before selection effects. Full text in
`eval/round3/protocol.json`, including two fresh server starts with a warm
pass each, paired AB/BA order, identical flags, report-once discipline, and
CLINC OOS proxy caveats (correlated renderings, group-collapsed intervals).

## iPhone sources: what exists and what does not

Apple App Intents, EventKit, and Contacts documentation was verified reachable
over HTTPS on 2026-11-04. Those pages are specifications. They justify schema
assertions (required arguments, permission and confirmation expectations),
never user-interaction gold. No downloadable, permissively licensed set of
real iPhone user traces with Pocket-style contact or event candidates was
found. Android traces were not used as iPhone evidence. ConfAIde and BFCL
irrelevance stay eval-only; BFCL contributes the deterministic
`no_tool_call` abstention contract (240 report groups).

## Validation

Run: `python3 training/round3/data_validate.py && python3 eval/round3/validate_benchmark.py`
Observed: real manifests pass; overlap, missing-label, and corrupt-hash
fixtures fail; `training/round3/data_test_validation.py` runs 7 tests, all pass;
`eval/round3/graders.py` smoke passes. Existing pipeline tests were not modified.

## Limitations

Dev/cal-fit/report Pocket letters are mostly `needs_label`. Until the parent
freezes Meta-teacher labels for them, only the deterministic categories
(answerability proxy, BFCL abstention, skill routing) can be scored. Phone
latency, memory, thermal behaviour, and on-device delivery remain NOT
MEASURED. SGD, MultiWOZ, Dolly, and SNLI transforms are retained in the
builder and source manifest but were not fetched in this bounded tranche.
