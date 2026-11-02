# NEXT_AGENT (for an agent working from a clone on Habib's PC or Mac)

You will NOT have the Grok Bot box (/workspace/...). Everything you need is in this repo, its Git LFS files and its GitHub release. Read **LEDGER.md** first: measurement protocol (section 0), results, rejected ideas, in-flight work.

## 1. Get the code, models and artifacts
```bash
gh repo clone hxbib/pocket-glimmer && cd pocket-glimmer     # gh is logged in as hxbib on both PC and Mac
git lfs install && git lfs pull                              # models/: SHIPPING ep1 GGUF + ep1/ep2 adapters
gh release download artifacts-2026-11-01 -D ../pg-release    # same models + labels-and-data.tgz + pg.tgz
cd ../pg-release && shasum -a 256 -c SHA256SUMS              # Windows: Get-FileHash -Algorithm SHA256
```
Shipping model = `SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf`, sha256 a5c60a88…82c2. ep2 and nv2 were measured and rejected. Mac already has a verified copy in `~/pocket-glimmer-models/`.
If a release asset is ever split (`name.partNN`), reassemble with `cat name.part* > name` (PowerShell: `cmd /c copy /b name.part00+name.part01 name`) and check sha256.

## 2. Secrets
Habib supplies API keys as environment variables; never commit or print them:
`BASETEN_API_KEY`, `META_API_KEY`, `MODAL_TOKEN_ID`, `MODAL_TOKEN_SECRET`.
Credits (authorized for the hackathon): Baseten $100, Modal $100, Meta Model API $150. Spend scripts honor `PG_ALLOW_SPEND=1` and log to training/spark_teacher/spend.jsonl.

## 3. Where training runs
- **PC**: WSL Ubuntu-24.04 on C: (RTX 3080 Ti 12 GB, 32 GB RAM). Scripts: training/local_teacher/lora_gpu.py, run_nudge_v2_gpu.sh, gpu_eval.sh. Do not touch the CurzohDocker or Debian WSL distros; delete nothing.
- **Modal**: training/spark_teacher/modal_train.py (needs MODAL_TOKEN_*).
- Base weights + teacher GGUF are re-downloaded (LEDGER section 11). Never use trust_remote_code.
- Selection on cal180 only; one final report on frozen test120 (LEDGER section 0).

## 4. Build the iOS app (Mac)
See docs/MAC_DAY_RUNBOOK (and handoff/mac-day). In short: install XcodeGen, `cd app && xcodegen`, open the project in Xcode, set your free team signing, build to the iPhone, then copy the shipping GGUF onto the phone via Files sharing (UIFileSharingEnabled). llama.cpp xcframework pinned at ddf48f8. Commit 35d619d (privacy badge) has not been compiled yet: build it first. Log PGPERF ttft/tok/s to fill `[PHONE_*]`.

## 5. Top next actions
1. iPhone build + measure `[PHONE_TTFT_MS] [PHONE_TOK_S] [PHONE_RAM_GB]`; record the 3-min video by **Tue Nov 3**.
2. Get Habib's sign-off and fill `[AFTER_*]` in docs/SUBMISSION.md and docs/DEMO_SCRIPT.md from LEDGER section 6 (ep1 numbers).
3. Optional, only before **Tue Nov 3 noon ET**: Spark Open teacher (license + logprob check first) / temperature scaling (training/temp_scale.py). Swap the model only if cal180 improves.

## 6. Submission checklist (due **Wed Nov 4, 9:00 PM ET**)
- [ ] Submit on cerebralvalley.ai/e/meta-ai-developer-hackathon/hackathon/submit (all teammates)
- [ ] 3-minute demo video, only work done during the event
- [ ] Make this repo PUBLIC and check it in a logged-out browser
- [ ] Call out prior work, flag bonus prizes (do NOT pitch Open Weights), X post link for Most Viral
- [ ] No `[AFTER_*]`/`[PHONE_*]` placeholders left; no secrets in the repo

## 7. Hard rules
- Only Meta models ship; non-Meta models never produce labels. Meta API is not a teacher (no logprobs, ToS §10.1(ix)).
- test120 frozen; select on cal180; augmented data never near test or certification.
- No Fireworks, no Supabase, no trust_remote_code. Never claim a guaranteed win.
- No secrets in git. Never force-push or rewrite history. Append a dated entry to LEDGER.md at every milestone.

## 8. What disappears with the Grok Bot assistant
- The box (/workspace/...): merged bf16 weights, Glimmer GGUFs, kickoff raw captures, gate1 benchmarks. Anything not in git/LFS/release is gone for you.
- The **hourly watchdog routine** (appends to training/local_teacher/out/WATCHDOG_NOTES.md, checks runs, posts updates) STOPS when the assistant's usage runs out. Nobody is babysitting background jobs after that.
- The box→PC bundle backup (scripts/BACKUP.md). From a clone, just `git push` (never force).
