# Bundled model resources

- `calibration.json` (committed): the on-device `CalibrationProfile`. Generated 2026-11-04 from the **shipping GGUF**
  (sha256 a5c60a88…82c2) with `pg-cli priors` (content-free letter priors for all 12 static sets + contactPick/eventPick
  with 1–7 candidates = 24 keys; prompt style fewShot). `defaultTau` = **0.90**, the certified operating point
  (LEDGER 6.2; `docs/AFTER_FILL_PROPOSAL.md` Option A). No temperature entries: confidence is the raw softmax of the
  prior-corrected letter logits, exactly the `v2+cc` headline pipeline (`eval/experiments/run_prompt_variants.py`).
  `AppModel` loads it from the bundle at launch; without it the app would run *without* the contextual-calibration
  correction that the headline numbers assume. Regenerate after any model change:
  `swift run pg-cli priors --url http://127.0.0.1:8088 --out app/PocketGlimmer/Resources/Models/calibration.json`
  then set `defaultTau` to the τ chosen on cal180.
- `*.gguf` (gitignored, 770 MB): copy `models/SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf` here to
  bundle it, or drop it into the app's Documents folder via Files sharing (`AppModel.findModel()` checks Documents
  first, then the bundle, and prefers a filename containing "reflex"). Ship the Llama 3.2 LICENSE text with the app.
