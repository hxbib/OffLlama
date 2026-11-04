# X thread (Most Viral): draft, 5 posts

> **Don't post yet.** Post only once the demo video is **public** (checked logged out), and **only after Habib says yes**.
> Posts 1 and 5 say "iPhone". If the video shows a Mac run instead of the phone build, change "on my iPhone" to "a
> phone-sized model" (JUDGE_BRIEF §8). Attach the video to post 1; attach `docs/img/slide_05.png` or
> `slide_06.png` to posts 2/3 if you like.

Sources: JUDGE_BRIEF.md §8 hooks; README headline table; eval/results/OOS_STRESS.md; eval/skills/SKILL_PROBE.md;
eval/results/SPARK_TEACHER.md; LEDGER §6. Character counts were measured (X counts a link as 23 characters). Every
post is ≤ 280 characters. No emojis. @MetaforDevs is tagged once.

**1/5** (267 chars)
```
I'm a CS student in the Bronx and my commute has no signal. So I put a 1B Meta model on my iPhone that knows when it doesn't know: Llama 3.2 1B, distilled from Muse Glimmer 30B, decides offline and asks Muse Spark only when it's unsure. Built with Llama. @MetaforDevs
```

**2/5** (253 chars)
```
It doesn't write out its decisions. Each is one forward pass over the answer-letter logits; a Learn-Then-Test threshold then picks act or ask. At τ=0.90: 36% kept on device, error bound ≤10.2% on those, assuming new requests resemble my calibration set.
```

**3/5** (242 chars)
```
I taught a 1B model to say "I'm not sure." On 120 held-out decisions: accuracy 74%→82%, decisions kept on-device 15%→51% (conf ≥0.8), calibration error 0.150→0.064. On 2,000 out-of-scope requests, it confidently kept just 5 (0.25%) at τ=0.90.
```

**4/5** (267 chars)
```
Bigger teacher, worse student. Muse Spark Open (816B) matched my hand labels better than Muse Glimmer 30B, but the 1B it taught was overconfident: error bound 13.7% vs 10.2%. I shipped the Glimmer student. The other failures (2 epochs, 1-bit Glimmer) are in the repo.
```

**5/5** (~261 chars as X counts it)
```
Open-world actions, no retraining: 35 phone skills, one runtime decision. "DM Sam on Instagram: congrats" picks the skill, confirms, opens the DM link and copies the text (iOS lets no app press Send). Smoke test: 23/25 right skill. Repo: github.com/hxbib/pocket-glimmer
```

## Caveats behind each number (if someone asks in replies)
- **36% / ≤10.2%:** calibration split N=180, 64/180 kept, 0 errors, Learn-Then-Test δ = 0.1. A bound under
  exchangeability, not a guarantee. A Nov 4 re-run gave 10.4% (run-to-run noise).
- **74→82%, 15→51%, 0.150→0.064:** frozen held-out test N=120; one item = 0.83 pts (95% CI ≈ ±7 pts). No temperature
  scaling. Measured with llama-server on a Linux x86 CPU; the same GGUF ships on the phone.
- **0.25% (5/2,000):** CLINC150 out-of-scope utterances, no gold labels. "False-confident" = conf ≥ τ with a
  handle-locally pick, an upper bound on errors. The untrained 1B scores 0% only because it is never confident (mean
  top confidence 0.46–0.54). Box CPU.
- **23/25:** N=25 smoke test, one author-written utterance per skill. The model was never trained on skills. Not
  covered by the conformal bound.
- Don't reply "memory never leaves your phone". Escalations carry scrubbed memory lines. Say "memory is stored on the
  phone; the cloud only sees masked text, and only when the model is unsure."
