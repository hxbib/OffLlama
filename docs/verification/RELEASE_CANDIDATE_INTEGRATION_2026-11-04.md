# OffLlama integrated review repairs

Recorded 2026-11-04. The installed phone source remains `7857cd68`; this report is
not evidence of a new installation or successful phone behavior.

The parent integrated the conversation repairs from `003ab24`, `6396ca4` and
`222ec61`, and the route-context repair from `645fd44`. The chart boundary repair
is `5784c72`. These follow the findings in
[the independent Apple review](CONVERSATIONS_INDEPENDENT_APPLE_REVIEW_2026-11-04.md).

The Send button now clears its captured input only after `AppModel.send` accepts
the request on the main actor, before its first suspension. A separate UI
precheck could pass and then lose a race to another request before `send` ran.
Refused input stays in the composer, and its reason is visible. This is admission
to the current in-memory request, not the unfinished durable input-store wiring.

The route decision uses the calibrated `Network` and `User` context shape.
Retrieved memories remain available to the other decisions and local answers.
The parent strengthened the memory-preservation test so the asserted name occurs
only in saved memory, not in the question. The shipping model, calibration,
threshold and prompt format are unchanged.

## Verification

The integrated Linux core suite executed **385 tests, with one opt-in live test
skipped and zero failures**. The saved output is
[release-candidate-core.txt](release-candidate-core.txt). Command:

```bash
docker run --rm -v /home/habib/pocket-glimmer/core:/src:ro \
  -v /tmp/pg-parent-core-20261104:/build -w /src swift:6.1-noble \
  swift test --scratch-path /build
```

This suite covers the core repairs. It does not typecheck the SwiftUI callback or
prove keyboard layout, contact binding, native composer behavior, file protection
on an iPhone, or model performance. A fresh independent Mac fix-diff review and
an exact-source signed build remain the next gate. Installation is authorized
only after that review and the build/resource checks pass.

The broader CPU route-context benchmark has produced an artifact, but analysis
is not yet integrated. It is diagnostic evidence, not a new held-out model
promotion result or a phone measurement. No candidate has been promoted.
