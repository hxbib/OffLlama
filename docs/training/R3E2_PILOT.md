# R3E2 pilot. Two epochs on the V4 and r2c recipe

## Verdict

PASS for the training attempt. The single authorized run finished in full and its artifacts verify.

This is not a candidate win and not a promotion decision. The parent owns selection. No test120 run was made. No shipping file changed.

## Hypothesis

Two epochs rather than one improve the strongest prior V4 and r2c candidate.

The prior comparison is `eval/results/ROUND2.md`. V4 on r2c was the strongest prior recipe there. It still failed the old gate on warm repeats. This pilot changes duration only. It does not isolate a data effect.

## Method

Everything except epochs was preserved from the existing pipeline.

- Base model. The cached `unsloth/Llama-3.2-1B-Instruct` weights in volume `pg-round2` under `/vol/base`. The base was already present. `base/DONE` was confirmed before launch.
- Data. `training/round2/out/r2c_train.jsonl`.
- Variant. `V4` in `training/round2/modal_round2.py`. The variant adds `--lr 1e-4` and `--conf-weight` to the `training/round2/lora_r2.py` defaults.
- Preserved settings. Seed 0. LoRA rank 16. Batch size 8. Loss is KL plus 0.5 CE with teacher-confidence weighting. Label smoothing 0. Entropy bonus 0. Target construction in r2c is unchanged.
- Changed setting. Epochs 1 to 2, passed only through `--extra '--epochs 2'`.
- Inference settings. Unchanged. The trainer runs its built-in zeroShot readout on the calibration file. That readout is a diagnostic in the saved JSON. This report does not use it as a headline result.
- Expected steps. `ceil(2915 times 2 divided by 8)` equals 729. The prior one-epoch V4 on r2c ran 365 steps in 81.3 seconds total.

The exact script was used as found. No source file was edited for this pilot.

## Pre-launch record

Recorded before launch in `/tmp/pocket-glimmer-training-scale/duration-pilot-status.json`.

- Timestamp. 2026-11-04T18:08:55Z.
- Candidate. `V4-R3E2-20261104`. Tag `R3E2-20261104`.
- Worktree git SHA. `79e0884b62c6a8c465443047c9113b95c5af62bc`. The tree was clean.
- Input rows. 2915.
- Input SHA-256. `afcf82d78426f6a096fbc52774cb654f44faaaac7a3ec97b0cc3953fec7dd3b3`.
- Command. `/tmp/gencode/modalenv/bin/modal run training/round2/modal_round2.py::main --train training/round2/out/r2c_train.jsonl --variants V4 --tag R3E2-20261104 --no-cpu --extra '--epochs 2'`
- Credentials. Sourced from the local credential file with shell tracing off. No secret value appears in the command, this report, or the status file.
- GPU request list in code. `H100` then `A100-80GB`. GPU function timeout is 1500 seconds.
- Rates checked live before launch. H100 at 3.95 dollars per hour. A100-80GB at 2.50 dollars per hour.
- Reservation. 5 dollars on Modal. No Baseten spend. No Muse API spend.
- Projected maximum. 1.65 dollars. The bound is the timeout-capped worst case for one GPU function. `1500 divided by 3600 times 3.95` equals about 1.65 dollars. One variant and one function call were authorized. No retry sweep and no CPU fallback were authorized.
- Read-only preflight. Billing showed metered cost 19.92 dollars and billed cost 0 dollars. The only deployed app was `pg-glimmer-vllm` with zero tasks. Volume `pg-round2` listed `base`, `gguf`, `lora`, and `logs`. No prior `V4-R3E2-20261104` artifact existed.

## Run record

- Modal app ID. `ap-FvDrvwYplrjYFYMOfI4SVH`.
- App state after the run. Stopped. Created 18:09 UTC and stopped 18:12 UTC with zero tasks. The `pg-glimmer-vllm` deployment was not touched.
- Actual hardware. `NVIDIA H100 80GB HBM3`.
- Sweep wall time. 169 seconds.
- Function total time. 148.3 seconds.
- Training field time. 115.6 seconds. Inner training loop time was 102.32 seconds.
- Container steps. All five steps returned code 0. Train 115.5 seconds. Merge 13.0 seconds. GGUF convert 9.8 seconds. Quantize 7.5 seconds. Adapter copy 0.2 seconds.
- Isolated logs. `/tmp/pocket-glimmer-training-scale/duration-pilot/modal-run.log` and the saved modal JSON copy in the same directory.
- Volume outputs. `/vol/gguf/V4-R3E2-20261104.gguf`, `/vol/lora/V4-R3E2-20261104/`, and `/vol/logs/V4-R3E2-20261104.json`. No round-2 artifact was overwritten. Writes used only the new candidate prefix.

## Verification

Each check below ran against the real artifacts after the run.

- Full steps. `train_rows` is 2915. `steps` is 729. `steps_done` is 729. The counts match the 2-epoch plan.
- Abort flag. The trainer only sets `aborted` on its early-stop path. No `aborted` key is present in `train_result`. Steps are complete and every container step returned 0. This is not a saved partial model. A partial run would not count as a candidate.
- Recipe match. Saved args show epochs 2.0, lr 0.0001, rank 16, ce-weight 0.5, and conf-weight true. Flags are `--lr 1e-4`, `--conf-weight`, and `--epochs 2`. Only epochs differ from the prior V4 run.
- Prior run compare. The prior `V4-gpuC` JSON shows 365 steps and 51.7 seconds of train field time on the same H100 type. Doubling steps roughly doubled inner training time. The limiter is GPU training time. Merge and quantize add about 30 seconds and do not scale with epochs.
- GGUF hash. The downloaded file hashes to `90af88d44f4a2dae0bfad0803a4d14ed12aa7397d421380dee9e64a3606d837c`. Size is 807694048 bytes. The value matches the volume log and the local modal JSON.
- Adapter. `adapter_model.safetensors` hashes to `36c9100283a065d9cbd0a1a70f4847579698cf984886fd076686d7bb20d6cd13`. The adapter directory also holds `adapter_config.json` and `eval_before_after.json`.
- Local downloads. Only this candidate was downloaded. Files sit in `training/round2/out/R3E2-20261104/` in this worktree. The GGUF matches the `*.gguf` ignore rule. Adapters match the `**/adapters/` ignore rule. The two JSON logs in that directory are untracked local evidence and were not committed.
- Shipping safety. Git status after training showed only the untracked candidate output directory. Shipping GGUF, priors, tau, prompt, and test120 were not touched.
- Evaluation limits. `docs/EVALUATION_CLAIMS.md` governs claims. Cal180 was reused for prior model selection. Nominal bounds on cal180 are not guarantees. This report makes no bound claim and no test120 claim.

## Accounting

- Reserved. 5.00 dollars on Modal.
- Actual attributable cost. 0.19 dollars. The Modal billing report for today lists four rows for `ap-FvDrvwYplrjYFYMOfI4SVH`. H100 0.183965 dollars. CPU 0.00313685 dollars. Memory 0.00050449 dollars. Network egress 0.00156144 dollars. The sum is 0.18916778 dollars.
- Billed cost after the run. 0 dollars. Metered cost rose from 19.92 to 20.31 dollars across all workspace activity. The per-app rows above are the attributable figure for this pilot.
- Unused reservation. About 4.81 dollars of the 5-dollar cap was not spent. No second candidate was launched. No automatic retry ran.
- Other providers. Baseten spend was zero. Muse API spend was zero. No new training examples or labels were created. No non-Meta model supplied training content.

## Gaps

- Budget enforcement. The training script has no dollar cap. The bound in this pilot came from procedure, not code. One variant, one call, GPU mode only, and a 1500-second function timeout kept the worst case under the cap. Billing is visible only after the run. A larger run needs an enforced reservation before launch.
- Abort trap. The trainer saves a model even when it aborts early. The saved `ok` flag covers the full export path, not step completion. Any future run must check `steps_done` against `steps` and the absence of `aborted` before treating the GGUF as a candidate. This pilot passed that check.
- Early-stop horizon. The trainer checks projected hours only at step 5 against a 1.2-hour budget. A slow start on different hardware could still waste the full timeout. The timeout, not the trainer check, is the hard bound.
- Hardware pinning. Code requests a list, not one GPU. Modal chose H100 here. A future run could land on A100-80GB and run slower. Reports must keep recording actual hardware.
- Reproducibility. Seed and shuffle are fixed. GPU kernels and server state still vary. Prior round-2 repeats showed fresh and warm differences. The image pins the llama.cpp revision and package versions. The base weights come from a mutable volume cache marked only by `base/DONE`. The exact input hash and output hash in this report are the durable anchor.
- Local evidence. The modal JSON logs are untracked in the worktree. The volume log holds the same fields. The GGUF hash lets the parent verify any later copy without trusting this report.

## Handoff

The candidate GGUF is ready for the parent frozen comparison harness. This pilot ran no calibration fit, no candidate evaluation on test120, and no app promotion. The parent should evaluate `V4-R3E2-20261104` only under its independently frozen harness and criteria.

Dispatch note. This delegate ran in-thread as Muse Code `muse/muse-wonder-1.0` with max reasoning effort per the user assignment. No subagent was spawned. No model or setting was changed.
