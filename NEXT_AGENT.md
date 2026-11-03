# NEXT_AGENT (for an agent working from a clone on Habib's PC or Mac)

You will NOT have the Grok Bot box (/workspace/...). Everything you need is in this repo, its Git LFS files and its GitHub release. Read **LEDGER.md** first: measurement protocol (section 0), results, rejected ideas, in-flight work.

## 0. State at handoff (Tue Nov 3 2026, 12:30 PM ET) — read this first
- **Standing order from Habib (Nov 2, 4:05 PM ET):** no training and nothing that spends API credit anywhere until he gives new directives. Spend so far: Baseten $11.06, Modal $0, Meta API $0 (training/spark_teacher/spend.jsonl). Do NOT set `PG_ALLOW_SPEND=1`.
- **Shipping model is frozen:** ep1 Q4_K_M. Numbers re-derived on that exact file:
  - cal180: acc 0.783, 49% handled at conf ≥0.8, acc-on-handled 0.955, ECE 0.042; LTT bound ≤10.2% at τ=0.90 (64/180 handled, 0 errors). 5% is NOT certified.
  - test120 (frozen, headline only): acc 0.817, ECE 0.064, 51% handled at τ=0.80, acc-on-handled 0.918.
  - Base model ECE was 0.150. The good calibration comes from distillation. No temperature scaling is used; never claim it, and never say "well-calibrated out of the box".
- **Decision waiting on Habib:** docs/AFTER_FILL_PROPOSAL.md. Option A (recommended): headline τ=0.90, certified, ~36% on-phone on cal180, and any "51%" must be labeled "at τ=0.8". Option B: τ=0.80, 51% on test120, no certificate. Apply with scripts/apply_after_fill.sh only after his own yes.
- **iOS:** unsigned **Simulator build passes** on the Mac (no code changes needed) once the xcframework exists:
  `cd ~/src/llama.cpp && ./build-xcframework.sh` (pinned ddf48f8) → copy `build-apple/llama.xcframework` to gitignored `app/Frameworks/`, then `cd app && xcodegen` and build with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (Xcode 27.2). The Mac has no iOS Simulator runtime (needs ~15 GB free for `xcodebuild -downloadPlatform iOS`; ~10 GB free last check), so skip the simulator and go straight to the device.
- **Critical path:** Mac + unlocked iPhone online → Habib picks his free Apple ID team in Xcode Signing → install → copy the GGUF into the app's Documents (Files sharing; `AppModel.findModel()` checks Documents then bundle, prefers "reflex" in the name) → log PGPERF to fill `[PHONE_TTFT_MS] [PHONE_TOK_S] [PHONE_RAM_GB]` → record the airplane-mode demo (was due Tue Nov 3). Only show offline shots for request types verified to clear τ on the real phone.
- **Fallbacks if no iPhone:** film on the Mac with Wi-Fi off, clearly labeled as a Mac run; last resort a screen-capture explainer.
- **After the phone works (not before):** confirmBeforeAct handlers (Messages/Mail compose sheets, shortcuts:// runs); speed levers (first-token logit decode needs re-calibration, cached system-prompt prefix, flash attention + q8 KV); CLINC out-of-scope stress test (training/data_scale/out/clinc_oos_test_stress.jsonl); scan docs/DEMO_SCRIPT.md for any temperature-scaling claim.
- **Reviewed and skipped:** Weight-Space Programming (incl. the HF ML Intern repro), Neuron Tuning, kimi-k3-in-c, Bonsai, Spark-X2.6-4B, Latent Sparse Attention. WSP is only a post-submission idea, and only with Habib's approval for credits.
- **Claims discipline:** say "we haven't found prior art" only for the combination; cite selective prediction (Chow 1970; Geifman & El-Yaniv 2017), FrugalGPT cascades, Learn Then Test (Angelopoulos, Bates et al. 2021); state the exchangeability assumption. Meta API in Standard mode only; BYO key is a README footnote.
- **Repo stays private** until submission; then final secret rescan, then public. Only Habib's own words approve actions.

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
See docs/MAC_DAY_RUNBOOK (and handoff/mac-day). In short: install XcodeGen, `cd app && xcodegen`, open the project in Xcode, set your free team signing, build to the iPhone, then copy the shipping GGUF onto the phone via Files sharing (UIFileSharingEnabled). llama.cpp xcframework pinned at ddf48f8. The Simulator build at e0e5b82 compiled cleanly (includes 35d619d). Log PGPERF ttft/tok/s to fill `[PHONE_*]`.

## 5. Top next actions
1. iPhone build + measure `[PHONE_TTFT_MS] [PHONE_TOK_S] [PHONE_RAM_GB]`; record the 3-min video by **Tue Nov 3**.
2. Get Habib's sign-off and fill `[AFTER_*]` in docs/SUBMISSION.md and docs/DEMO_SCRIPT.md from LEDGER section 6 (ep1 numbers).
3. ~~Optional teacher / temperature-scaling experiments~~ cancelled: the Nov 3 noon cutoff passed and credit spend is paused. Model is frozen at ep1.

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
