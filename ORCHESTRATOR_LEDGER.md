# Orchestrator handoff ledger

Updated 2026-11-04 during the resumed run at 18:45 UTC. Parent T3 thread `4311f30f-96dc-4e78-9f19-860e3bbea796`.
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

- Privacy and Mac preparation repairs are integrated through `4b92321`. Training reassignment was pushed at `f22e38d`; the completed pilot report was integrated at `eb4ea4e`. Subsequent resume evidence and allocations are recorded below and in `docs/ORCHESTRATOR_DECISIONS.tsv`.
- Prior integrated verification ran 136 Swift tests, one skipped, zero failures. The Mac preparation
  fixtures passed 73 checks. These checks do not establish an Xcode build or phone behavior.
- Shipping model remains ep1 Q4_K_M, SHA-256 `a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2`.
- Shipping threshold is 0.90. Keep shipped priors, prompt templates, and weights unchanged during experiments.
- `docs/EVALUATION_CLAIMS.md` supersedes historical claims of a 10.2% certificate. Cal180 was reused
  for model selection. Test120 is report-only, not a tuning set. Do not rerun it for candidate selection.
- The user said the Mac is unavailable. Current iOS source remains unbuilt. Signed install,
  device acceptance, phone measurements, demo video, repository visibility, and submission remain open.

## Active work and ownership

Both existing OpenCode workers failed on event stream reconnection during the resumed run.
`task_cancel` and terminal status confirmed no pending child runs. Preserve their checkouts.
The recovery patch and new files are saved at `/tmp/pocket-glimmer-takeover/recovery-resume/`.
Its manifest records hashes and the original `009430f` base. Do not merge this unfinished patch
without preserving the newer privacy code and testing the integrated result.

| Work | State and next action |
|---|---|
| Durable action recovery, editable drafts, email routing, memory recall, cloud result provenance | Resume the saved patch with the same River07 assignment. Old checkout `/home/habib/.t3/worktrees/pocket-glimmer/t3-7b160d24`. The worker had 144 tests, one skipped, and four assertions failing on two already-known privacy cases in its old base. Merge the current privacy implementation and rerun. No iOS build claim. |
| Independent privacy and Mac review | Resume with the same River08 assignment. Logs under `/tmp/pocket-glimmer-takeover/resumed-review/` show 136 tests with one skip and no failures, plus 73 Mac fixtures passing. No final independent verdict was written, so review is still open. |
| Request-bound shared input | Investigation archived at `docs/research/REQUEST_INPUT_GROUNDING.md`. Global inbox ownership is unsafe. Apply the repair after recovery integration; do not reorder the global inbox write as a shortcut. |
| Two-epoch training pilot | Complete, artifact and bill checked. `docs/training/R3E2_PILOT.md` and `docs/training/evidence/` preserve evidence. No promotion. |
| Both-teacher scale-up and stronger benchmarks | Execution contract at `docs/training/ROUND3_EXECUTION.md`. Muse Wonder max remains assigned. Next task IDs will be appended to `docs/training/round3_jobs.json`. |
| Handoff, spend reservations, integration | Parent owns this ledger, current job records, and the canonical decision trail. |

Follow a delegate's `next`. Completion wakes the parent. Do not poll running delegates. A result
is not integrated merely because a child says it is finished. Resume tasks must receive consolidated
original requirements and later corrections, not only the original brief.

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
A new $20 Modal allocation funds Glimmer labeling, and $25 Baseten funds bounded Spark Open labeling.
Spark spending cannot start until per-call reservations and restart safety are implemented and tested.
Remaining planning balances after these reservations are $89.81083222 Modal and $55 Baseten.
Of those, protect $15 Modal and $20 Baseten for evaluation and integration. These are planning
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
