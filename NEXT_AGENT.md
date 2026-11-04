# NEXT_AGENT (for an agent working from a clone on Habib's PC or Mac)

> **Latest authorization, Nov 4 2026:** Read [ORCHESTRATOR_LEDGER.md](ORCHESTRATOR_LEDGER.md) first.
> The user reopened training and authorized remaining Modal and Baseten credits. Candidate experiments
> may change training weights; shipping artifacts stay unchanged until validation. The durable ledger
> owns live jobs, budget reservations, pending reviews, and takeover steps. Older freeze/readiness
> statements below are historical.
> Training-related delegates now use Muse Code `muse-wonder-1.0` with `reasoningEffort=max`,
> per the user's latest assignment. Unrelated existing app delegates retain their assigned models.

> **Continuation checkpoint, Nov 4 2026:** `1242605` integrates the strict Mac preflight repair. Its 73 fixture checks pass, and shipping model/calibration/resource validation passes. The cloud-text repair has complete-window screening and typed memory filtering. The Nov 4 17:39 UTC integrated suite passed 136 tests, one skipped, after alias masking and export repairs. Independent review is still pending. All four Muse reports are archived under `docs/research/`; read `MUSE_REVIEW_FINDINGS.md` for parent corrections. Durable action recovery is still running in its existing isolated T3 worktree and has not been integrated. Its assignment includes explicit email routing, real memory recall, and cloud-result provenance. Current iOS source remains unbuilt. The model, priors, threshold, prompt templates and test120 stay frozen. The older snapshots below are history, not current readiness claims.

You will NOT have the Grok Bot box (/workspace/...). Everything you need is in this repo, its Git LFS files and its GitHub release. Read **LEDGER.md** first: measurement protocol (section 0), results, rejected ideas, in-flight work.

## 0a. State at 8:45 AM ET Wed Nov 4 (submission day) — read this first, then docs/FINAL_HOURS.md
- **Everything a machine without the iPhone can do is done and pushed** (`master` 63dbecb; `scripts/verify_submission.sh` passes: sha, no placeholders, no forbidden claims, no secrets, 7 Python + 94 Swift tests). LEDGER.md has two dated Nov 4 entries with every number and its source.
- **Habib's remaining path is docs/FINAL_HOURS.md**: Mac + iPhone build → fill the three `[PHONE_*]` numbers → shoot the 3:00 video from docs/demo/STORYBOARD.md with the slide PNGs in docs/img/slide_*.png → make the repo PUBLIC and check logged out → submit on the CV form with the text in FINAL_HOURS §F. Before shooting: install the Shortcuts listed in docs/SKILLS.md (incl. "PG Play on Apple TV"), and hit the Glimmer endpoint `/health` ten minutes early if the open-weights hand-off is in the video.
- **Shipping model unchanged: ep1 Q4_K_M** (round 2 rejected under the gate, eval/results/ROUND2.md). τ = 0.90 via the bundled `app/PocketGlimmer/Resources/Models/calibration.json` (31 cc prior sets, incl. skillPick).
- **Spend authorized and used (Nov 4):** Baseten $16.62 cumulative, Meta Model API < $1, Modal ≈ $10–20 (round-2 H100 trainings + the Glimmer vLLM endpoint, which scales to zero; keys/URL only in /tmp/gencode/sec on the build box, never in git). The Nov 2 no-spend standing order was lifted by Habib at ~6:20 AM ET Nov 4.
- New since Nov 3: skills layer (docs/SKILLS.md), Meta voice/vision/SAM 3.1 (docs/META_MULTIMODAL.md), self-hosted Glimmer System 2 (docs/OPEN_WEIGHTS_SYSTEM2.md), closed loop (training/loop/), code review (docs/CODE_REVIEW_NOV4.md), research pack (docs/research/), demo kit (docs/demo/). The app code compiled last on the Mac at e0e5b82; expect small Xcode fixes (the review lists the riskiest lines).

## 0. State at handoff (Tue Nov 3 2026, 12:30 PM ET) — historical
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
