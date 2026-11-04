# FINAL HOURS: Wed Nov 4 2026 (deadline 9:00 PM ET, no grace period)

Written ~6:45 AM ET for Habib. Everything that a person with the repo could do is done. The rest needs your Mac,
your iPhone, your Apple ID, your voice, and your own click on "Submit". **Target: submitted by 5:00 PM ET.**

Spend: you lifted the no-spend / no-training order at ~6:20 AM ET, and a round-2 run (Muse Spark Open labels on
Baseten + a LoRA sweep on Modal) is running under the same cal180 gate. Spend is being recorded in
`training/spark_teacher/spend.jsonl` and `eval/results/ROUND2.md`; the final totals will be in LEDGER.md (read them
there before quoting any number). Before today's run: Baseten $11.06, Modal $0, Meta Model API $0. The Muse Spark 1.3
hand-off shot adds a few Meta API calls with your own key; skip it if you'd rather not.
**If round 2 ships a new model**, the headline numbers in README/SUBMISSION/DEMO_SCRIPT change with it: use the ones
the orchestrator writes into LEDGER.md and eval/results/ROUND2.md, and copy that GGUF to the phone instead (step B5).
A Spark-Open-labeled model that ships also changes the story: Glimmer is then not "the only teacher", Spark Open is not
"rejected", and the Muse Model License requires showing "Built with Muse Spark Open" (docs/LICENSING.md; NOTICE already
has the line). Check the form text in section F against ROUND2.md before pasting.

---

## A. Placeholder list (5 minutes once the phone numbers exist)

Nothing below can be filled without the phone or your accounts. Every other placeholder in the repo is filled.
Check with `grep -rn '\[PHONE_\|\[AFTER_\|\[PLACEHOLDER\|\[TBD' README.md docs/` (only this file and the
on-screen cells of docs/DEMO_SCRIPT.md should match).

| # | Value | Where it goes | How to get it |
|---|---|---|---|
| 1 | `[PHONE_TOK_S]` decode tok/s | DEMO_SCRIPT 1:45 slide; README paragraph starting "**iPhone speed and memory:**"; SUBMISSION "Phone speed" bullet | Step B6: `PGPERF … decode_tok_s=` |
| 2 | `[PHONE_TTFT_MS]` time to first token | same three places | Step B6: `PGPERF … ttft_ms=` |
| 3 | `[PHONE_RAM_GB]` peak memory | same three places | Step B6: Xcode Debug navigator (⌘7) → Memory, peak during a generation |
| 4 | `[PHONE_CONF]` per demo card | DEMO_SCRIPT on-screen cells only (read off the phone, never typed into docs as claims) | the decision cards while you record |
| 5 | Video URL | SUBMISSION "Demo" + "Links"; CV form | Step D |
| 6 | X post URL (optional, Most Viral) | SUBMISSION "Links"; CV form | Only if you decide to post. Hooks: docs/research/JUDGE_BRIEF.md §8 |
| 7 | Real-use line (optional) | SUBMISSION "Impact": add one sentence | Only if you actually used it today (e.g. on the train). Never invent one |

Paste-ready replacements, once you have the numbers (median of runs 2–3, Release build, airplane mode):
- README.md, replace the "**iPhone speed and memory:**" paragraph, and the "On-iPhone speed / memory" row of the Status table, with:
  `iPhone 17 Pro (Release build, airplane mode, n_ctx 4096, Metal): X tok/s decode, Y ms to first token, Z GB peak memory (Xcode memory gauge); median of runs 2–3.`
- docs/SUBMISSION.md, replace the "Phone speed" bullet with the same sentence.
- If the phone is not a 17 Pro, fix the model name: `grep -rn '17 Pro' README.md docs/`.

---

## B. Mac + iPhone build (target done by 9:30 AM, hard cut-off 11:30 AM)

Condensed from ios/MAC_DAY_RUNBOOK.md and NEXT_AGENT.md §0. The Mac already has Xcode 27.2, xcodegen, gh (logged in
as hxbib), the repo at `~/src/pocket-glimmer`, llama.cpp at `~/src/llama.cpp`, and a verified shipping model in
`~/pocket-glimmer-models/`. On Nov 2 an unsigned Simulator build of the app compiled cleanly (source at e0e5b82).
**The app and core have changed since then** (today's agents added Messages/Mail compose sheets, offline sensitivity
and memory features), so expect a possible small compile fix.

```bash
# B1. Pull (2 min)
cd ~/src/pocket-glimmer && git pull && git lfs pull
shasum -a 256 models/SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf   # must start a5c60a88, end 82c2

# B2. llama.xcframework, pinned ddf48f8 (skip if app/Frameworks/llama.xcframework already exists; ~10-15 min if not)
ls app/Frameworks/llama.xcframework || ( cd ~/src/llama.cpp && git checkout ddf48f8 && ./build-xcframework.sh \
  && mkdir -p ~/src/pocket-glimmer/app/Frameworks && cp -R build-apple/llama.xcframework ~/src/pocket-glimmer/app/Frameworks/ )

# B3. Project (1 min)
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ~/src/pocket-glimmer/app && xcodegen generate && open PocketGlimmer.xcodeproj
```

B4. **Signing (free Apple ID), 5 min.** Xcode → Settings → Accounts → + → your Apple ID. Target PocketGlimmer →
Signing & Capabilities → "Automatically manage signing" → Team: *(Personal Team)*. If the bundle ID
`com.habib.pocketglimmer` is taken, set `PRODUCT_BUNDLE_IDENTIFIER: com.habib.pocketglimmer.dev` in `app/project.yml`
and run `xcodegen generate` again. Free-team apps expire after 7 days (re-install before the Nov 9 finals).

B5. **Install, 10 min.** iPhone: Settings → Privacy & Security → Developer Mode ON (reboots), USB → Trust.
Scheme → Edit Scheme → Run → Build Configuration **Release** (Debug is much slower for llama.cpp). Pick the phone, ⌘R.
On the phone: Settings → General → VPN & Device Management → your Apple ID → Trust. Grant Reminders, Calendars and
Contacts on first launch.
- Then copy the model: Finder → your iPhone → Files → Pocket Glimmer → drag
  `~/pocket-glimmer-models/SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf` (808 MB) in. Relaunch.
  `AppModel.findModel()` checks Documents first and prefers a filename containing "reflex".
- Check: Settings tab → "On-device model" shows the model name (not "No model file"). Open any decision card:
  the footer reads **τ = 0.90**. That value comes from the bundled `app/PocketGlimmer/Resources/Models/calibration.json`
  (contextual-calibration priors measured on the shipping GGUF + `defaultTau` 0.90). If the footer says 0.80, the
  calibration file didn't make it into the bundle: check that it is listed under Copy Bundle Resources.
- If the build is red: fix core first, then the engine, then the views (runbook §7 lists the usual errors). If today's
  changes won't compile within 30 minutes, build the last known-good tree instead:
  `GIT_LFS_SKIP_SMUDGE=1 git worktree add ../pg-e0e5b82 e0e5b82 && cp app/PocketGlimmer/Resources/Models/calibration.json ../pg-e0e5b82/app/PocketGlimmer/Resources/Models/ && cp -R app/Frameworks ../pg-e0e5b82/app/`
  then repeat B3–B5 there. That tree lacks today's compose sheets and offline sensitivity card, so use the demo
  variants marked "(Nov 2 tree)" in section C.

B6. **Measure (20 min), airplane mode ON, Wi-Fi off.**
1. Xcode console filter `PGPERF`. Each local generation prints
   `PGPERF prompt_tokens=… prefill_ms=… ttft_ms=… gen_tokens=… decode_tok_s=…`.
2. Ask the same local-answer prompt 3× (e.g. *"Write a two-line thank-you text to my roommate"*). Use the median of
   runs 2–3 for ttft_ms and decode_tok_s. Note the thermal state.
3. RAM: Debug navigator (⌘7) → Memory → the peak during a generation (cleaner: Product → Profile → Allocations,
   peak Physical Footprint).
4. Reflex decisions are one forward pass each; their ms is printed on each decision card. Don't quote it as tok/s.
5. Write the three numbers into the table in section A. Label them "measured on iPhone 17 Pro, Release build, airplane mode".

**11:30 AM cut-off:** no working app on the phone by then → go to C-fallback. Don't keep debugging.

---

## C. Record the demo (10:00 AM–12:30 PM)

Full script with voiceover: docs/DEMO_SCRIPT.md. Shot list, condensed and adjusted for **τ = 0.90**: at that
threshold, contactPick, eventPick, route, toolChoice and sensitivity are the types that most often stay on device
(eval/results/PER_TYPE_TAU090.md). **Rehearse every offline shot on the real phone and keep only those that clear τ.**
Never say a number on camera that you didn't read off the phone or the eval files.

| Time | Shot | Must show |
|---|---|---|
| 0:00–0:10 | Airplane Mode ON (icon visible). *"Remind me to call Mom at 7."* | route → tool and toolChoice → create_reminder cards; tap Confirm if it asks (confirmBeforeAct below τ falls back to confirm); the reminder appears in Reminders |
| 0:10–0:25 | Lower third "Habib · CS student, Hunter College · Bronx" | who you are, the subway moment |
| 0:25–0:45 | Still offline. *"Text Mom I'll be home by 8."* | toolChoice → send_message card, JSON tool call, Confirm button, then the Messages compose sheet. Call it "structured confirmation": messages **always** confirm by rule. Don't promise a green bar on the confirmBeforeAct card (it clears 0.90 only 2/10 on test) |
| 0:45–1:05 | Airplane OFF (pill → "Online"). *"Help me budget: my salary is $2,100 a month and I owe $3,400 on my credit card."* | sensitivity → sensitive card, "Kept on device · nothing sent" lock badge, no Muse Spark badge |
| 1:05–1:20 | *"When's my advising meeting?"* with two advising events seeded | eventPick picks one with a green bar (or asks "Which one?", both are fine) |
| 1:20–1:32 | *"Text Sam I'm running late."* (two Sams in Contacts) | contactPick bar orange below τ → the phone asks "Which Sam?" instead of guessing |
| 1:32–1:45 | Online, Meta key set. *"Plan my week around Professor Lee's CSCI 335 final and my calc midterm."* | route → escalate, badge "Meta Model API · Muse Spark 1.3 (Standard mode)", info sheet shows masked `[PERSON_1]` |
| 1:45–2:20 | Proof slides (DEMO_SCRIPT has the exact text) | before/after table, phone numbers (section A), risk–coverage chart `docs/img/risk_coverage_test120.png`, the ≤10.2% bound **with** "assuming new questions look like the calibration set" |
| 2:20–2:45 | Meta stack: `docs/img/architecture.png` + lineage line | Spark → Glimmer → Llama-Reflex-1B; Spark Open tested and rejected |
| 2:45–3:00 | Airplane ON again, Memory tab | close line (DEMO_SCRIPT) |

Seed before recording (by talking to the app, never by inserting rows): a "Mom" contact, two "Sam" contacts, two
calendar events with "advising" in the title, a memory fact naming Professor Lee. (Nov 2 tree: no compose sheet, so
the message beat ends at the Confirm card; skip the airplane-mode sensitivity variant.)

If the Meta key isn't set or you'd rather not spend: cut 1:32–1:45 and say "with the API key, this goes to
Muse Spark 1.3 in Standard mode" over the orange contactPick card. That is the honest fallback.

**C-fallback, no iPhone app by 11:30 AM:**
1. Mac run, Wi-Fi off, clearly captioned **"Mac run, not iPhone"**: either Xcode destination "My Mac (Designed for
   iPad)" if it shows up, or terminal:
   `llama-server -m ~/pocket-glimmer-models/SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf --port 8088 -c 4096`
   then `cd ~/src/pocket-glimmer/core && swift run pg-cli e2e --url http://127.0.0.1:8088 --tau 0.9 --calibration ../app/PocketGlimmer/Resources/Models/calibration.json`
   (18 typed decisions with confidence and escalation; on the box this gave 16/18 argmax, 10/18 kept, 10/10 correct
   on kept, eval/results/E2E_SWIFT_SHIPPING.md).
2. Last resort, screen-capture explainer: narrate over README → architecture.png → risk–coverage chart →
   reliability chart → the e2e terminal run. Say plainly that the phone build isn't in the video.

---

## D. Upload the video (12:30–2:30 PM)

1. Edit to **≤ 3:00**. Cut failures. Check the audio on headphones.
2. YouTube → **Public** (not unlisted, not private). Title: `Pocket Glimmer: a 1B Meta model on iPhone that knows when it doesn't know`.
   Description: the one-liner from section F + the repo URL.
3. Open the link in a private/incognito window (logged out). It must play, with sound, at full length.
4. Keep the local file. Bring it to the Nov 9 finals as a backup.

---

## E. Repo public + final secret scan (2:30–3:00 PM)

```bash
cd ~/src/pocket-glimmer && git pull
# 1. Secret scan of the whole history (expect only false positives: vendored sqlite3.c, Swift build records)
git log -p --all | grep -inE 'sk-[A-Za-z0-9_-]{16,}|api[_-]?key["'"'"' ]*[:=] *["'"'"'][A-Za-z0-9_-]{12,}|bearer [A-Za-z0-9._-]{20,}|(BASETEN_API_KEY|META_API_KEY|MODEL_API_KEY|MODAL_TOKEN_(ID|SECRET))=[^ $]|token=[A-Za-z0-9]{16,}' \
  | grep -v 'sqlite3' | head -40
# expected false positive: docs line 'BASETEN_API_KEY=... MODAL_API_KEY=...' (literal dots, no key)
command -v gitleaks && gitleaks detect --source . --log-opts="--all" --redact -v | tail -20
# 2. Make it public (the release artifacts-2026-11-01 becomes public with it; it was scanned on Nov 1, LEDGER §15)
gh repo edit hxbib/pocket-glimmer --visibility public --accept-visibility-change-consequences
```
3. Logged-out check in a private window: https://github.com/hxbib/pocket-glimmer. README renders, both images
   (`docs/img/architecture.png`, `docs/img/risk_coverage_test120.png`) load, Commits shows dates Oct 31–Nov 4,
   and the Releases page lists `artifacts-2026-11-01`.
4. Judgment call before going public: `handoff/kickoff/` holds transcripts and OCR of the event kickoff stream
   (the signed stream URL is already redacted). If you'd rather not publish them, `git rm -r handoff/kickoff && git commit -m "remove kickoff transcripts" && git push`.
   History keeps them, and we never rewrite history.
5. Git LFS free bandwidth is 10 GiB/month (≈13 downloads of the 808 MB GGUF). The release asset has the same file
   and doesn't count against LFS. README already points to both.

---

## F. Cerebral Valley submission form (3:00–4:30 PM; **submit by 5:00 PM**)

URL: cerebralvalley.ai/e/meta-ai-developer-hackathon/hackathon/submit. The field names below are our best guess
from the kickoff ("Review the form early"). Paste by meaning. Source text: docs/research/JUDGE_BRIEF.md
(number-checked against LEDGER §6 and eval/results/).

**Project name**
```
Pocket Glimmer
```

**Track / theme**
```
Indie Developer · Build for Your World
```

**One-liner / tagline**
```
A 1B Meta model on my iPhone that makes an assistant's everyday decisions offline and knows when it doesn't know: Llama 3.2 1B distilled from Muse Glimmer 30B, handing off to Muse Spark 1.3 only when it's unsure.
```

**Description** (≈ 300 words)
```
I'm Habib, a CS student at Hunter College who lives in the Bronx. My commute is underground with no signal, and the assistants I can use either forget me or keep my life on a server. Pocket Glimmer is an iPhone assistant whose memory of me lives in SQLite on the phone and whose decisions run on the phone, in airplane mode: reminders, calendar, contacts, messages (always confirmed), memory recall and corrections.

Every step is a typed decision (12 types: route, tool choice, contact pick, sensitivity, confirm-before-act, and more) answered by Llama-Reflex-1B in one forward pass: it reads the answer-letter logits and compares the top probability to a threshold τ. Below τ it takes the safe path: ask, confirm, or hand the question to Muse Spark 1.3 (Meta Model API, Standard mode), with names, emails, phones, addresses and card numbers masked first. A sensitivity decision can keep a request on the phone even when the cloud is available.

Four Meta models, four jobs: Llama 3.2 1B is the student that runs on the phone (Q4_K_M, 808 MB, llama.cpp + Metal). Muse Glimmer 30B, run locally on my own machine, is the only teacher: its option-letter probabilities are the soft labels for 892 decisions. Muse Spark 1.3 is the cloud escalation. Muse Spark Open was tested as a stronger teacher and rejected: it matched my hand labels better, but the 1B it taught was overconfident. Lineage: Meta pre-trained Glimmer on Spark's outputs by logit distillation, so this is Spark → Glimmer → Llama-Reflex-1B.

Results on a frozen held-out set of 120 hand-labeled decisions: accuracy 74% → 82%; decisions kept on the phone at confidence ≥0.8: 15% → 51% (92% correct); calibration error (ECE) 0.150 → 0.064, from distillation alone, no temperature scaling. The shipped threshold τ=0.90 comes from Learn-Then-Test on a separate 180-item calibration split: 36% kept on the phone with 0 errors, error among kept decisions bounded at ≤10.2% (δ=0.1), assuming new requests resemble the calibration set. Negative results (2 epochs, a relabel, the Spark Open teacher, four other quants) are in the repo.
```

**What was built during the event / prior work**
```
Everything in the repo was written during the event (first commit Oct 31 2026, all commits Oct 31–Nov 4). No earlier code, products or templates were reused. Third-party pieces: llama.cpp (MIT), SQLite (public domain), PyTorch/Transformers/PEFT and Unsloth for training, matplotlib. Model weights keep their own licenses (Llama 3.2 Community License, "Built with Llama"; Muse Glimmer Apache-2.0).
```

**Repository**
```
https://github.com/hxbib/pocket-glimmer
```

**Demo video**
```
<your public YouTube URL from step D>
```

**Team**
```
Habib (solo) · GitHub: hxbib
```

**Bonus prizes to flag**
```
Best Agentic Use-Case; Community Vote
```
Add "Most Viral Project" + the X link only if you post (your call). **Do NOT flag Best Build on Meta Open Weights.**

**Agentic use-case blurb** (if the form asks why; if `docs/SKILLS.md` exists when you submit, add the sentence
"A skill registry (docs/SKILLS.md) extends this to open-world phone actions through a dynamic skill-pick decision.")
```
Each request is a chain of typed on-device decisions where every link can stop safely: route → tool choice → contact/event pick → confirm-before-act → act (EventKit, Contacts, Messages compose). Messages always ask for confirmation; when the contact pick is unsure (two "Sam"s) it asks instead of guessing; when a request is hard it escalates to Muse Spark 1.3 with personal details masked; a sensitivity decision can keep it on the phone. Proactive nudges come from iOS Shortcuts triggers through an App Intent and a nudge-now decision. Memory writes (remember-or-not, conflict: update / keep both / ignore) are decisions too, with provenance and user corrections as retrievable memories.
```

After submitting: reopen the submission page, click the video and repo links logged out.

---

## G. If everything goes wrong (60-second plan)

1. It's after 6:30 PM and something is still broken: **stop fixing and submit what exists.**
2. Repo public (section E, 2 commands). The README stands on its own: numbers, charts, negative results.
3. Video: whatever you have. Even a 90-second screen capture of the README, the charts and the `pg-cli e2e` terminal
   run beats no video. Say what isn't shown.
4. Form: paste section F as it is. Leave the phone numbers out. No doc claims a phone number that wasn't measured.
5. Submit before 8:30 PM. Then check the links logged out.
