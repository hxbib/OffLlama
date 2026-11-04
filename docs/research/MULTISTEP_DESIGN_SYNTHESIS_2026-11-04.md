# Multi-step implementation choice

Parent read both completed designs end to end before implementation. Sources are
`/tmp/offllama-multistep-20261104/wonder/design.md` and
`/tmp/offllama-multistep-20261104/grok/design.md`. These are design proposals,
not running features. The parent comparison uses `MULTISTEP_DESIGN_RUBRIC.md`.

| Criterion | Wonder | Grok | Parent judgment |
|---|---:|---:|---|
| One claim authority and dependency correctness | 3 | 4 | Grok explicitly gates both existing claim branches; Wonder's separate claimStep risks bypass and its broad sheet boundary includes saved mail drafts. |
| Typed bounded proposals and evidence | 4 | 4 | Both distinguish actual model decisions from deterministic gates. Grok's event/reminder-only evidence is the smaller executable contract. |
| Native review and recovery | 4 | 4 | Both preserve partial progress and one communication confirmation. Grok reviews every plan step before execution. |
| Implementation size and ownership | 3 | 3 | Wonder duplicates header specs and attempt dependency data; Grok adds derived payload hashes, invalidation and cross-request acknowledgement beyond the first unit. |
| Reproducible verification | 4 | 4 | Both separate fake-effects contracts from real-model and device evidence. Neither has device proof. |
| Total, design judgment out of 25 | 18 | 19 | Grok is the base after the corrections below. |

The chosen first unit keeps all steps in `action_attempts`, one request ID and
the existing `EffectLedger.claim` authority. It accepts two or three typed
steps, with calendar/reminder producers and message/mail consumers. Every step
starts awaiting review. An optional dependency names one earlier verified local
write. An independent step has no edge and does not wait for its neighbor.
Unsupported steps remain visible and unclaimable. No automatic executor or
plan-wide approval is added.

The useful Wonder graft is late materialization. A dependent message has no body
until its predecessor has an immutable verified receipt. The generated body is
then saved as a new draft revision for review. Edits before the producer settles
therefore require no invalidation graph. Claim checks the predecessor, the saved
body and the displayed revision in one transaction. Mail draft, sheet acceptance,
URL opening, failure, cancellation, claimed and ambiguous states cannot produce
a dependency value.

Use the existing typed disposition/receipt instead of duplicating it in new
verified-boundary and payload-hash columns. A bounded plan metadata column and
explicit plan-size marker distinguish plans from legacy rows, including corrupt
metadata. A partial unique index applies only to plan steps so legacy duplicate
request/step pairs do not invalidate migration. Repeated staging for one request
returns the existing plan; it never appends new work. Count limits include
claimed and ambiguous plans, and refuse new work without eviction.

Rejected for this unit are cloud planning, arbitrary dependency fields, a separate
controller, sheet/handoff success dependencies, a new plan execution path,
automatic retry, timed deletion, and cross-request destination acknowledgements.
The last item can be designed separately; this unit promises no replay of an
attempt, not proof that two separate user requests refer to the same intent.

First artifact is a core plan API and behavioral tests using fake effects and
file-backed SQLite. It must cover dependency blocking, exact receipt-derived
body, independent order, stale revisions, concurrent confirmation, cancellation,
receipt-write failure, restart, corrupt metadata, idempotent staging and legacy
migration. Assistant parsing, app plan cards, live-model routing and iPhone
acceptance are later required units. The Mac conversation owner retains its
AppModel/Views scope and the approved local-context parameter in Assistant.
