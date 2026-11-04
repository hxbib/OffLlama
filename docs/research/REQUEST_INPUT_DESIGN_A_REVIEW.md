# Parent review of request-input candidate A

Candidate: `/tmp/pg-input-design-20261104/a/design.md`, received 2026-11-04.
The parent read the proposal and has now read completed candidate B at
`/tmp/pg-input-design-20261104/b/design.md`. Cross-review is running under the
standing River assignment; no design is selected and no input-store
implementation has started.

The separate protected store, immutable per-request body, explicit Resume,
atomic claim, and effect-ledger reconciliation fit the accepted requirements.
The implementation must resolve these gaps before adopting the proposal:

1. **Recovery ownership.** A one-shot flag per store instance cannot prove a
   claimed row belongs to a dead process. Confirm the actual App Intent process
   boundary and store lifetime, and encode ownership so reopening cannot make
   live work retryable. A new epoch alone also does not prove the old owner is dead.
2. **Relative times.** The proposal reinterprets relative times at resume and
   assumes every effect gets a confirmation card. Some contracts permit immediate
   action. Preserve the captured time context or require review of the newly
   resolved time; a saved request must not silently shift dates or deadlines.
3. **Deletion claims.** The proposed terminal update omits `source_label` and
   `interrupt_reason`, which may contain filenames or user text. Clear sensitive
   metadata too. Separate logical deletion, SQLite cleanup, and device protection
   evidence; do not promise forensic erasure.
4. **Body invariants.** The sample trigger allows a nulled terminal row to regain
   a body, and does not cover every identity/type field. Enforce valid state/body
   combinations and terminal transitions, including one-time transcript storage.
5. **Replay wording.** No effect row does not prove that no cloud request occurred.
   Explicit retry after interruption must disclose possible repeated transcription
   or cloud reads. A new process must never resume work automatically.
6. **Capture scope.** Camera remains unresolved in slice 1. A second implementation
   slice is required before claiming durable preservation across all capture flows.
   Avoid synchronous multi-megabyte writes on the UI actor where practical.

The candidate's reference to 136 tests is stale. Current parent evidence is 189
Swift tests executed, one opt-in test skipped, zero failures. Its proposed tests
are a plan, not executed evidence. The next comparison should judge both designs
against these concrete failure cases and minimize new lifecycle machinery.
