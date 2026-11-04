# Finish and submit Pocket Glimmer — Nov 4, 2026

Submission deadline: **9:00 PM ET (Nov 5, 02:00 UTC)**. The working-demo target is **6:00 PM ET**, with some leeway for troubleshooting. Leave time for the video, benchmarks, repository cleanup, and submission. The Mac is now reachable through T3 Linked environments. Current-source compilation and phone installation remain unverified.

The project is not yet ready to call a finished iPhone release. The current app needs Xcode compilation, signing, and device tests. The repository is private, the public video is missing, and form submission is unrecorded. [PROJECT_STATUS.md](PROJECT_STATUS.md) separates implemented features from verified behavior.

Round 2 is finished and **rejected**. Keep ep1 and τ=0.90 until a new candidate passes the recorded promotion protocol. Round 3 training continues under the user-authorized budgets in [ORCHESTRATOR_LEDGER.md](../ORCHESTRATOR_LEDGER.md). The shipping model's only teacher is Glimmer. Spark Open also supplied experimental labels. See [ROUND2.md](../eval/results/ROUND2.md).

## A. Evidence to collect

| Evidence | Record | Where it goes |
|---|---|---|
| Current build | Git SHA, Xcode/SDK, configuration, build log, installed model hash | Mac runbook evidence folder; project status |
| Phone speed | Device and OS, prompt, all PGPERF rows, cold/warm distinction, thermal state | README and submission only after measurement |
| Phone memory | Peak physical footprint and measurement method | Same; do not substitute the GGUF file size or Linux RSS |
| Demo | Local video file and verified public URL | SUBMISSION.md and form |
| Publication | Logged-out repository/video checks and submission receipt | Launch checklist |

`[PHONE_TOK_S]`, `[PHONE_TTFT_MS]`, and `[PHONE_RAM_GB]` are rehearsal placeholders, not results. Omit them from published copy if no measurement exists. Confidence shown in footage must be the actual decision card. Keep raw measurements; report the sample count and aggregation rather than choosing the fastest take.

## B. Mac and iPhone

The single build procedure is [ios/MAC_DAY_RUNBOOK.md](../ios/MAC_DAY_RUNBOOK.md). Follow it for prerequisites, the pinned llama.cpp framework, unsigned compilation, signing, model installation, and logs. Do not maintain a second command sequence here.

Last historical success: Nov 2 unsigned Simulator build, e0e5b82 source, recorded in commit 613a612. There was no app/core source change between those commits. Skills, media capture, compose sheets, and later fixes were added afterward. A successful old build does not validate this tree.

1. Sync the latest reviewed commit and model. Shipping file SHA-256 must be `a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2` (807,694,080 bytes).
2. Run the runbook's preflight and unsigned Release compilation before spending time on signing. Check actual bundled calibration and skill resources.
3. Sign and install the current Release build. Verify the model name and τ=0.90 on a real decision card. Treat missing or invalid calibration as a build defect.
4. Test first launch with permissions undecided, grant/deny paths, offline behavior, a canceled action, and a confirmed message draft with the intended body. Opening Messages is not delivery; the user still taps Send.
5. Test cloud settings, contact-name masking immediately after permission grant, the prompt disclosure sheet, and the sensitive-text local path. Voice uploads audio before transcript screening. Photo pixels are not anonymized by text masking.
6. Check camera/picker, microphone, App Intents, and each Shortcut used in the video. Apple TV needs the user's configured Shortcut; opening it is not proof of playback.
7. Compare decision prompt token counts with the pinned server path, then collect PGPERF, memory, and thermal evidence using the runbook. Syntax parsing and Linux core tests cannot establish Metal behavior.

Keep the current tree as the build target. If device verification cannot finish in time, use the labeled explainer in section C; an old build must not be presented as proof of features it lacks.

## C. One demo cut

[demo/STORYBOARD.md](demo/STORYBOARD.md) is the **canonical 3:00 timeline and voiceover**. [DEMO_SCRIPT.md](DEMO_SCRIPT.md) contains rehearsal and evidence notes, not a competing timeline. Slides come from `docs/demo/slides.html` and `docs/img/slide_*.png`.

Rehearse the phone's actual behavior. A successful reminder should appear in Reminders; the message composer should contain the right recipient and body. A clarification is a question, not tappable contact choices unless the current UI actually provides them. Optional Apple TV footage replaces an existing skill beat; it does not extend the runtime.

Show only verified behavior and label its source. An edited success demonstration is not a success-rate measurement. Do not claim the system never guesses or never exposes private information: both the confidence gate and scrubber have measured or known limits.

**If the phone is still unavailable:** use the storyboard's labeled terminal/slide variant. Say “phone-sized model” or “iPhone prototype”; state that the current phone build is unverified. Run the existing `pg-cli e2e` against the shipping GGUF if live terminal footage is available, otherwise label the saved results as recorded evidence. Do not simulate an iPhone recording or imply the terminal controls real phone apps.

## D. Video and repository

- Export a video no longer than 3:00. Check audio and text legibility; keep the local original.
- Upload the final video publicly and verify playback while logged out. Choose a title that matches what the footage proves.
- Run `scripts/verify_submission.sh` on the reviewed commit. Read its scope: core checks do not certify a signed iPhone build or a completed submission.
- Review the tracked files and history for secrets before making the repository public. Use a redacting scanner where available; never paste credentials into logs or the submission.
- Make the repository public at submission, then verify README images, source, model release, and links while logged out. Preserve dated history.
- Keep X/social drafts unpublished unless Habib explicitly requests posting. An optional public post is separate from the required repo/video/form work.

## E. Submission text

Form: https://cerebralvalley.ai/e/meta-ai-developer-hackathon/hackathon/submit. Field names and optional prizes must be checked against the actual form. [SUBMISSION.md](SUBMISSION.md) is the detailed evidence packet. Use the following draft only after updating the device-status sentence to the observed result.

**Name:** Pocket Glimmer

**Track / theme:** Indie Developer · Build for Your World

**Team:** Habib (solo), GitHub hxbib

**Repository:** https://github.com/hxbib/pocket-glimmer

**Video:** add the verified public link after recording.

**Short description**

> Pocket Glimmer is an iPhone assistant prototype for moments without a signal. A small Meta model makes typed decisions locally, remembers facts in an on-device database, and asks for clarification or cloud help when confidence is low. Messages require confirmation and open the system composer. The current iPhone build is awaiting device verification.

**Project description**

> I'm Habib, a CS student at Hunter College in the Bronx. My commute is underground, where cloud-only assistants stop working. Pocket Glimmer puts everyday choices and memory on the phone.
>
> Llama-Reflex-1B is a Llama 3.2 1B model trained on 892 soft-label examples from a local Muse Glimmer 30B. It reads answer-letter probabilities in one forward pass per decision. The app combines those choices with local memory, public iOS APIs, and a registry of 36 skills. Many skills hand off to an app or a user-installed Shortcut; this is not unrestricted control of other apps.
>
> On 120 fixed hand-labeled decisions, accuracy rose from about 74% to 82% and calibration error fell from 0.150 to 0.064. At the shipping confidence threshold of 0.90, 44 decisions were accepted and 41 were correct. These measure individual decisions on the Linux build host, not complete phone tasks. Phone speed and memory are still unmeasured.
>
> Difficult text requests can go to Muse Spark 1.3 in Standard mode after a sensitivity check and masking of known names and common identifiers. An optional self-hosted Glimmer endpoint was smoke-tested through the same Swift client. Voice uses cloud transcription before text screening; photo features can send an image to Spark vision and SAM after local checks. The scrubber is imperfect.
>
> Spark Open teacher experiments and a later training sweep were rejected, so the original Glimmer-trained student remains shipping. The repository includes the app, model, training code, evaluation rows, negative results, and reproducible core tests.

Before submitting, replace only statements supported by newly collected evidence. Do not delete the prototype/device caveat until the current app is actually tested. Describe the optional open-weights endpoint if selecting a relevant bonus; saved cloud smoke evidence is not phone execution or prize eligibility.

## F. Final checks

1. Read the submitted text against the actual footage and current project status.
2. Verify the public repository and video without signing in.
3. Submit before the deadline and save the receipt or confirmation.
4. Reopen the submission and verify both links.
5. Keep the local video, tested build, model, and measurement logs for the finals.

If time becomes short, submit a clearly labeled account of the working core and prototype. Leave out unavailable phone measurements and unsupported completion claims.
