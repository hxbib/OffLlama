# Action review repairs

The independent review examined `b41ffae`. Its report is
[CONTRACT_REVIEW_2026-11-04.md](CONTRACT_REVIEW_2026-11-04.md).
The parent checked the findings against the current source after `b7f2d37`.
This record separates repairs from work still required. No iPhone behavior is
verified by these Linux checks.

| Finding | Current disposition | Evidence or next check |
|---|---|---|
| C1: immediate local read fallback hides outbound text | App projection now retains the payload and labels an attempted cloud request. Confirmed read fallback uses the same label. | `AppModel.send` and `confirm`; syntax parse passes. Actual privacy-sheet interaction needs Xcode/device verification. |
| C2: default shared document ignored on non-tool routes | Shared text now goes through document reasoning when the skill override does not handle it and the general route is non-tool. Complete document screening still gates cloud requests. | Six new tests include all three non-tool routes, cloud payload capture, sensitive-document withholding, fallback, and interrupted reads. |
| W1: cancelled/failed reads claim nothing was sent | A read without a verified result becomes ambiguous. Cancellation propagates; repeat confirmation does not execute it again. Both immediate and restored summaries disclose a possible cloud request. | `SharedReadRecoveryTests`; existing effect-recovery suite. |
| W4: receipt-write failure can follow a completed effect | App confirmation errors now state that completion could not be verified and ask the user to check the destination. They no longer claim that nothing changed. | Source inspection and syntax parse only; device storage-failure behavior remains unverified. |
| C3/C4/W2: calendar constraints, time extraction, recipient/attachment variants | Open. Repair parsing and conservative validation, including the common phrases reproduced by review. | Review's repro summary and scratch tests. |
| W3: attempted provider names absent from local fallback | Open. Exact outbound text is retained on successful fallback, but failed-provider attribution is not yet represented. | `CloudBrainChain`, `ReadResult`, `AssistantTurn`, app disclosure. |
| W5: mixed responsibilities in EffectLedger | Deferred maintainability work. A file split alone does not repair the reproduced behavior. | Keep functional repairs focused and independently reviewed. |
| W6: stale model lookup and implementation notes | Open. Correct current operator docs without rewriting historical evidence. | App prefers bundled shipping model over Documents. |
| Review nits | Pending individual adjudication. | Do not silently promote hypothetical findings into verified phone defects. |

The full updated Swift suite executes 189 tests, with one opt-in live test skipped
and zero failures. The six added tests pass independently. The modified app file
passes `swiftc -frontend -parse`; this is not an Apple SDK typecheck. Commands and
outputs are retained in `run65-core-tests.txt` and `run65-app-parse.txt`.

The review's budget, Glimmer-completion, and split-status warnings refer to its
older checkout. The current `ORCHESTRATOR_LEDGER.md` already records the $100
Modal and $54.99 Spark-expansion caps, integrated 2,915 Glimmer labels, and rejection
of the overlapping first phone split. Those records do not establish a promoted
candidate or completed new training run.

The separate Mac packaging repair passed all 88 Linux/mock fixtures. A subsequent
real Mac run confirms the defined llama symbol. Compilation is still blocked by
disk space, an unbundled model, and missing provenance for the existing framework.
