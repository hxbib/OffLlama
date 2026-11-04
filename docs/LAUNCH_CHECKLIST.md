# Launch checklist

Deadline: **Nov 4, 2026, 9:00 PM ET (Nov 5, 02:00 UTC)**. Target submit: **5:00 PM ET**. Start the Mac work when the device becomes available. [FINAL_HOURS.md](FINAL_HOURS.md) owns submission preparation; [ios/MAC_DAY_RUNBOOK.md](../ios/MAC_DAY_RUNBOOK.md) owns build steps.

## Evidence available

- [x] Shipping ep1 GGUF and its exact hash; τ=0.90 and bundled priors.
- [x] Saved test120 decision results, calibration calculations, and negative training results.
- [x] Integrated Linux run on Nov 4 at 15:46 UTC: 108 Swift tests executed, one skipped, no failures; 7 Python tests. Later privacy regressions and repairs require a new final run.
- [x] 36 built-in skills and a 27-item diagnostic skill probe. It is not a gold benchmark or a risk certificate.
- [x] Voice, Spark vision, and SAM core integrations with saved API smoke evidence. iOS capture/display remains unverified.
- [x] Optional self-hosted Glimmer endpoint with saved connectivity and placeholder-preservation smoke evidence. Recheck availability before a live demo.
- [x] Round 2 finished and rejected. Glimmer remains the only teacher of the shipping model; Spark Open supplied experimental labels.

## Still required

- [ ] Integrate and verify the takeover repairs; push the reviewed, passing commit.
- [ ] Compile the current iOS app with Xcode and inspect built resources.
- [ ] Sign, install, and exercise the Release build on the phone, including first-session permissions, cancellation, message body, and cloud privacy.
- [ ] Verify the demo's Shortcuts and Apple TV handoff on the actual device.
- [ ] Measure phone latency, decoding, memory, and thermal state. Publish only recorded values.
- [ ] Record the canonical [storyboard](demo/STORYBOARD.md), or use its clearly labeled no-phone variant.
- [ ] Upload the video publicly and verify playback while logged out.
- [ ] Review secrets/history, publish the repository at submission, and verify source/model links while logged out.
- [ ] Habib reads the final submission in his own words; submit and retain confirmation.

## Claims to verify before publication

- [ ] Current code/core checks are distinguished from Xcode and physical-device verification.
- [ ] 51% accepted is labeled τ=0.80; shipping τ=0.90 accepts 44/120 with 41/44 correct.
- [ ] Statistical calculations are accompanied by their assumptions and selection limitations; no general phone-risk guarantee.
- [ ] CLINC uses 1,000 unique utterances wrapped into 2,000 decision rows; the result is a proxy, not 2,000 independent gold judgments.
- [ ] Voice uploads audio before transcript screening. Photos may upload recognizable pixels. Text masking is incomplete.
- [ ] Memory is stored locally, but relevant masked text can be sent during escalation.
- [ ] Opening an app or Shortcut is described as a handoff; sending, playback, and downstream completion require separate evidence.
- [ ] No performance figure from Linux or a cloud H100 is labeled an iPhone result.
- [ ] “Built with Llama” and model/dataset attribution accompany the release.
- [ ] Prize categories match the actual form. Social posting still requires Habib's explicit instruction.

For the finals: keep the local video, exact model, tested app, logs, charger, and mirroring cable. Check signing validity before the event.
