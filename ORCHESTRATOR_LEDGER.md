# Orchestrator handoff ledger

Updated 2026-11-04T19:38:53+00:00 during parent run 60. Parent T3 thread `4311f30f-96dc-4e78-9f19-860e3bbea796`.
This file owns the current handoff. Older entries in `LEDGER.md` and `NEXT_AGENT.md` are historical snapshots.

## Current objective and authorization

Finish the Meta-model iPhone assistant and its verification. The user has now explicitly reopened
training and authorized using the remaining Modal and Baseten credits to improve the models.
The user also has Muse API credits. Do not interpret the older training freeze as a ban on new
candidate experiments. Keep the current shipping model available until a replacement passes validation.

The user requested this durable ledger so another orchestrator can continue without losing jobs,
spending records, decisions, or unfinished app work. Push completed work to GitHub regularly.
Never force-push, expose credentials, or claim a guaranteed hackathon placing.

Follow `/home/habib/.agents/MODEL_SELECTION.md`. The parent chat retains its user-selected settings.
Training-related delegates now use **Muse Code** provider `muse`, model `muse-wonder-1.0`,
with `reasoningEffort=max`. This standing assignment covers training execution, data research,
experiment design, evaluation, and training-related review. The user explicitly replaced the
earlier DeepSeek assignment for these tasks. Existing app/recovery delegates keep their assignments.
Other general delegates use `opencode`, `river02` through `river08` `/deepseek-v4.1-flash-1017`,
with `variant=max`. The user authorized any working River account except the broken unsuffixed
`river` account. Do not substitute models or settings. Agent selection does not change the separately
licensed training-target sources. Runtime and teacher models remain Meta models.

## Verified repository checkpoint

- Recovery was integrated at `1507e36`, the new data tranche at `78e0355`, and
  two-epoch evaluation at `3e5df77`. The Mac packaging repair is `11c07cf`.
- Run 57 preserved the interrupted action-validation and privacy patch, completed
  its artifact export, and reran the current sources. 183 Swift tests passed with
  one opt-in live test skipped. All 84 Mac preparation fixtures and 22 Python
  data/evaluation/grader tests passed. App syntax parsing passed on 18 files.
- `docs/ACTION_VALIDATION.md` describes the implemented limits and remaining gaps.
  `docs/ACTION_CONTRACTS.json` exports 38 compiled contracts, including the
  unavailable app alarm. The bundled registry has 36 skills and now includes
  translation's required target language.
- Shipping model remains ep1 Q4_K_M, SHA-256
  `a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2`.
  The resource check verified its hash, calibration hash, 31 prior sets, registry,
  and entitlements. Shipping threshold remains 0.90.
- R3E2 failed its every-pass diagnostic gate. It is not promoted. Cal180 remains
  selection history, and test120 is report-only. No candidate was selected from
  test120 during this continuation.
- One real text-cloud smoke call passed earlier on source `4bf72c9` through
  PocketCore and Meta Spark 1.3, HTTP 200. Its local decisions were scripted.
  Evidence is `docs/verification/cloud_smoke_2026-11-04.json`. It is not a fresh
  phone test or a verification of every provider, task, or multimodal path.
- User reports the MacBook Air M4 (16GB/256GB), Xcode, iOS SDK 27.2 and Metal Toolchain 27.2 are now available, with the iPhone 17 Pro ready to connect. Current app code remains unbuilt with Xcode.
  Signed install, phone acceptance, phone measurements, demo video, public
  repository visibility, and submission remain open. Submission verification
  returned incomplete because Swift was deliberately checked separately and
  GitHub remains private. It did not report an all-clear.

## Active work and ownership

The recovery and privacy review workers that failed on event-stream reconnection
were replaced in run 48. Their old saved patch is historical recovery material;
do not reapply it over the now-integrated implementation.

| Work | State and next action |
|---|---|
| Durable action recovery and argument validation | Integrated recovery plus the resumed validator patch at `8c990e4`. Versioned contracts, editable drafts, exact contact methods, required local times, external handoff review, and request-bound shared text. Independent review of the combined patch remains required. |
| Busy input preservation | Still open. `AppModel.send` rejects while busy. Request-bound documents fix cross-talk but do not save rejected inputs. Use `docs/research/REQUEST_INPUT_GROUNDING.md` and the accepted Muse findings for durable explicit resume, without automatic replay. |
| Privacy and cloud reliability | Prior independent review found partner-value masking and cancellation bugs. Fixes and regression tests are in the resumed patch, with malformed-settings checks and local fallback. Fresh review pending. |
| Mac packaging | `11c07cf` integrates `18762c3`. Empty executable, missing model, and symlinked framework false passes are repaired. 84 Linux/mock fixtures passed here; no Xcode proof. |
| Glimmer labels | Completed and integrated at `2922acb`. Parent checked all 2,915 source IDs, rendered prompt hashes, option mappings and recomputed probability distributions, plus nine tests. Exact label hash and compressed archive are under `docs/training/evidence/glimmer-r3/`. Live Modal app listing confirms all four batch apps stopped with zero tasks. Teacher is bf16 with mutable `main` revision; keep identity distinct from IQ2_M. No student improvement follows from label completeness. |
| Spark Open labels | Existing Muse worker remains active, observed in run 57. Existing $25 Baseten cap unchanged. The recovered status snapshot records 4,630 settled sampling calls for the 2,915-row batch, with $4.361473 recorded settled usage and $0.031885 retained for unknown calls. The 70 RPM restart is acknowledged; those counts are a snapshot, not completion. Await completion and verify the restart-safe reservation ledger, labels, quality gate, and total known/unknown spend. |
| Phone data and benchmark | `78e0355` integrated source-group splits and protocol. Grader fixes at `74f2341` reject inexact slots, unconfirmed execution, empty traces, and duplicate effects. 22 Python checks pass. Enough labeled independent groups and actual model evaluation remain pending. |
| Expanded phone-specific training | User expanded the active phone worker to a $100 Modal total cap, replacing $35, including evaluation. A new $54.99 Baseten phone-expansion allocation shares the verified request quota with the existing $25 batch. Existing phone owner remains active; the separate Spark phone-expansion task was dispatched in run 60. Both must use the compiled contract manifest, preserve held-out groups, and exchange immutable inputs/labels for paired experiments. Quota partition is 70 RPM for the existing matched batch and 25 RPM for the new expansion; the transition acknowledgment is archived under docs/training/evidence/spark-r3/. |
| R3E2 two-epoch evaluation | `3e5df77` integrated the evaluation. Failed every-pass gate, no promotion, no paid evaluation and no test120 use. |
| Late links | Assessment completed in run 54 and saved at `docs/research/LATE_WEBGPU_KERNEL_REVIEW.md`. No drop-in iOS speedup was established; no model/runtime substitution. |

`docs/training/round3_next_jobs.json` records the six run-48 task IDs and the later
Mac repair. Read it alongside `round3_jobs.json`, which records the earlier pilot.
Run 57 added phone-training execution, contract/privacy/trail review, and comment review.
Their IDs and user-selected targets are recorded there and in `docs/training/run57_dispatches.json`.
Phone training uses Muse Wonder max with the user-expanded $100 Modal allocation. Contract review uses
River08 and comment review River03, both DeepSeek V4.1 Flash 1017 at max.
Independent review is pending, so this checkpoint is not declared release-ready.
Follow a delegate's `next`; do not poll running delegates. Review source and actual
artifacts before integrating. A passing core suite cannot prove phone behavior.

## Throughput checkpoint for this continuation

- Blocking first steps. Recover active writers and prior decisions before edits;
  verify the interrupted patch before creating a checkpoint for follow-up work.
- Independent workstreams. Existing Glimmer and Spark workers keep their separate
  checkouts and allocations. Mac packaging and core integration touch separate files.
- Shared mutable state. The parent alone integrates the main checkout. New writers
  get prepared worktrees. No suite runs inside a worker's checkout from the parent.
- Smallest safe decomposition. One owner must finish input admission across core,
  AppModel, intents, and capture. Correctness review reads the stable checkpoint.

## Spending and credentials

At approximately 17:52 UTC, Modal reported monthly metered usage of $19.92132361, applied credits
of $19.78, and billed cost of $0. This is usage, not the remaining credit balance. Today's app costs
were $17.82792011 for `pg-round2` and $2.09050191 for `pg-glimmer-vllm`.
The only listed deployed app was `pg-glimmer-vllm`, with zero running tasks.

Baseten's billing endpoint returned HTTP 403. The repository's last recorded cumulative spend is
$16.62, not a verified current balance. The user subsequently reported $110 remaining on Modal
and approximately $80–90 remaining on Baseten. Use $110 and the conservative $80 respectively
as the current credit budgets, with reported rather than API-verified provenance.

The pilot's original $5 reservation is closed. The current per-app bill verifies $0.18916778.
The $20 Glimmer allocation is closed at $1.88781456 actual, verified by summing its billing rows. The $25 Baseten matched-label batch remains active.
Spark spending cannot start until per-call reservations and restart safety are implemented and tested.
The user subsequently requested aggressive use of all remaining credits. Phone-specific Modal generation/training/export/evaluation now has a $100 total cap, replacing $35.
Baseten phone expansion has a $54.99 allocation and the one-call rate probe reserves $0.01.
Unallocated planning balances are $7.92301766 Modal and $0 Baseten. Evaluation is funded within the active allocations; the older protected reserves are superseded. These are planning
balances against user reports, not API-confirmed remaining credits.

At the resumed live check, Modal's month summary was $20.10288506 metered and $0 billed.
The child had reported $20.31. Preserve both snapshots; use the per-app report for pilot attribution,
not differences between differently refreshed aggregates. The pilot is stopped with zero tasks.
The existing Glimmer endpoint remains deployed with zero tasks at this check.

Credentials exist locally in `/tmp/gencode/sec/env.sh` and `meta.env`. Never print their contents,
copy them into a report, or commit them. The existing Modal CLI is
`/tmp/gencode/modalenv/bin/modal`. Billing snapshots and current pricing are in
`/tmp/pocket-glimmer-training-scale/`. They contain no API key values.

Meta Model API service terms differ from the open-weight model licenses. Preserve the project's
existing choice to obtain training targets from licensed open-weight teachers, not the Muse API.
Muse API credits remain available for the actual app's cloud features and integration checks.

## Returned review that still needs adjudication

The comment review completed without changing the repository. Its proposed patch is
`/tmp/pocket-glimmer-takeover/resume-comments.patch`, with report `resume-comments.md`.
It names two low-impact redundancies and a benign-input coverage issue: dense Unicode text can
exceed the 48-window screening budget before the 24,000-character cap. That path withholds the
request rather than leaking text. Do not blindly apply every comment deletion or expand the screening
budget before checking the bounded-runtime tradeoff and the pending independent review.

## Resume procedure

1. Read this file, the scaling record, and the last entries in `docs/ORCHESTRATOR_DECISIONS.tsv`.
2. Check `git status`, current commits, and returned T3 completion notifications. Preserve active writers.
3. Read completed reports and verify their claimed artifacts. Never substitute a passing core suite for iOS proof.
4. Record each training job's app ID, candidate name, input hash, exact command, reserved maximum,
   actual usage, terminal state, and artifact hash before starting its successor.
5. Keep data-source groups separate across training, development, calibration fitting, and final reporting.
   Do not train on old gold, stress-test rows, or new held-out groups.
6. Integrate reviewed changes, run appropriate checks, update the ledger, and push the checkpoint.

The canonical decision trail is now `docs/ORCHESTRATOR_DECISIONS.tsv`. The earlier
`/tmp/pocket-glimmer-takeover/decisions.tsv` is an archived predecessor for already-dispatched reviewers.

## Training-agent reassignment checkpoint

At approximately 18:05 UTC, all three DeepSeek scale-up tasks were confirmed interrupted with
no pending child runs. Their worktrees were clean, and no reports or pilot-status artifact had been
written. The pilot activity contains only read-only preflight commands. Modal app listing showed
only the existing `pg-glimmer-vllm` deployment with zero running tasks. No new training job needs takeover.

Preserve the useful pilot discovery: the Modal command must use
`training/round2/modal_round2.py::main`, because the file has several local entrypoints.
The r2c input has 2,915 rows and SHA-256
`afcf82d78426f6a096fbc52774cb654f44faaaac7a3ec97b0cc3953fec7dd3b3`.
The $5 pilot reservation transfers to the Muse replacement; it is not a second allocation.

## Latest scale-up and rate-limit evidence

The user asked to use all remaining credits and increase parallelism. Baseten model-details
GET returned 403, so the parent made one authorized, capped inference call. HTTP 200
headers confirmed 100 requests/minute and 2,000,000 tokens/minute for Spark Open.
These are independent limits. See `docs/verification/baseten_rate_limits_2026-11-04.json`
and https://docs.baseten.co/inference/model-apis/pricing-and-limits. The existing
Spark worker owns its live process and has acknowledged a restart at 70 RPM.
A separate 25 RPM worker was dispatched in run 60 for batched phone-example generation;
it must verify that acknowledgment before paid requests.

The completed Glimmer budget code is not proof of crash-safe reservations: its
exception path does not charge unknown GPU calls. Parent warned the new phone
worker to persist reservations before launch and retain them across failure/restart.
The completed run's actual spend was checked independently; future reuse requires
the stronger accounting contract.

## Run 60 recovery and next integration

Recovered the interrupted run-57 allocations without duplicating the active Modal or
matched Spark workers. The $54.99 Spark phone expansion was reserved but not dispatched
before the interruption; `docs/training/run60_dispatches.json` now records the real task.
It uses the standing Muse Wonder 1.0 max assignment, owns `spark_phone_*`, and writes
raw output/status under `/tmp/pocket-glimmer-training-scale/spark-phone-v1`.
The Modal phone worker was steered to publish frozen input paths/hashes and retain
compute for paired Spark/Glimmer training. No additional Modal allocation was created.

Contract/privacy and comment reviewers were still working at recovery; no replacement
review was launched. Follow completion notifications rather than polling. Next actions:
validate returned artifacts, integrate accepted review repairs, finish the open busy-input
work, and compare exported candidates under the frozen benchmark protocol. All reported
allocations are caps, not money already spent or evidence of a trained improvement.

## Phone worker startup return: not training completion

The phone worker returned while its smoke app `ap-SRyOOiX3TaBGyMUxPobjTS`
was still ephemeral with zero tasks. Parent resumed the same worker with unchanged
Muse Wonder max assignment and unchanged $100 total cap. The updated task ID is in
`round3_next_jobs.json`; there is no second Modal allocation or duplicate smoke.

Parent found pre-integration blockers in the uncommitted phone code and assigned
the owner repairs before further paid launches: non-atomic budget admission, reused
attempt IDs that can erase unknown reservations, resume chunk IDs that skip remaining
labels, parallel GPU settlement using wall time divided by concurrency, unreserved
fallback GPU attempts, and fabricated missing-letter probabilities in GGUF evaluation.
These findings remain OPEN pending corrected code and independent validation.

The first frozen phone split is REJECTED for evaluation. It has disjoint group IDs
but 62 dev rows and 64 calfit rows exactly repeat train decision inputs; 23 calfit
rows repeat dev inputs. Candidate order and option IDs are included in this exact
comparison. An additional wrapper-free screen detects broader related contexts,
which require semantic adjudication because time/network can affect decisions.
Raw frozen splits are archived compressed under `docs/training/evidence/phone-v1-rejected/`.
Reproduce: `python3 eval/round3/audit_phone_splits.py docs/training/evidence/phone-v1-rejected`.
Expected exit: 1, with overlap findings. The audit measures split hygiene only, not
correctness or independence of every scenario. The original 3,115 training rows and
2,070 declared groups are not evidence of 2,070 independent scenarios.

Both phone and Spark expansion owners received the finding. Phone must publish a
new immutable v2 after source grouping repairs. Spark may continue independent
contract-grounded generation and runner work; v1-dependent training generation is
on hold. Preserve any existing paid output by exact prompt hash for safe reuse.
No v1 scores may support model selection or promotion.

## Mac availability and 6 PM demo target

User explicitly clarified the target is installation on their iPhone for the demo,
not TestFlight/App Store distribution. Parent assumes 6 PM Eastern from the existing
timeline; at 19:49 UTC that left about three hours. No build-time promise is made.
The Mac is available but is NOT yet accessible from this Linux session. Device tools
currently list only Linux/Android. Calls to t3_environment_links and
t3_environment_link were unavailable. T3's official current remote-access docs say
to enable Linked environments in Settings > Labs on both hosts, then link the Mac
from curzoh-dev in Settings > Environments > Linked environments. Parent supplied
these steps; user must complete pairing in T3, not paste credentials in chat.

Once accessible, prioritize current-source Xcode build, signing, install, real Metal
startup and core phone flows. Keep training parallel; newly trained candidates need
validation before replacing the existing model. Mac UI/device interaction must use
the provided device tools; connection to a desktop client alone is not proof that
this agent can run on its Mac. Preserve model/provider assignments for any remote
delegate; request a missing remote assignment instead of choosing a substitute.

## Comment review integration

Adjudication is in docs/verification/CONTRACT_COMMENT_REVIEW.md. Parent repaired
false comments, recursive typed grader equality, the manifest-derived action inventory,
benchmark test gating and actor-isolated test counters. Targeted validation passed.
The independent contract/privacy review remains separate and pending.
