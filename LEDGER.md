# Pocket Glimmer: LEDGER (chronological project record and handoff)

Last written: Sun Nov 1 2026, ~8 PM ET. **Append to this file at every milestone** (see scripts/BACKUP.md).
Every number below cites its source file or commit. If a number has no source, it is not in this file.

## 0. Measurement protocol (read first)
- Headline numbers come ONLY from the frozen test split `eval/gold/gold_test.jsonl` (N=120, 10 per type, 12 types). It is frozen: never tune, select or augment on it.
- Model/prompt/threshold selection uses ONLY the calibration split `eval/gold/gold_calibration.jsonl` (N=180). Gold set: 300 hand-labeled items, 25/type, labeling rules in commit a297c83.
- Pipeline: `eval/experiments/run_prompt_variants.py`, variant **v2+cc** (prompt v2 + contextual calibration), served by llama-server; `training/reliability.py` (10-bin ECE); `pg_train.conformal` (Learn-Then-Test, alpha 0.05, delta 0.1, exact binomial, Bonferroni over a fixed grid). "Handled" = confidence ≥ τ (default τ=0.8).
- `lora_cpu.py`'s built-in score uses the zeroShot prompt and is NOT comparable to the v2+cc headline (WATCHDOG_NOTES 08:12).
- Augmented/generated data never goes near test120, and cannot be used to certify a conformal bound.
- One test item = 0.83 pts; 95% CI on 0.82 is about ±7 pts (docs/research/IMPROVEMENT_PLAN_NOV1.md). Do not claim small gains.

## 1. Project and architecture
Pocket Glimmer: an on-device iPhone assistant that makes small decisions locally and escalates only when unsure.
- **System 1, Llama-Reflex-1B** ("Jev-style" reflex; Jev by TypeSafe AI is a comparison point only, no affiliation): Llama 3.2 1B Instruct, LoRA r=16 distilled from **Muse Glimmer 30B IQ2_M** soft option-letter labels (llama-server letter logprobs), merged and quantized to an **808 MB Q4_K_M GGUF** (`Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf`, sha256 a5c60a88…82c2, /workspace/mac-day/SHA256SUMS) run with llama.cpp (pinned ddf48f8 xcframework, commit d75cfd5).
- **System 2**: Muse Spark 1.3 via the Meta Model API, Standard mode. Escalation when System 1 confidence < τ (conformal / LTT, commits d5513ea, e5ffa88). Masked-prompt privacy sheet, sensitivity withholding ("Kept on device · nothing sent" badge, commit 35d619d, NOT yet compiled).
- **Memory**: SQLite with CURATOR-style provenance, trust-ordered eviction, user corrections as retrievable rows (be88e25).
- **Actions**: EventKit, Contacts, Shortcuts, App Intents (81cb380). Swift package PocketCore (93edfab), pg-cli (180c197).
- Why 1B not 3B: 3B leaves ~0.47 GB headroom on phone (d2eb9db); gate-1 measurements in /workspace/gate1/RESULTS.md and README (a97c290).

## 2. Deadlines
- Submission: **Wed Nov 4, 9:00 PM ET** (CV platform, 3-min video, PUBLIC GitHub repo, check logged-out view). Repo is private until submission day.
- Demo video recorded by **Tue Nov 3**.
- Retrain cutoff: **Tue Nov 3 noon ET** (if a new model isn't selected by then, record with the current one).
- Later: judging Nov 5–8, finals Nov 9 noon ET, community vote Nov 16, Most-Viral X engagement until Nov 8 11:59 PM ET.

## 3. Rubric and banned/overdone list (source: /workspace/kickoff/summary.md, also handoff/kickoff/)
| Criterion | Weight |
|---|---|
| Impact (real-world potential, fit with a problem statement) | 30% |
| Use of Meta AI tooling (creative, beyond basic integration) | 25% |
| Technical depth | 20% |
| Demo (working, video worth watching) | 25% |
Banned: anything breaking legal/ethical/platform policy or using code/data/assets without rights. Overdone (avoid): AI medical advice (incl. mental-health advisors, skin detectors), basic RAG, simple image analyzers, Streamlit apps, dashboards as main feature, "AI for Education" chatbots, AI job screeners, nutrition coaches, personality analyzers, sports analyzers/coaches, simple chat wrappers. Must show only work done during the event and call out prior work.

## 4. Hard rules
- Only Meta models in the shipped product. Non-Meta models may help build (e.g. write scenarios) but never produce labels.
- test120 frozen; select on cal180 only; augmented data never near test.
- Meta Model API cannot be a teacher: no logprobs, and ToS §10.1(ix).
- No Fireworks, no Supabase, no `trust_remote_code`.
- Do not pitch the Open Weights bonus (no source for it; removed in 52eccd0). Never claim a guaranteed win.
- Secrets never in git. Never force-push or rewrite history.
- Don't disturb the PC's background worker (WSL Ubuntu, GPU), don't touch CurzohDocker/Debian WSL, don't delete on the PC.

## 5. Chronological git log (all 45 commits before this ledger; dates ET)
| Commit | Date | What |
|---|---|---|
| 93edfab | 2026-10-31 | core: PocketCore package (option sets, Reflex, calibration, SQLite memory, proactive rules, cloud brains, scrubber, telemetry) + 30 tests |
| 180c197 | 2026-10-31 | core: pg-cli with llama-server e2e decision suite |
| 9630cd5 | 2026-10-31 | training: seeded scenarios, teachers w/ spend guard, disagreement->escalate merge, Unsloth r16 letter-only SFT, calibration, GGUF export, cost estimator, labeled dry run |
| 2ff2f7c | 2026-10-31 | eval: 36 hand-labeled gold decisions, decision scorer (acc/ECE/coverage), System 2 Q&A runner; untrained 1B baseline |
| 81cb380 | 2026-10-31 | app: SwiftUI iOS app (llama.cpp engine, EventKit/Contacts/Shortcuts actions, App Intents, Reflex chart, memory, settings) + XcodeGen spec |
| 4369f7c | 2026-10-31 | docs: README with architecture diagram and measured baseline, MIT LICENSE, 3-minute demo script |
| 86107c7 | 2026-10-31 | docs: mark demo numbers as placeholders |
| 03ba605 | 2026-10-31 | providers: verified Meta Model API/Fireworks/Baseten/Modal ids, prices, logprob support; sample-vote teachers where logprobs unavailable; license + rules notes; Llama naming for exported student |
| d5513ea | 2026-10-31 | core: conformal risk control for tau (Learn-Then-Test, exact binomial / Clopper-Pearson, Bonferroni over fixed grid) + 6 tests |
| 749a29e | 2026-10-31 | training: conformal tau recalibration script (+test), run on untrained 1B gold baseline |
| 16ff101 | 2026-10-31 | training: wrap conformal test in TestCase |
| dc160af | 2026-10-31 | Add demo script, submission skeleton, launch checklist, reliability/ECE script + baseline chart |
| 3b08f2f | 2026-10-31 | systemone: align notes with llama.cpp #29818, upstream confidence formula in core, Laya/Julia-1 benchmark on gold |
| 7a66cb2 | 2026-10-31 | docs: LICENSING.md with exact Muse Model License + Llama 3.2 clauses, NOTICE; drop unsourced $10K prize line |
| 949913a | 2026-10-31 | Merge rubric map into submission packet + checklist; add UI TODO to demo script |
| e5ffa88 | 2026-10-31 | conformal: report tightest supported bound + min self-handled rows for target alpha (Swift + Python) |
| b401944 | 2026-10-31 | reflex: debias untrained 1B without training (sharper labels, few-shot exemplars, contextual calibration priors via pg-cli priors); app engine hardening, cancel action, Built with Llama |
| be88e25 | 2026-10-31 | memory: CURATOR-style provenance column (+migration), trust-ordered eviction budget, user corrections as retrievable rows feeding Reflex context; 3 tests |
| a97c290 | 2026-10-31 | README: Meta stack table + why not 30B on phone (gate1 measurements) |
| 52eccd0 | 2026-10-31 | docs: remove unsourced open-weights bonus mention |
| a297c83 | 2026-10-31 | eval: 300 hand-labeled gold decisions (25/type) with written labeling rules; stratified 180 calibration / 120 test split |
| 1c0d1de | 2026-10-31 | docs: Built with Llama / Muse Spark Open attribution, Llama-Reflex-1B naming, four Meta roles, SystemOne comparison, frozen-test-split headline rule |
| 32ec3ee | 2026-10-31 | training/local_teacher: free local Glimmer IQ2_M teacher (llama-server letter logprobs), eval dedupe guard, resumable labeler, QC scorer, CPU LoRA distill |
| 0110b3a | 2026-10-31 | app: decision cards (type→choice, conf vs τ, ms, expandable dist + tool-call JSON), orange-below-τ bar, Corrected-by-you memory section, Meta escalation badge + masked-prompt privacy sheet, per-round telemetry chart; core: turn.action/cloudPromptSent/corrections, shareByModel; tick DEMO_SCRIPT UI TODOs |
| 6bf3f88 | 2026-10-31 | eval: frozen test120 before/after for prompt-only debiasing |
| 3ed3d76 | 2026-10-31 | eval: untrained Llama 3.2 1B baseline on frozen test (N=120) + calibration split (N=180), conformal from calib, docs before-row |
| e38f773 | 2026-10-31 | distill: drop low-confidence teacher labels on QC-shaky types |
| d75cfd5 | 2026-11-01 | ios: compile-readiness pass (SWIFT_VERSION 5.0, free-team entitlements, Files sharing for .gguf, pinned llama.cpp ddf48f8 xcframework, PGPERF ttft/tok/s logging) + MAC_DAY_RUNBOOK |
| d2eb9db | 2026-11-01 | docs: lock on-device model to Llama 3.2 1B (3B leaves ~0.47 GB headroom), gate-1 lineup (box-CPU figures labeled), baseline 74%/89%/ECE 0.101 with [AFTER_*]/[PHONE_*] placeholders, demo steered to answerability/confirm/memory-conflict with shaky types only as Spark 1.3 hand-off |
| fe7a2cd | 2026-11-01 | training/review: 20 shaky-type teacher labels (contactPick, eventPick, notificationTriage, nudgeNow, rememberOrNot; conf 0.5–0.8 preferred) for a 10-minute hand review |
| e5ddace | 2026-11-01 | docs: correct baseline ECE to 0.150 (v2+cc frozen test N=120, training/reliability.py); 0.101 was an early N=36 run; add reliability chart |
| b6a7a12 | 2026-11-01 | training: fix lora_cpu eval path crash (resolve before relative_to); add memory-gated rerun_lora.sh |
| 882b6ee | 2026-11-01 | training: low-memory LoRA floor options (--dtype bf16, --micro grad accumulation, --grad-ckpt) + rerun_lora_floor.sh; defaults unchanged |
| 4876d34 | 2026-11-01 | eval: after-distillation floor run on frozen v2+cc test120 (acc 0.74->0.82, ECE 0.150->0.064, handled@0.8 0.15->0.51); after-eval chain + export tokenizer fallback |
| 2b2eb77 | 2026-11-01 | eval: 2-epoch floor LoRA vs 1-epoch on cal180/test120 (ep2 more confident, not more correct; keep ep1) |
| 7f16491 | 2026-11-01 | training: nudgeNow v2 scenario generator (message/email/time/charger triggers + 'later' cases; v1 output unchanged) after root-causing nudgeNow 3/10 to generator coverage |
| 95b3e1e | 2026-11-01 | training: run_nudge_v2.sh chain (dedupe -> RAM-gated Glimmer labels -> rebuild -> floor LoRA -> matched v2+cc eval as floor_nv2) |
| 43f3186 | 2026-11-01 | backup: tighten .gitignore, add handoff/ (mac-day, kickoff), latest eval/teacher outputs |
| 8e0e1ca | 2026-11-01 | scripts: GitHub backup script and procedure |
| d9c4d12 | 2026-11-01 | scripts: simplify no-op check |
| cc63432 | 2026-11-01 | scripts: BACKUP.md CopyFromBox path note |
| 861e088 | 2026-11-01 | docs: honesty fixes (Glimmer-only teacher, no Fireworks/non-Meta, ~10% certified conformal bound, current eval counts); add per-type shipping results |
| c0f4106 | 2026-11-01 | scripts: record bundled head for incremental base |
| 4b704a7 | 2026-11-01 | Demo script: replace memory-conflict beat with sensitivity decision; align task types with per-type shipping results |
| 35d619d | 2026-11-01 | Show 'Kept on device · nothing sent' badge when cloud is withheld for sensitivity |

Note: the brief referenced commits `adff22b` / `9023872` for the shipping run. `adff22b` exists only as `.git/ORIG_HEAD` (a pre-rewrite head) and `9023872` was not found; neither is in current history. The shipping-run eval is commit **4876d34**; the adapter itself is in the release (section 9).

## 6. Experiments and results
### 6.1 Headline table, frozen test120, v2+cc
| Run | Acc | Handled @τ0.8 | Acc on handled | ECE | Source |
|---|---|---|---|---|---|
| Baseline untrained Llama 3.2 1B | 0.74 | 0.15 | 0.89 | 0.150 | eval/results/AFTER_FLOOR.md, commit e5ddace (0.101 was an early N=36 run) |
| **Floor LoRA 1 epoch (SHIPPING)** | **0.82** (98/120) | **0.51** (61/120) | **0.92** (56/61) | **0.064** | eval/results/AFTER_FLOOR.md, 4876d34 |
| LoRA 2 epochs (REJECTED) | 0.81 | 0.61 | 0.92 | 0.076 | eval/results/AFTER_FLOOR_EP2.md, 2b2eb77 |
Median latency per decision on box CPU: 1050 ms before, 141 ms after (indicative only, AFTER_FLOOR.md).
Floor run: 892 Glimmer labels, bf16, micro-batch 2, grad-accum to 8, grad-ckpt, 112 steps, 502 s (AFTER_FLOOR.md).

### 6.2 Calibration split (cal180) and conformal
- Floor ep1: acc 0.78, handled 0.49 @0.8, acc on handled 0.96. Conformal (α 0.05, δ 0.1): **no certified τ** (5% needs 135 handled with 0 errors). Tightest: **τ=0.90, 64/180 (36%) handled, 0 errors, bound 10.2%** (eval/results/after_floor.conformal.txt).
- Baseline tightest: τ 0.64, 29%, 3 errors, bound 22.4% (AFTER_FLOOR.md).
- Ep2: acc on handled 0.96→**0.90**, tightest τ 0.96, 25% handled, bound **14.2%** → rejected; "more confident, not more correct" (AFTER_FLOOR_EP2.md).

### 6.3 Per type, shipping ep1, test120 (eval/results/PER_TYPE_SHIPPING.md, report only)
| Type | Acc | Handled @0.8 | Acc on handled |
|---|---|---|---|
| answerability | 9/10 | 5/10 | 5/5 |
| confirmBeforeAct | 10/10 | 6/10 | 6/6 |
| contactPick | 9/10 | 9/10 | 8/9 |
| eventPick | 9/10 | 9/10 | 8/9 |
| memoryConflict | 9/10 | 1/10 | 1/1 |
| notificationTriage | 8/10 | 4/10 | 3/4 |
| **nudgeNow** | **3/10** | 0/10 | n/a |
| rememberOrNot | 7/10 | 1/10 | 1/1 |
| route | 8/10 | 7/10 | 7/7 |
| sensitivity | 10/10 | 7/10 | 7/7 |
| timing | 8/10 | 5/10 | 4/5 |
| toolChoice | 8/10 | 7/10 | 6/7 |
Ep2 vs ep1 per type: rememberOrNot 5 vs 7, memoryConflict 10 vs 9, nudgeNow 3 both (AFTER_FLOOR_EP2.md).

### 6.4 Other measured items
- Prompt-only debiasing of the untrained 1B (sharper labels, few-shot, contextual-calibration priors): b401944, 6bf3f88; results in eval/experiments/test120_results.json.
- Untrained 1B fewShot test acc 0.733; zeroShot 0.675 (training/local_teacher/out/lora-llama1b-glimmer/eval_before_after.json, WATCHDOG_NOTES).
- lora_cpu.py HF bf16 zeroShot readout 0.558→0.825 (not headline; AFTER_FLOOR.md).
- Laya and Julia-1 (SystemOne comparison, Q8_0) on gold: eval/results/laya-q8_0.json, julia-1-q8_0.json, conformal_*.json (3b08f2f).
- Teacher labeling (box CPU, Glimmer IQ2_M): stopped at deadline with 1,006 labels (73 items/h, server peak RSS 12.6 GB); build_train kept **892** (dropped 114 low-confidence: nudgeNow 47, contactPick 32, rememberOrNot 15, route 9, eventPick 9, notificationTriage 2) (WATCHDOG_NOTES 08:12; e38f773).
- fp32 CPU LoRA: OOM-killed 11:11 rc 137 → replaced by bf16 floor run (WATCHDOG_NOTES 12:20; 882b6ee).
- nudgeNow root cause: train generator only emitted "arrive at store" nudges and **0 "later"** cases; of 76 raw teacher nudgeNow labels 0 were confident "later" (WATCHDOG_NOTES 16:10; 7f16491). Every nudgeNow prediction has conf < 0.8, so it always defers to Spark rather than ships wrong.
- 20 shaky-type teacher labels prepared for a 10-min hand review (fe7a2cd; training/review/).

## 7. In-flight work (as of ~8 PM ET Nov 1)
- **nudge_v2 relabel on the box**: run_nudge_v2.sh is RUNNING (llama-server Glimmer IQ2_M on :8091, label_local.py writing out/nv2/nv2_labels.jsonl). 300 scenarios (143 skip / 91 nudge / 66 later), 0 dropped by dedupe vs 636 eval items. Chain: label → rebuild train → floor LoRA 1 epoch → v2+cc eval as `floor_nv2`. Gives up at 2026-11-02 12:00 (out/nv2/GAVE_UP). A snapshot of nv2 files was committed; the run is not finished.
- **PC GPU path** (another worker): WSL Ubuntu-24.04 install on C:, training/local_teacher/lora_gpu.py, run_nudge_v2_gpu.sh, gpu_eval.sh; /workspace/xfer holds the transfer kit (adapter.tar, basecfg.tar, q4.* split GGUF, pg_code.tgz, pg_data.tgz, setup*.sh).
- **Temperature scaling + LTT rerun**: training/temp_scale.py (single T fit on cal180, then LTT; report T-scaled ECE on test120 once). Not yet reported.
- **Q4_K_M Glimmer relabel on the PC** (higher-precision teacher, partial offload, benchmark 20 items first; IMPROVEMENT_PLAN #4).
- **Next**: Muse Spark Open as teacher via Baseten or Modal credits, pending (a) license check for distillation and (b) confirming the endpoint returns logprobs.
- **iPhone build** (phone arriving; Mac connected with gh; docs/MAC_DAY_RUNBOOK / handoff/mac-day), compile 35d619d badge, record video, fill placeholders.

## 8. Open TODOs / placeholders
- `[AFTER_*]` in docs/SUBMISSION.md and docs/DEMO_SCRIPT.md (ACC, COVERAGE, ACC_HANDLED, ECE, TAU, BOUND, RELIABILITY_CHART, ROUND_SHARES): values exist in section 6 for ep1, but Habib must sign off before filling (and refill if nv2 wins).
- `[PHONE_*]` (TTFT_MS, TOK_S, RAM_GB): need on-device measurement.
- "892 labels" text: will change if the nv2 retrain ships (892 + new nv2 labels).
- Make repo public on submission day; check in a logged-out browser.

## 9. Habib's pending decisions
- Sign-off on AFTER numbers in SUBMISSION/DEMO_SCRIPT.
- Whether to swap in an nv2 / refreshed-label model (only if cal180 improves and phone smoke test passes, before Nov 3 noon).
- Spark Open teacher spend on Baseten/Modal (after license + logprob check).
- 10-minute hand review of 20 shaky teacher labels (training/review/).
- Which bonus prizes to flag (not Open Weights pitch).

## 10. Infrastructure
- **Box** (Linux, shared by all agents): repo /workspace/pocket-glimmer; llama.cpp + Glimmer GGUFs in /workspace/gate1; LoRA venv /workspace/pg-lora-venv (base HF weights at pg-lora-venv/llama32-1b-instruct); kickoff capture /workspace/kickoff; hackathon rules /workspace/meta-hackathon; research /workspace/research, /workspace/pocket-glimmer-research, /workspace/papers. CPU-only, RAM gated by a host balloon (frequent pauses).
- **PC** (Windows, machineId 42c228be-…2a): RTX 3080 Ti 12 GB, 32 GB RAM, WSL Ubuntu-24.04 being installed on C:, gh logged in as hxbib, clone C:\src\pocket-glimmer.
- **Mac**: connected, has gh; for Xcode build. **iPhone**: arriving.
- **Hourly watchdog routine**: appends to training/local_teacher/out/WATCHDOG_NOTES.md.
- **Backup**: scripts/BACKUP.md + scripts/backup_push.sh (bundle on box → CopyFromBox → PC push, never force).
- **Credits** (Habib authorized spending all on the hackathon): Baseten $100 (Muse Spark Open), Modal $100 (open-weight endpoints, serverless GPUs, training), Meta Model API $150. Keys are box env vars `BASETEN_API_KEY`, `META_API_KEY`, `MODAL_TOKEN_ID`, `MODAL_TOKEN_SECRET`. Values are never recorded.

## 11. Re-downloadable inputs (NOT in releases)
- Muse Glimmer 30B IQ2_M teacher GGUF (9.85 GB, sha256 07c286ac…fa per /workspace/xfer/sha.txt): https://huggingface.co/NANI-Nithin/Muse-Glimmer-30B-GGUF/blob/main/Muse-Glimmer-30B-IQ2_M.gguf (official card: https://huggingface.co/meta-models/Muse-Glimmer-30B).
- Llama 3.2 1B Instruct base (HF safetensors, sha256 1ff795ff…538f): https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct (gated, Llama 3.2 license); ungated mirror used by the PC kit: https://huggingface.co/unsloth/Llama-3.2-1B-Instruct (/workspace/xfer/dl.sh).
- Base Llama 3.2 1B/3B, 3.1 8B Q4_K_M GGUFs used in gate 1: /workspace/gate1/models (public GGUF mirrors; see gate1/dl.log).
- llama.cpp: https://github.com/ggml-org/llama.cpp (Glimmer support since b10353; iOS pinned ddf48f8).

## 12. Rejected and why
| Idea | Why rejected |
|---|---|
| LeCun/JEPA paper as a basis | Not Meta research for this purpose; not used. |
| Qwen, Gemma (or any non-Meta model) in the stack | Only Meta models may ship. |
| Llama 3.2 3B as System 1 | ~0.47 GB phone headroom, 3× train time, new binary; out of scope for time left (d2eb9db, IMPROVEMENT_PLAN). |
| Full fine-tune of 1B | Gains over LoRA show only at larger data; 892 rows already overfit. |
| 2+ epochs | Measured and lost: cal acc-on-handled 0.96→0.90, bound 10.2%→14.2% (AFTER_FLOOR_EP2.md). |
| Vector/matrix scaling | Too many params for 180 cal rows; single-T scaling instead. |
| Speculative decoding | Decisions are 1 token; System 2 is server-side. |
| ARM repack quant (Q4_0_4_x) | CPU-only, doesn't apply on Metal; negligible for 1-token decisions. |
| Mondrian / per-type conformal | Per-type buckets of 180 cal rows are vacuous (≥20% bounds); keep one global LTT. |
| Meta Model API as teacher | No logprobs; ToS §10.1(ix). |
| Fireworks | Excluded by rule (and costs money). |
| Local System 2 | Parked until after the hackathon. |
| Open Weights bonus pitch | No source for it (52eccd0). |
| Augmented data for certification | Not valid: conformal guarantee needs cal rows from the test distribution. |
| MobileMoE in app/demo | License gray zone (docs/PROVIDERS_AND_LICENSES.md). |

## 13. Ideas not yet tried (ranked, from docs/research/IMPROVEMENT_PLAN_NOV1.md)
1. nudge_v2 relabel + retrain (in flight). 2. Temperature scaling (script written, not run/reported). 3. Grammar-constrained single-token readout + cached system-prompt KV on phone. 4. Higher-precision Glimmer quant relabel + option-order permutation averaging. 5. One retrain on refreshed labels (1 epoch, r16 vs r32, KL soft-label loss). 7. Hard-example mining near τ. 9. Grow the calibration set with same-distribution new items (not from test). Also: Spark Open teacher via Baseten/Modal.

## 14. How to resume
```bash
cd /workspace/pocket-glimmer && git log --oneline | head; cat NEXT_AGENT.md
tail -5 training/local_teacher/out/WATCHDOG_NOTES.md; tail -20 training/local_teacher/out/nv2.log
ps aux | grep -E 'llama-server|label_local|run_nudge' | grep -v grep
# re-evaluate a GGUF exactly like the headline (see eval/experiments/run_prompt_variants.py --help)
python training/reliability.py --help
# backup: follow scripts/BACKUP.md
BACKUP_AUTOCOMMIT=1 scripts/backup_push.sh
```
From scratch (no box): clone the repo, download release `artifacts-2026-11-01` (section 15), reassemble splits, `sha256sum -c SHA256SUMS`.

## 15. Release artifacts and Git LFS (2026-11-01 ~8:50 PM ET)
Release `artifacts-2026-11-01` on hxbib/pocket-glimmer (private), created from the Mac (PC was offline): https://github.com/hxbib/pocket-glimmer/releases/tag/artifacts-2026-11-01
| Asset | Bytes | sha256 |
|---|---|---|
| SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf | 807694080 | a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2 |
| lora-ep1-SHIPPING.tar (dir SHIPPING-ep1-lora-llama1b-glimmer/, adapter sha 24731bef…8e59) | 45141504 | ea86f577cb34ae7a41c7ff6157f5bea7c49dbe567fd97dd5a62ac0d37f36c03f |
| lora-ep2-REJECTED.tar (dir lora-llama1b-glimmer-ep2/) | 45137920 | 2ae0ffb318daf71744e905b134cfc241f8aab12bdff0c29aa3c363afabbe6c68 |
| labels-and-data.tgz (teacher labels, pool, scenarios, qc, nv2 snapshot as of ~7:55 PM) | 443222 | a2299f27c20d8ac7d5cf6037335434b2b3dc6193807a2a87ce6ba49cfb718c4f |
| pg.tgz (Mac-day tarball of this repo) | 29271784 | dd5057cc30da8f1c80e1693e7c6c378a97258acb1f4717394ce841765f2ba36b |
| SHA256SUMS | 460 | (checksums of the above) |
No split files in this release (all assets < 2 GB). Verify: `gh release download artifacts-2026-11-01 -R hxbib/pocket-glimmer -D rel && cd rel && shasum -a 256 -c SHA256SUMS`.

Git LFS (commit 37a952b, merged in 8c4176e): `models/SHIPPING-ep1-…Q4_K_M.gguf`, `models/lora-ep1-SHIPPING/`, `models/lora-ep2-REJECTED/` (898 MB of the 10 GiB free LFS quota; free bandwidth 10 GiB/month, per docs.github.com Git LFS billing). Fetch with `git lfs install && git lfs pull`.

Not uploaded, and why:
- Merged fp16/bf16 safetensors (2.47 GB each, ep1 and ep2): reproducible from base + adapter with training/local_teacher/export_gguf.sh; transfer limits (CopyFromBox ≤100 MiB per file, ~30 MB chunks reliable) and low free disk on PC (~7 GB) and Mac (~8 GB). Still on the box at training/local_teacher/out/lora-llama1b-glimmer*-merged/.
- Glimmer IQ2_M teacher and base Meta weights: re-downloadable (section 11).
- Kickoff recordings: see the dated entry below (added after upload, or pending).
- m3u8.txt, rec_*.log and anything with the signed Vimeo URL or keys: excluded on purpose.
- gitleaks: history and release staging scanned; only false positives in vendored sqlite3.c and Swift build records.

Local copies of the shipping model: Mac `~/pocket-glimmer-models/SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf` + `~/pocket-glimmer-models/SHIPPING-ep1-lora-llama1b-glimmer/` (sha256 verified). PC copy into C:\pocket-glimmer-backup\models\ PENDING (PC offline at ~8:15 PM ET).

## 2026-11-01 20:20 ET: nv2 retrain measured and rejected
nudge_v2 relabel + 1-epoch floor retrain (1,030 rows) loses to ep1 on cal180: acc on handled 0.92 vs 0.96, conformal bound 10.9% vs 10.2%, nudgeNow unchanged 7/15 (test120 report: acc 0.79, ECE 0.106, nudgeNow 3/10). IQ2_M teacher labeled only 20/66 intended-"later" scenarios "later". ep1 stays shipping. Source: eval/results/AFTER_FLOOR_NV2.md.

## 2026-11-01 23:20 ET: Spark Open teacher retrain measured and rejected
Floor LoRA (unchanged recipe, 1,157 rows = 892 + 280 weak-type, Muse Spark Open k=8 labels) vs ep1 on cal180: acc on handled 0.90 vs 0.96, conformal bound 13.7% vs 10.2% (tau 0.98, 1 error), handled@0.8 0.70 vs 0.49, nudgeNow 10/15 vs 7/15. test120 (report only): acc 0.81 vs 0.82, ECE 0.089 vs 0.064, handled@0.8 0.73 / acc-on-handled 0.89, nudgeNow 4/10 vs 3/10. Graded against the gold field in eval/gold/*; Spark cal labels were used for analysis only (Spark vs gold cal180 0.989; vs Glimmer on train 0.964). License permits distillation with "Built with Muse Spark Open" attribution (docs/LICENSING.md). Spend: Baseten $11.06 cumulative (spend.jsonl), Modal $0 (MODAL_TOKEN_SECRET missing). Trained on box CPU, because the PC run finished but the PC's C: drive then filled up during export. **ep1 stays shipping; nothing uploaded.** Source: eval/results/SPARK_TEACHER.md.

## 2026-11-02 11:10 ET: general-capability drift check of ep1 (no meaningful drift)
40 hand-written non-routing prompts, base Llama 3.2 1B Instruct vs base+ep1 SHIPPING adapter (HF bf16, box CPU, $0): mean per-token KL(base||tuned) 0.0096 nats (median 0.0036, max per-prompt 0.047), 30/40 greedy outputs identical, checkable answers 23/23 vs 23/23, routing/JSON collapse 0/40 for the tuned model. Not measured on the Q4_K_M GGUF. Source: eval/results/DRIFT_CHECK.md, eval/drift/.

## 2026-11-02 11:15 ET: drift check extended to shipping Q4_K_M GGUF (clean)
Same 40 prompts via llama.cpp ddf48f8 (box CPU, greedy, HF template token ids): shipping Q4_K_M (a5c60a88…82c2) 23/23 checkable, 0 collapse, 23/40 exact match with the bf16 tuned outputs. Local base Q4_K_M control: 22/23, 0 collapse, 21/40 match; shipping and base Q4 identical on 27/40. KL vs bf16 not computed (llama-server exposes only top-n probs). Source: eval/results/DRIFT_CHECK.md "Shipping GGUF".

## 2026-11-02 12:20 ET: quant identity + quant ladder (keep Q4_K_M)
The headline numbers (test acc 0.82, ECE 0.064; cal bound 10.2% @tau 0.90) came from the shipping Q4_K_M GGUF (a5c60a88…82c2) via llama-server, not from bf16 (this pipeline has no temperature scaling). Same pipeline on cal180, graded vs gold: f16 bound 14.5%, ECE 0.031; Q8_0 (1321 MB) 13.9%, ECE 0.069; Q4_K_M rerun 10.7%, ECE 0.046 (2 test / 4 cal preds differ from Nov 1 = llama-server noise); Q3_K_M (691 MB) acc 0.72, 13.9%; Q2_K (581 MB) acc 0.66, 30.4%. IQ2_M skipped (no llama-imatrix built). Nothing beats Q4_K_M on cal, so keep shipping Q4_K_M. Source: eval/results/QUANT_IDENTITY.md, eval/quant/.

## 2026-11-04 05:40–08:30 ET: final-hours integration (orchestrating agent + four Opus 5.5 subagents, $0 spend, no training)
Box: a CPU-only cloud machine (16 vCPU, 125 GB, no swift on host → `swift:6.1-noble` Docker; llama.cpp master 13ec8f6 built locally). Standing orders honoured: no training, no API spend (Baseten $11.06 / Modal $0 / Meta API $0 unchanged), shipping ep1 Q4_K_M frozen (sha256 re-verified), test120 touched only for report-once numbers, all selection on cal180.
- **AFTER_FILL Option A applied** (τ=0.90 certified operating point; "51%" always labelled "at τ=0.8, test N=120"). `[AFTER_*]` placeholders filled in README/SUBMISSION/DEMO_SCRIPT; `[PHONE_*]` remain only in docs/FINAL_HOURS.md and the DEMO_SCRIPT on-screen cells, to be filled from the real iPhone.
- **Headline reproduced on this box** (eval/results/REPRO_NOV4.md): cal180 acc 0.794 (ref 0.783), ECE 0.040 (0.042), LTT tightest 10.4% @ τ0.90, 63/180, 0 errors (ref 10.2%, 64/180). 5/180 preds differ (llama.cpp ddf48f8 → 13ec8f6 + known run noise). Published numbers stand.
- **Risk–coverage / AURC** (eval/results/RISK_COVERAGE.md, docs/img/risk_coverage_test120.png; re-analysis of saved test120 rows, no re-run): AURC 0.148 (untrained) → **0.085** (shipping); at τ0.9 shipping keeps 37% with 6.8% selective risk, at τ0.8 51% / 8.2%.
- **Per type at τ=0.90** (eval/results/PER_TYPE_TAU090.md): 44/120 handled, 41/44 correct; confirmBeforeAct clears τ0.90 only 2/10 (the demo's confirm beat relies on the "messages always confirm" hard rule).
- **Swift production path on the shipping GGUF** (eval/results/E2E_SWIFT_SHIPPING.md, `pg-cli e2e`, 18 cases): 14/18 argmax, 10/18 handled @τ0.9, 10/10 correct; with contextual-calibration priors 16/18, still 10/10 on handled; every miss is below τ. Untrained was 9/18 / 3/18.
- **Bundled `app/PocketGlimmer/Resources/Models/calibration.json`**: content-free priors measured from the shipping GGUF (`pg-cli priors`, 24 sets) + `defaultTau` 0.90. Before this the app would have run fewShot *without* the cc correction the headline assumes.
- **docs/img/architecture.png** rendered from the README Mermaid (mermaid-cli), for GitHub/judges without Mermaid.
- **Option-order permutation averaging** (eval/results/PERM_AVG.md; LEDGER idea 13.4): ranks better (AURC 0.058 vs 0.067–0.070) and tightens the cal180 LTT bound (all-cyclic/geo 7.8% @τ0.77, 47% handled, 0 errors) but makes the student under-confident (ECE 0.084–0.101 vs 0.040–0.056) and costs K≈3.4× latency. Fails the pre-registered rule (bound ↑ AND ECE within +0.01). **Does not ship.** K=2 reversed/mean was borderline on cal180 (win on one run, loss by 0.002 ECE on another) and, under a written pre-commitment (eval/experiments/perm_test120_precommit.txt), was reported ONCE on test120 report-only: ECE 0.087 vs 0.047 single-order on the same run; verdict unchanged. That is the only test120 run of Nov 4 so far.
- **Single-order run-to-run noise on the same GGUF**: a fresh server reproduces T1 exactly; warm-server runs differ on up to 7/180 preds; cal180 spans ECE 0.040–0.056, bound 10.4–10.9% (6 runs). Any future "win" must clear that band.
- **CLINC out-of-scope stress (eval/results/OOS_STRESS.md; 1000 route + 1000 answerability, no gold, no conformal claim)**: shipping model false-confident (keeps an OOS item on device with conf ≥ τ) **0.25% (5/2000) at τ0.90**, 7.3% at τ0.80; of its confident route picks at τ0.90, 96/103 are escalate_cloud. Untrained base is 0.0% only because it is never confident (mean top conf 0.46–0.54 vs 0.66).
- **Box latency, clean server (eval/results/LATENCY_BOX.md; x86 CPU, not iPhone)**: single-order decision median 175 ms / p90 288 ms, median 356 prompt tokens of which 78 uncached (system+few-shot prefix cached).
- **Closed loop made runnable** (training/loop/): phone export of escalated decisions → `label_queue.py` (Glimmer local logprobs or Spark Open k-vote, with a Python mirror of the privacy scrubber) → `verdicts.py` (teacher-agree back to the phone's telemetry) → `merge_round.py` (next-round train file, deduped vs every eval item) → existing LoRA/GGUF/cal180 chain. `selftest.sh` passes on the box with the shipping model as stand-in teacher.
- Research pack (docs/research/): RELATED_WORK.md (32 verified refs; closest prior art Uddin & Bauer ACL 2026 SRW, Conformal Cascade 2607.25018, CR² 2605.12001 — our "no prior art found" claim is scoped to the full on-phone combination only), ARXIV_SCAN_NOV4.md (Meta's Glimmer report arXiv:2610.24628 states Glimmer was pre-trained on Muse Spark outputs via logit distillation: chain Spark → Glimmer → Llama-Reflex-1B), JUDGE_BRIEF.md, ROADMAP_POST_HACKATHON.md. Claim fix: "memory never leaves your phone" was false (scrubbed memory lines accompany escalations) and is being reworded everywhere.
- Swift core/app upgrades and the skills layer are recorded in the next entry once their tests are green.
