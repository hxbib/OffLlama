# Muse Glimmer 30B on Modal: smoke results (2026-11-04, 08:17–08:40 ET)

Endpoint `https://<modal-app>.modal.run/v1` runs vLLM 0.33.0 on 1x H100 80GB with bf16 `meta-models/Muse-Glimmer-30B`, served as `muse-glimmer`. It uses `reasoning_strength=low`, `--language-model-only`, and a 16k context. Raw output: `glimmer_modal_smoke.json`. Script: `smoke_glimmer.py`.

| Check | Result |
|---|---|
| (a) `GET /v1/models` | `["muse-glimmer"]`. **Cold start 570.8 s** (scale-from-zero, 59.6 GB loaded from the Volume, CUDA-graph and torch.compile warmup; first boot, compile cache empty) |
| (b) Assistant.swift escalation prompt with `[PERSON_1]` | **Placeholder kept verbatim**: "Happy birthday [PERSON_1]! Would you like to celebrate with dinner on Friday?" (3.6 s, 165 completion tokens) |
| (c) System-2 items qa04, qa07, qa12 (`run_system2.grade`) | **3/3 PASS** (3.1 s, 10.1 s, 5.1 s) |
| (d) Warm streaming | **TTFT 0.172 s**, decode **48.1 tok/s** (263 tokens in 5.6 s, batch 1) |
| Auth | Without the token: `/v1/models` 401, `/invocations` 401. `/health` 200 (open by design) |

## The app's own CloudBrain code (`pg-cli cloud-probe`, `CloudPresets.modal` → `OpenAICompatibleBrain.complete`)

```
$ pg-cli cloud-probe --url https://<modal-app>.modal.run/v1/ --model muse-glimmer \
    'Known about the user: [PERSON_1] is my manager. User: Write one sentence asking [PERSON_1] to move our 1:1 to Thursday.'
[Modal · muse-glimmer] 2854 ms
Hi [PERSON_1], could we please move our 1:1 to Thursday?
```

## Cost

Modal H100 list price is $3.95–4.56/h, billed per second only while a container is up. `min_containers=0` and `scaledown_window=300` mean **idle costs $0**. Spend for this session: about 30 GPU-minutes (≈ 9.5 min cold boot + ≈ 15 min of smoke traffic + 5 min scaledown), so about **$2–2.30 of H100**. The one-time 60 GB download ran on CPU and cost cents. Not confirmed on the Modal billing dashboard.

## Caveats

- n = 3 Q&A items is a smoke test, not an evaluation.
- Sampling uses the published settings (T = 1.0), so outputs vary from run to run.
- Cold start is long (~9.5 min). Warm the endpoint before a demo with `curl -H "Authorization: Bearer $PG_GLIMMER_TOKEN" $PG_GLIMMER_URL/v1/models`. Expect later cold starts to be shorter now that the compile cache Volume is populated (not measured).
- `CloudBrain.swift`'s 60 s request timeout is fine when warm. It would fail on a cold start, and the app's fallback chain then moves to the next brain.
