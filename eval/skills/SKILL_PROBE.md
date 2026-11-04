# skillPick probe: the open-world action decision on the shipping GGUF (Nov 4 2026, box CPU, not iPhone)

The skills layer (docs/SKILLS.md) adds ONE new decision type, `skillPick`, built at runtime exactly like `contactPick`:
retrieval picks ≤7 candidate skills, the shipping Llama-Reflex-1B answers one multiple-choice question in one forward
pass, and the same letter-logit confidence is compared with τ. **The shipping model was never trained on this set**;
this probe measures how well the trained decision behaviour transfers to an unseen option set. It is a smoke test
(N=27: one author-written utterance per skill plus two Apple TV phrasings added at 8:20, not gold-standard, not part of cal180/test120), run with
`pg-cli skill-probe` (core/Sources/pg-cli/main.swift) against llama.cpp master 13ec8f6, `-t 4 -c 4096`.

| readout | retrieval hit (expected skill in top-7) | argmax correct | handled @τ0.90 | correct on handled | handled @τ0.80 | correct on handled |
|---|---|---|---|---|---|---|
| fewShot, no priors (`skill_probe_shipping_tau090_nocc.txt`) | 25/25 | 22/25 | 12/25 | 12/12 | — | — |
| **fewShot + cc priors from `calibration.json` (`skill_probe_shipping_tau090_cc.txt`, what the app ships; N=27 re-run 8:22)** | **27/27** | **25/27** | **15/27** | **15/15** | — | — |
| (earlier N=25 run, same settings) | 25/25 | 23/25 | 14/25 | 13/14 | 22/25 | 21/22 |

The two argmax misses with priors are near-synonyms, not failures of the mechanism: "play some jazz on spotify" →
`music_play` (Apple Music) instead of `spotify_play`, and "reply haha nice to every reel Sam sends me" → `imessage_send`
instead of `instagram_autoreply` (below τ, so the app asks "Did you mean…" rather than acting). Every message/social
skill still forces an explicit confirmation regardless of confidence (registry hard rule).

Reading: an untrained-for-this-set 1B picks the right one of 7 open-world phone actions 25/27 (93%) and, at the
certified τ=0.90, keeps 15/27 on device with 15/15 correct. The demo line "open the latest episode of Severance on Apple TV"
is picked at 0.986 (`appletv_play`, kept on device); the Shortcut "PG Play on Apple TV" does the playback (docs/SKILLS.md). The same behaviour the gold set measures (route,
toolChoice, contactPick) transfers to a dynamic action space with no retraining. Priors matter here as elsewhere
(+1 argmax, +2 handled). These numbers are NOT covered by the cal180 conformal bound (different distribution); the
roadmap item is a hand-labeled skill set of ≥100 items so skillPick can get its own τ and bound.

Files: `eval/skills/skill_probe.jsonl` (items), the two `.txt` outputs, `app/PocketGlimmer/Resources/Models/calibration.json`
(now 31 prior sets incl. `skillPick#2…#8`, defaultTau 0.90).
