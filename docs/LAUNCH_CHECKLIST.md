# Launch checklist

Deadline: **Nov 4, 2026, 9:00 PM ET** (Nov 5 02:00 UTC). No grace period. Target submit: **5:00 PM ET Nov 4**.
Hour-by-hour plan with exact commands and the form text: **docs/FINAL_HOURS.md**.

## Timeline (Nov 4)
- [ ] iPhone build + PGPERF numbers (FINAL_HOURS §B), hard cut-off 11:30 AM; otherwise the Mac fallback.
- [ ] Record and edit the 3:00 video (FINAL_HOURS §C, docs/DEMO_SCRIPT.md).
- [ ] **Upload the video as public.** Open the link in a logged-out / private window: it plays, audio is fine.
- [ ] **Public repo:** final secret scan, make it public, check the link logged out. README and both images render.
- [ ] **Dated commits:** history shows the work inside Oct 26 – Nov 4 (first commit Oct 31). Never squash or rewrite.
- [ ] No unfilled placeholders: phone-measurement tags may remain only in FINAL_HOURS.md and the DEMO_SCRIPT on-screen
      cells (the exact grep is in FINAL_HOURS §A). `scripts/verify_submission.sh` checks this plus secrets and tests.
- [ ] Habib does the final read of docs/SUBMISSION.md in his own words.
- [ ] **Submit hours before the deadline.** Then reopen the submission page and check the video and repo links logged out.
- [ ] **Nov 9 finals:** the video file (local copy), the offline build on the iPhone (re-install: free-team builds expire
      after 7 days; airplane mode works; memories seeded), charger, mirroring cable.
- [ ] *Optional:* 30–45 s X clip tagged @MetaforDevs for Most Viral (engagement counted until Nov 8, 11:59 PM ET). Hooks
      in docs/research/JUDGE_BRIEF.md §8. **Post only with Habib's explicit yes.**

## Claims discipline (check before submitting)
- [x] Headline numbers = frozen held-out test split only (N=120). Selection on the calibration split only (N=180).
- [x] Any "51%" is labeled "at τ=0.8 (test N=120)". The shipped threshold is τ=0.90 (certified ≤10.2% on cal180).
- [x] Every conformal-bound quote states the exchangeability assumption.
- [x] No temperature scaling claimed anywhere (the confidence is the raw letter softmax).
- [x] "Haven't found prior art" only for the whole combination; certified routing thresholds themselves are prior art
      (Uddin & Bauer, ACL 2026 SRW; docs/research/RELATED_WORK.md).
- [x] Memory is stored only on the phone, but escalation sends masked request + masked relevant memory. No "never
      leaves your phone" wording.
- [x] Box-CPU numbers labeled as box CPU. No phone speed claimed until measured.
- [x] Meta Model API in Standard mode only (`muse-spark-1.3`, core/Sources/PocketCore/CloudBrain.swift:73). BYO key is a
      README footnote only.
- [x] Open Weights bonus is not pitched or flagged.
- [x] "Built with Llama" in README header, packet and app Settings → About; the on-device model is called Llama-Reflex-1B.

## Build side: done
1. [x] Before → after decision accuracy: 0.74 → 0.82 (frozen test N=120, v2+cc; AFTER_FLOOR.md)
2. [x] ECE 0.150 → 0.064 + reliability charts; risk–coverage AURC 0.148 → 0.085; conformal assumption stated
3. [ ] On-device decode tok/s + TTFT + peak RAM on the iPhone: needs the phone (FINAL_HOURS §A/§B6)
4. [x] Share of eval decisions handled on device: 37% at τ=0.90 (44/120), 51% at τ=0.8 (61/120); cal180 36% at τ=0.90
5. [x] Teacher-labeled examples used: 892 (1,006 labeled, 114 low-confidence dropped)
6. [x] SAM 3.1: not built
7. [x] Architecture diagram image: docs/img/architecture.png
8. [x] GGUF size: 807,694,080 bytes (808 MB, 770 MiB). App size: measured from the device build if wanted
9. [x] Install path: build from source (app/project.yml + XcodeGen, ios/MAC_DAY_RUNBOOK.md)
10. [x] Dated new-work list: docs/SUBMISSION.md "What I built during the event"
11. [x] UI elements the script needs (docs/DEMO_SCRIPT.md, all present in code; verify on the device build)
12. [x] Bundled calibration.json (contextual-calibration priors from the shipping GGUF, defaultTau 0.90)

## Habib side
13. [ ] Airplane-mode footage on the physical iPhone (or the labeled Mac fallback)
14. [x] Teacher is Muse Glimmer 30B only (Apache-2.0). Muse Spark Open was tested as a teacher and rejected on Nov 1 ($11.06 on Baseten); a round-2 Spark Open sweep ran Nov 4 (outcome: eval/results/ROUND2.md).
15. [x] Cloud calls use `muse-spark-1.3` Standard mode (code default; Settings shows it)
16. [x] Primary user + moment: Habib, Hunter College CS student in the Bronx, no signal on the subway
17. [ ] Real-use evidence (optional): one honest sentence if you used it today; never invented
18. [ ] Public YouTube URL, tested logged out
19. [x] Team: Habib (solo), GitHub hxbib
20. [ ] Approval: whether to post a public X demo clip
