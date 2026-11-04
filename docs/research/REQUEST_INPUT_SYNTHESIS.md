# Durable request input implementation contract

Choose candidate A's separate protected SQLite store, incorporating the cross-judge's
ownership fixes and candidate B's truthful caller behavior. The full proposals and
cross-judge are archived beside this document. Neither proposal is accepted verbatim.

The store owns one immutable body per existing `UserRequestID`. Body and metadata
are committed together before checking busy. No global inbox slot, auto-drain,
background execution, fake effect attempt or second action executor is permitted.

An exclusive advisory lock for the canonical store directory is held for the entire
owner lifetime. A process-local registry also prevents a second owner in one process.
Only that owner can recover, claim, retry, write a transcript, complete or interrupt.
A non-owner can stage and read summaries; it can discard only staged/interrupted rows.
An epoch or PID is not proof that an earlier owner has stopped. Recovery after acquiring
the lock converts abandoned claims to interrupted without executing anything.

Use fixed origin and interruption enums. Body kind, origin and creation metadata are
immutable. Transcript is write-once while claimed. Terminal transitions remove body,
transcript, previews and sensitive free-form metadata atomically. Terminal rows cannot
regain a body. Store timestamps, identifiers and coded status in text-free tombstones.

Default limits are 24 hours for text/share/voice, eight active requests and 8 MiB total
active payload, with 24,000 text characters and 2 MiB per WAV. Active includes staged,
claimed and interrupted. Refuse new work at capacity; never evict saved requests.
Camera capture is a required subsequent caller slice, with a 1 MiB image and one-hour
TTL plus question, concept, mode and OCR text. Tombstones expire after 30 days. Avoid
forensic deletion claims; device file protection and backup exclusion need phone proof.

The first implementation unit is core store, ownership and meaningful concurrency/
crash-boundary tests only. Do not change AppModel, Assistant or the effect ledger in
that unit. Require tests for two live owners, lock release, one claim winner, body
immutability, terminal resurrection refusal, write-once transcript, interrupted caps,
Unicode/NUL handling, expiry cleanup, read-only summaries and no automatic execution.

The next unit makes `Assistant.handle` require the ingress ID, adds a read-only ledger
query per request, and wires explicit resume. Any resumed datetime capability requires
a review card showing capture time/phrase and the newly resolved instant. Never
silently reinterpret a relative date and auto-act. Claimed/ambiguous effect state blocks
retry; an awaiting effect resurfaces its existing card; settled work is not executed again.

An interrupted input with no effect attempt may be retried only explicitly, after
proven owner loss and a warning that a cloud read, memory write or transcription may
repeat. Voice must be claimed before transcription and reuse a saved transcript.
The composer and microphone must eventually remain available while busy, preserve
input on persistence refusal, and show Resume/Discard only for eligible requests.
Model-not-ready must not claim input. No save claim is valid without a committed body.

Camera must resume through its own Glimpse flow. Do not route a JPEG through text
`Assistant.handle`. Until camera integration lands, durable capture is not complete.
The effect ledger's `_sharedText` retention is also separate work. Clear it at settled/
cancelled read boundaries and apply a documented expiry policy before claiming the
entire app's retained input is covered by this store.
