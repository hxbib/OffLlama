# X thread (Most Viral): draft, 5 posts

> **Don't post yet.** This is draft copy only. Post only once the demo video is **public** (checked logged out), and
> **only after Habib says yes**. The draft does not claim a published video or a working phone build. If the final
> video is a phone run, post 1 may say "on my iPhone"; if it is the labelled Mac fallback, keep "phone-sized" and label
> the run as Mac. Attach the video to post 1; attach `docs/img/slide_05.png` or `slide_06.png` to posts 2/3 if you like.

Sources: JUDGE_BRIEF.md §8 hooks; README headline table; eval/results/OOS_STRESS.md; eval/skills/SKILL_PROBE.md;
eval/results/SPARK_TEACHER.md; eval/results/ROUND2.md; LEDGER §6. Character counts were measured (X counts a link as
23 characters). Every post is ≤ 280 characters. No emojis. @MetaforDevs is tagged once.

**1/5** (268 chars)
```
I'm a CS student in the Bronx and my commute has no signal. So I built a phone-sized 1B Meta model that knows when it doesn't know: Llama 3.2 1B, distilled from Muse Glimmer 30B, decides offline and asks Muse Spark only when it's unsure. Built with Llama. @MetaforDevs
```

**2/5** (253 chars)
```
It doesn't write out its decisions. Each is one forward pass over the answer-letter logits; a Learn-Then-Test threshold then picks act or ask. At τ=0.90: 36% kept on device, error bound ≤10.2% on those, assuming new requests resemble my calibration set.
```

**3/5** (242 chars)
```
I taught a 1B model to say "I'm not sure." On 120 held-out decisions: accuracy 74%→82%, decisions kept on-device 15%→51% (conf ≥0.8), calibration error 0.150→0.064. On 2,000 out-of-scope requests, it confidently kept just 5 (0.25%) at τ=0.90.
```

**4/5** (268 chars)
```
Bigger teacher, worse student. Muse Spark Open (816B) matched my hand labels better than Muse Glimmer 30B, but the 1B it taught was overconfident: 13.7% vs 10.2% bound. Round 2 (Spark Open labels, H100 LoRA sweep) finished rejected too. ep1, Glimmer-only, still ships.
```

**5/5** (262 chars as X counts it)
```
Open-world actions, no retraining: 36 phone skills, one runtime decision. "Open the latest episode of Severance on Apple TV" picks the skill, then hands off to a user-installed Shortcut. Smoke: 25/27 argmax, 15/15 correct when kept. Repo: github.com/hxbib/pocket-glimmer
```

## Caveats behind each number (if someone asks in replies)
- **36% / ≤10.2%:** calibration split N=180, 64/180 kept, 0 errors, Learn-Then-Test δ = 0.1. A bound under
  exchangeability, not a guarantee. A Nov 4 re-run gave 10.4% (run-to-run noise).
- **74→82%, 15→51%, 0.150→0.064:** frozen held-out test N=120; one item = 0.83 pts (95% CI ≈ ±7 pts). No temperature
  scaling. Measured with llama-server on a Linux x86 CPU; the same GGUF is the one bundled for the phone.
- **0.25% (5/2,000):** CLINC150 out-of-scope utterances, no gold labels. "False-confident" = conf ≥ τ with a
  handle-locally pick, an upper bound on errors. The untrained 1B scores 0% only because it is never confident (mean
  top confidence 0.46–0.54). Box CPU.
- **25/27:** N=27 author-written smoke test over 26 distinct skills (two Apple TV phrasings). Retrieval 27/27,
  argmax 25/27, 15/27 kept at τ=0.90, 15/15 correct when kept. The model was never trained on skillPick, and
  skillPick is not covered by the cal180 bound. Not gold. Full iOS action behavior is unverified on a device.
- **Apple TV:** `appletv_play` only hands to the user-installed "PG Play on Apple TV" Shortcut. The app cannot detect
  whether it is installed, cannot confirm playback, and cannot guarantee the latest episode. The 0.986 probe is a
  skillPick score, not a playback result. Fallback is a manual TV-app search or a labelled clip.
- **Round 2:** finished and **rejected** under the same cal180 gate; no variant cleared every run. The shipping model is
  still ep1, Glimmer-only. The Spark Open teacher experiment was rejected too.
- **Privacy:** memory is stored on the phone. For typed turns, an escalation carries the masked request plus masked
  memory lines, and only when the model is unsure. Voice audio uploads to Muse Voice Transcribe before any on-device
  sensitivity check. A permitted photo leaves as an image with EXIF/GPS stripped; question text is masked, pixels are
  not redacted, and the photo gate is heuristic. Don't reply "memory never leaves your phone" or "nothing leaves" for
  voice/photo.
- **Video:** no public demo video exists yet. Do not link one until it is uploaded and checked logged out.
