# Launch checklist

Deadline: **Nov 4, 2026, 9:00 PM ET** (Nov 5 02:00 UTC). No grace period. Target submit: midday Nov 4.

## Timeline
- [ ] **Record by Nov 3.** Final cut of the 3:00 video done Nov 3.
- [ ] **Upload the video as public a day early** (by Nov 3). Open the link in a logged-out / private window and check that it plays and the audio is fine.
- [ ] **Public repo:** make it public, then check the link logged out. README and docs render.
- [ ] **Dated commits:** history shows the work inside Oct 26 – Nov 4. Don't squash away the dates.
- [ ] Every `[TBD]` and `[PLACEHOLDER]` in `docs/SUBMISSION.md` and `docs/DEMO_SCRIPT.md` is filled or cut. Delete the internal rubric map from the packet.
- [ ] Habib does the final read/edit of the submission in his own words.
- [ ] **Submit hours before the deadline** (midday Nov 4 ET).
- [ ] After submitting, open the submission page and check the video and repo links.
- [ ] **Nov 9 finals:** bring the video file (local copy) + the offline build on the iPhone (airplane mode works, memories seeded), charger, and a mirroring cable.
- [ ] *Optional:* 30–45 s X clip tagged @MetaforDevs, using the "Active Memory that never leaves your phone" hook. **Post only with Habib's explicit yes.**

- [ ] **Headline numbers = frozen held-out test split only.** After-distillation accuracy and ECE in the video, packet and README come from the frozen test split. Never quote dev-set or calibration-split figures (e.g. the 120-row dev conformal number) as headlines.
- [ ] "Built with Llama" and "Built with Muse Spark Open" visible in README header and packet; on-device model called Llama-Reflex-1B everywhere.

## Blockers: build side
1. [ ] [PLACEHOLDER: before→after decision accuracy, N, task set, baseline definition] (baseline done: N=36, 0.53)
2. [ ] [PLACEHOLDER: ECE before→after + reliability chart image; calibration method; conformal assumption stated] (baseline done: ECE 0.101, `docs/img/reliability_baseline.png`)
3. [ ] [PLACEHOLDER: on-device decode tok/s + TTFT + peak RAM on A19 Pro, Q4, stated context length]
4. [ ] [PLACEHOLDER: % of eval tasks handled fully offline vs escalated]
5. [ ] [PLACEHOLDER: N teacher-labeled examples actually used]
6. [ ] [PLACEHOLDER: SAM 3.1 built yes/no]
7. [ ] [PLACEHOLDER: architecture diagram image] (Mermaid source exists in README)
8. [ ] [PLACEHOLDER: GGUF size MB + app size MB]
9. [ ] [PLACEHOLDER: install/run path (TestFlight or build steps)]
10. [ ] [PLACEHOLDER: dated new-work vs OSS list, from commit history]
11. [ ] UI elements the script needs (see TODO in `docs/DEMO_SCRIPT.md`)

## Blockers: Habib side (Mac, keys, approval, people)
12. [ ] [PLACEHOLDER: airplane-mode proof clip recorded on the physical iPhone 17 Pro]
13. [ ] [PLACEHOLDER: final license determination: does the Muse Model License allow Spark Open outputs as distillation training data? Read the license text. If unclear, use Glimmer-only labels]
14. [ ] [PLACEHOLDER: confirmation that cloud calls use `muse-spark-1.3` Standard mode (keys/config)]
15. [ ] [PLACEHOLDER: primary user + moment (must be firsthand)]
16. [ ] [PLACEHOLDER: real-use evidence: tester quote or self-use log]
17. [ ] [PLACEHOLDER: public YouTube URL, uploaded by Nov 3 and tested logged out]
18. [ ] [PLACEHOLDER: team names for submission]
19. [ ] Approval: whether to post a public X demo clip. Also ask on Discord whether an open-weights bonus exists.
