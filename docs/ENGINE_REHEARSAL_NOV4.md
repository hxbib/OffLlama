# Linux rehearsal of the app's inference engine

On November 4, the app's `LlamaCppEngine.swift` compiled and ran against llama.cpp commit `ddf48f85c933c1f438212a02eb21e7b001d2d37d` with Swift 6.1 on Linux. The check used the shipping 807,694,080-byte GGUF (`a5c60a88…82c2`) and bundled calibration (`b9ce25b5…0a8f1`), τ = 0.90, with prefix reuse off. This validates the C API bridge on CPU; it does not typecheck UIKit/SwiftUI or validate Metal.

The harness instantiated the real engine, `Reflex`, in-memory SQLite and `Assistant`, with the built-in skill registry. Contacts were fixtures: Mom, Sam Lee and Sam Ortiz. Action execution was a recorder. No message, Shortcut or network request was sent. Each request began with a fresh memory database. These are development rehearsals, not independent benchmark examples.

| Request | Route confidence | Skill confidence | Observed result |
|---|---:|---:|---|
| Text Mom I'll be home by 8 | 0.826 | 0.810 | Clarification; no action |
| Text Mom that I'll be home by 8 | 0.868 | 0.805 | Clarification; no action |
| Text Mom: I'll be home by 8 | 0.819 | 0.787 | Clarification; no action |
| Text Sam I'm running late | 0.801 | 0.989 | Contact choice 0.573: asks “Which Sam?” |
| Open the latest episode of Severance on Apple TV | 0.762 | 0.995 | Plans `appletv_play` for Severance and asks for confirmation |

The first rehearsal exposed a routing problem: uncertain explicit message commands never tried the skill chooser and instead generated a local draft. The app now gives those commands the existing gated skill-selection path. A low-confidence skill asks for clarification; it does not lower the threshold or execute the argmax. The frozen model, priors and τ were unchanged. The “that” and colon forms were checked because the argument parser already supports them; neither repaired the model's uncertainty.

Saved decision output is [DEMO_REHEARSAL_NOV4.txt](../eval/results/DEMO_REHEARSAL_NOV4.txt). The complete temporary logs are `/tmp/pocket-glimmer-takeover/demo-real-engine.log`, `demo-real-engine-after.log` and `demo-real-engine-final.log`. A later text-only edit changed the clarification opening to “Did you mean”; the decisions above are unaffected.

The original message-body and routing regressions, threshold behavior, mandatory confirmation and shared-text masking are exercised by `TakeoverRegressionTests`. The integrated core run passed 108 tests, with one opt-in live API test skipped. App Swift files passed syntax parsing only. The Mac must still build the current app, verify resources, compare tokenization and letter scores, and rehearse actual permissions and action sheets. Do not use a message-compose demo take unless the device actually reaches that sheet.
