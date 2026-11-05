# Finish and submit OffLlama

Deadline from the user's plan: **November 5, 2026, 02:00 UTC / November 4, 9 PM ET**.
Keep enough time for recording, upload, public-link checks and the form. The
signed release candidate `4376810` is installed on the iPhone 17 Pro. Composer,
Copy and reminder save were user-confirmed on the preceding build. The new
Apple TV routing and screen cleanup need a final phone check.
See [project status](PROJECT_STATUS.md).

## Freeze the recording build

Use the installed build whose exact source and resources appear in the
[Apple report](verification/RESUMED_FINAL_APPLE_2026-11-05.md).
Do not change model, threshold or features during recording. New candidates
remain experimental. Only fix a defect that blocks the selected demonstration,
and rebuild and retest after any such change.

## Rehearse one complete flow

The canonical [three-minute demo](demo/OFFLLAMA_THREE_MINUTE_DEMO.md) contains
exact actions, narration and substitutions. In order:

1. Recheck the offline answer with Airplane Mode on and Wi-Fi off.
2. Check multi-line keyboard visibility, Chats, history and the storage readback in Settings → Advanced.
3. Check the supplied-number chart appears inline with all three values.
4. Use a demo contact Habib controls. Review the correct recipient and body,
   open the native Messages composer, then cancel and inspect the outcome.
5. Repeat the message request after an ordinary answer. Verify it still produces
   an action card. Confirm a pending card survives relaunch without execution.

No agent should send a message to a real person for rehearsal. A composer or
Shortcut opening is a handoff, not proof of downstream completion. Omit a shot
that has not passed; never substitute a mockup for real phone footage.

## Record and publish the evidence

Record the screen and narration, export no more than three minutes, and retain
the original footage. Keep genuine waits visible or label cuts. Use only the
[measured benchmark figures](BENCHMARKS.md); phone speed and RAM remain unmeasured.
The build runbook's PGPERF procedure is available if time permits a proper cold
run and repeated warm measurements. A single fast take is not a benchmark.

Upload the video publicly, then check playback while logged out. Record its
exact URL in [the submission packet](SUBMISSION.md). Keep the local file too.

## Repository and form

1. Run `scripts/verify_submission.sh` and read the complete result. A skipped
   check or a private repository makes the result incomplete.
2. Review the available redacted tracked-file and history secret scans. Do not
   paste credentials into logs. Check README images, model attribution and links.
3. Publish the repository at final release and verify source, model and video
   access while logged out. Publication exposes the repository history and
   research branches too.
4. Use the prepared [submission text](SUBMISSION.md). Confirm fields and optional
   categories on the actual form. Habib should review the final wording against
   the footage before submission.
5. Submit before the deadline, save the confirmation and recheck both public
   links. No completed submission should be inferred from passing build tests.

Form recorded in the project plan:
[Meta AI Developer Hackathon submission](https://cerebralvalley.ai/e/meta-ai-developer-hackathon/hackathon/submit).
The form and eligibility have not been re-verified in this preparation pass.
Social copy remains a draft until Habib explicitly requests posting.

The [Mac runbook](../ios/MAC_DAY_RUNBOOK.md) remains the build procedure. This file
owns final preparation order; it does not duplicate build commands or the script.
