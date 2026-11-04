# Packaging review follow-up

The independent report is [MAC_SYMBOL_REVIEW_2026-11-04.md](MAC_SYMBOL_REVIEW_2026-11-04.md).
It reviewed `571d80d`/`15ab389`; its statements about the then-blocked Mac build
are historical. Later real build/install evidence is in
[MAC_INSTALL_CHECKPOINT_2026-11-04.md](MAC_INSTALL_CHECKPOINT_2026-11-04.md).

- F1: corrected the ledger's stale retest sentence and appended a checkpoint
  distinguishing the actual Mac symbol retest from the Linux/mock fixture suite.
  The earlier TSV row remains an original snapshot.
- F2: accepted. `nm` command failure now reports that the tool failed to verify
  symbols and retains its diagnostic output. Missing or undefined symbols keep
  the separate missing-symbol result. Output is still drained, and a nonzero
  `nm` result cannot pass even if it printed the required symbol.
- F3: all current evidence explicitly labels the 88-fixture suite Linux/mock.
  It does not establish iPhone runtime behavior.

The updated full fixture run passed 88 checks with zero failures. Output is
`mac-prep-reviewed-diagnostics.txt`; command: `bash ios/test_mac_prep.sh`.
The reviewer separately mutation-tested the old implementation and observed the
two intended regressions. That is distinct from this fixed-suite run.

Candidate B's trail audit also correctly identified batch-written TSV times.
The ledger now states that `ts` is the checkpoint recording time, and points to
source artifacts/thread items for exact event ordering. Its bounded inability
to find the user's 6 PM leeway instruction was a scope limitation: the other
review found that instruction at the earlier user item 2584.
