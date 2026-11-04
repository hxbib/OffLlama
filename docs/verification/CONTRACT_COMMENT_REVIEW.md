# Contract comment review adjudication

Review source: b41ffae. Parent applied repairs on top of cd6fa2e.
Original report: /tmp/pocket-glimmer-takeover/contracts-comments-v1/REPORT.md.

Accepted factual corrections: removed the unverified installed-alarm-recipe claim;
rewrote the compiled catalog export description; identified the Mach-O data as a
fixture whose file command is mocked; corrected the exact-slot matching description.
Retained useful public API, command/body parsing, relative-duration and test-purpose
comments. Extracting helpers or deleting accurate explanations solely to reduce
comments was not necessary. The existing pipe protocol is preserved for compatibility;
changing it requires changing and verifying the user-installed Shortcut too.

Behavioral repairs from the review:
- L2 slot equality and L4 effect equality now preserve types recursively, so booleans,
  integers and floats cannot silently substitute for each other.
- The benchmark's canonical action inventory reads docs/ACTION_CONTRACTS.json and
  includes unavailable actions for refusal coverage. Parallel native/handoff lists
  and legacy tool aliases are removed; no callers used those lists.
- The documented benchmark validator now executes the grader-safety tests. Protocol
  thresholds, splits, labels and frozen protocol JSON were not changed.
- CloudBrainTests uses an actor for both shared call counters, removing unchecked
  Sendable assertions over mutable storage.

Validation: 7 grader tests and the benchmark corruption checks pass; 18 data/duration
checks pass; 3 CloudBrainTests pass using Swift 6.1 in Docker. The compiled catalog
export exactly matches the 38 committed contracts. Shell syntax and diff checks pass.
No Xcode or iPhone execution was performed by this review integration.

Remaining work: separate contract/privacy review, durable busy-input admission,
phone training repairs and model validation, and actual signed iPhone acceptance.
A passing action inventory is not fixture coverage or an end-to-end action result.
