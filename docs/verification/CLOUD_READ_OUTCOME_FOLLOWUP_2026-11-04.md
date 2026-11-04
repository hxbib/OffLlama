# Cloud read outcome follow-up

The follow-up to the shared-read review retains screened outbound text when a
provider cancels, local fallback also fails, or a completed read cannot save its
receipt. `CloudRequestFailure` carries that text and cancellation state while its
display description excludes the provider error body. `EffectResult` can carry
known text when the journal cannot confirm completion.

Ambiguous attempts now appear during launch recovery without becoming runnable.
Interrupted cloud-capable reads disclose that a request may already have been
sent. The confirmation UI clears stale on-device labels, keeps known payloads,
and reloads a still-awaiting card after an error when the ledger is readable.
Edit failure copy no longer claims that an already-persisted edit changed nothing.

Verification on the parent checkout used Docker `swift:6.1-noble` with the source
mounted read-only and `/tmp/pg-parent-core-20261104` as the build scratch directory.

```sh
docker run --rm -v /home/habib/pocket-glimmer/core:/src:ro \
  -v /tmp/pg-parent-core-20261104:/build -w /src swift:6.1-noble \
  swift test --scratch-path /build
```

The full suite executed 210 tests, skipped one pre-existing opt-in live test, and
reported zero failures. Seven new behavioral cases cover actual mocked transport
payload equality, cancellation, failed local fallback on document and direct-answer
paths, failed receipt writes, failed ambiguity writes, recovery and no replay.
No paid provider call was made. Evidence is `cloud-read-outcomes-core-tests.txt`.

`swiftc -frontend -parse /app/AppModel.swift` in the same Swift image exited zero.
This checks syntax only. Xcode typechecking, the privacy sheet and phone behavior
remain unverified for this follow-up.

The messaging worker owns `AppModel.send`. Its immediate-error projection still
needs to consume the new typed error after integration. That path currently loses
the payload in the app even though the core now carries it. Attempted-provider
attribution remains open. A crash before a durable receipt can lose the exact text;
launch recovery gives an uncertainty warning and does not invent a saved payload.
These limitations prevent a claim that every privacy finding is closed.
