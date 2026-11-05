# X thread (Most Viral): draft, 5 posts

> **Don't post yet.** Draft copy only. Post only after the demo video is public (checked logged out) and
> Habib says yes. Attach the video to post 1.

Sources: JUDGE_BRIEF.md §8 hooks; README headline table; eval/results/OOS_STRESS.md; eval/skills/SKILL_PROBE.md;
eval/results/SPARK_TEACHER.md; eval/results/ROUND2.md; LEDGER §6. Character counts were measured (X counts a link as
23 characters). Every post is ≤ 280 characters. No emojis. @MetaforDevs is tagged once.

**1/5** (279 chars as X counts links)
```
I'm a CS student in the Bronx and my commute has no signal. So I built OffLlama, a System 1 model on my iPhone: Llama 3.2 1B, distilled from Muse Glimmer 30B, decides offline in one pass and passes hard questions to Muse, its System 2, when online. Built with Llama. @MetaforDevs
```

**2/5** (250 chars as X counts links)
```
It reads answer-letter scores in one pass, then acts, asks or falls back. At the shipping threshold of 0.90: 44/120 test decisions accepted, 41 correct. Those are measured choices, not a guarantee of complete phone tasks. It runs on my iPhone 17 Pro.
```

**3/5** (255 chars as X counts links)
```
On 120 report-only decisions: accuracy 74%→82%, acceptance 15%→51% at the comparison threshold of 0.8, ECE 0.150→0.064. A separate probe rendered 1,000 out-of-scope requests twice: 5/2,000 decision rows falsely confident at the shipping threshold of 0.90.
```

**4/5** (256 chars as X counts links)
```
Bigger teacher did not mean a better student. Spark Open matched my labels better, but its student was overconfident. A second training sweep also failed the repeat-run gate. The shipping 1B still uses Glimmer-only labels. Negative results are in the repo.
```

**5/5** (236 chars as X counts links)
```
Open-world actions, no retraining: 36 registered skills, one runtime decision. “Open Ted Lasso on Apple TV” picks the skill and shows a review card. Confirm opens the Ted Lasso search results, not playback. Repo: github.com/hxbib/OffLlama
```

## Caveats behind each number (if someone asks in replies)
- **44/120, 41 correct:** report-only decisions at τ=0.90. The earlier 10.2% certificate claim is withdrawn: cal180 also selected the model. See docs/EVALUATION_CLAIMS.md. The hand-authored data do not establish a task-success or deployment guarantee.
- **74→82%, 15→51%, 0.150→0.064:** report-only N=120; one item = 0.83 pts. No shipping choice used it, but 13 reporting runs are saved. No temperature
  scaling. Measured with llama-server on a Linux x86 CPU; the same GGUF is the one bundled for the phone.
- **0.25% (5/2,000):** CLINC150 out-of-scope utterances, no gold labels. "False-confident" = conf ≥ τ with a
  handle-locally pick, a proxy, not a measured error rate. The 2,000 rows come from 1,000 unique utterances rendered twice. The untrained 1B scores 0% only because it is never confident (mean
  top confidence 0.46–0.54). Box CPU.
- **25/27:** N=27 author-written smoke test over 26 distinct skills (two Apple TV phrasings). Retrieval 27/27,
  argmax 25/27, 15/27 kept at τ=0.90, 15/15 correct when kept. The model was never trained on skillPick, and
  skillPick is not covered by the cal180 bound. Not gold. Full iOS action behavior is unverified on a device.
- **Apple TV:** on installed build `4376810`, Habib confirmed the review card and that Confirm opens tv.apple.com
  search results for the show. It does not pick an episode or start playback.
- **Round 2:** finished and **rejected** under the same cal180 gate; no variant cleared every run. The shipping model is
  still ep1, Glimmer-only. The Spark Open teacher experiment was rejected too.
- **Privacy:** memory is stored on the phone. For typed turns, an escalation carries the masked request plus masked
  memory lines, and only when the model is unsure. Voice audio uploads to Muse Voice Transcribe before any on-device
  sensitivity check. A permitted photo leaves as an image with EXIF/GPS stripped; question text is masked, pixels are
  not redacted, and the photo gate is heuristic. Don't reply "memory never leaves your phone" or "nothing leaves" for
  voice/photo.
- **Video:** no public demo video exists yet. Do not link one until it is uploaded and checked logged out.
