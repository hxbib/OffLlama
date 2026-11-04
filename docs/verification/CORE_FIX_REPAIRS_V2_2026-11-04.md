# Core fix review, second repair checkpoint

The independent review at `f77e5e8` verified the input-store F1/F2/F4 repairs,
named-group refusal and repeated-message invariant. Apple file protection remains
unverified on a device. The full review is `CORE_FIX_REVIEW_V2_2026-11-04.md`.

Parent accepted all four correctness warnings and the summary-size nit.

- A complete message with no registry candidates now reaches the compiled message
  review card. It no longer tells the user to confirm a card that does not exist.
- Message channel and group-destination validation share the body-marker pattern.
  Bare `that` begins the body, so mentions of email or group chats remain message text.
- Charts retain every numeric pair in compact comma lists and lists separated by
  spaces. Thousands separators, decimals, negative values and quarter labels have
  regression coverage.
- Saved-input summary size includes the UTF-8 transcript as well as its audio.

Verification on the integrated source used Docker `swift:6.1-noble`.
The suite executed 334 tests, skipped one opt-in live test and had zero failures.
Output is `core-review-v2-repairs.txt`. New tests cover both tool and chat routes
and assert that no effect executes before confirmation. These are scripted core
checks, not live-model or phone evidence. A fresh fix-diff review remains required.

The Mac worker reports an unsigned Release build of `f77e5e8` and another after
the keyboard safe-area change at `e995966`. Neither checkpoint includes these
new repairs or establishes phone layout behavior. The installed source remains
`7857cd68` until a later installation is recorded.

Apple checks still required for RequestInputStore are iOS-SDK compilation and
Darwin ownership tests; protection and backup-exclusion readback for directory,
database, lock and any journal sidecars both after initialization and a later
write; first-unlock behavior; process kill during a claim followed by ownership
recovery; and App Intent process behavior. The core store is not yet wired to
production input admission.
