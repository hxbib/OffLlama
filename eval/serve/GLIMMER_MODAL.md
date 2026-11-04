# Muse Glimmer 30B on Modal: saved smoke evidence

Recorded Nov 4, 2026. These are build-host requests to a cloud H100, not iPhone measurements. The endpoint was live during the recorded session; its present availability has not been rechecked in this audit.

The deployment serves `meta-models/Muse-Glimmer-30B` in bf16 through vLLM 0.33.0 as `muse-glimmer`. Configuration is in `training/serve/modal_glimmer_vllm.py`. The private endpoint and bearer token are not published.

| Saved check | Result | Evidence |
|---|---|---|
| Model discovery | `muse-glimmer` | `glimmer_modal_smoke.json`, `models` |
| Masked landlord-message prompt | `[PERSON_1]` preserved; 2.67 seconds, 122 completion tokens | `placeholder_test` |
| One reasoning response | 6.43 seconds, 300 completion tokens; saved answer is truncated | `reasoning_test` |
| Whole-response throughput for that reasoning request | 300 / 6.43 = 46.7 completion tokens/second | `warm_tok_s`; includes request/prefill overhead, not isolated decoding |
| Unauthenticated access | Saved warm check reports `/v1/models` and `/invocations` 401, `/health` 200 | `auth_without_token`; status summary, not raw HTTP captures |
| Swift `CloudBrain` probe | 2,768 ms for the conformal-threshold explanation | `cloud_probe_swift.txt` |

The JSON also contains a separate 2,854 ms Swift-probe summary for a meeting-reschedule prompt. It is not the same request as `cloud_probe_swift.txt`; do not combine the two timings or answers.

The saved JSON contains two completion samples. It does **not** support the earlier claims of 3/3 graded QA, 0.172-second streaming time to first token, 48.1 decode tokens/second, or an exact 570.8-second cold start. Those claims have been removed. `smoke_glimmer.py` is a runnable smoke script with a different output schema; the saved file is not evidence that every check in that script ran.

## Demo preparation and limits

- The deployment scales to zero. Startup includes loading the weights and starting vLLM; the historical deployment log reported several minutes. No repeatable cold-start benchmark is available.
- Warm the endpoint and verify an authenticated completion before rehearsing. A health response alone does not prove authenticated inference works.
- The Swift client's request timeout can expire during a cold start. The app can then try the next configured brain.
- This smoke establishes connectivity and placeholder preservation on one example. It does not establish general answer quality, privacy reliability, or production availability.
- Scale-to-zero stops GPU compute charges only after the container has actually stopped. The configured idle window is 300 seconds; storage and other charges are separate. Use a dated billing report for spend, not an estimate based on the two request timings.

Deployment and app configuration: [OPEN_WEIGHTS_SYSTEM2.md](../../docs/OPEN_WEIGHTS_SYSTEM2.md).
