# Action validation checkpoint

The compiled catalog owns action arguments, confirmation requirements, and result
classification. `ActionValidation` checks values before execution and after edits.
A high model score cannot bypass those checks. This does not prove that the model
understands every possible request.

The generated [contract manifest](ACTION_CONTRACTS.json) describes every compiled
capability, including the unavailable app-alarm capability. It records required
and optional fields, prerequisites, decisions, and observable success evidence.
Regenerate it from `core` with `swift run pg-cli action-contracts`.
The bundled registry is generated separately with `pg-cli dump-skills`.

## Enforced behavior

- Unsupported argument keys stop an effect instead of being discarded.
- Missing or invalid fields keep the review card unconfirmable. Text edits retain
  the original value, including punctuation, instead of silently truncating it.
- Text fields have a 2,000-character application limit. Shared input has a
  separate 24,000-character limit and belongs to the request that supplied it.
- Durations require explicit units, must be positive and finite, and cannot
  exceed 24 hours. Compound durations are supported.
- URLs require HTTP or HTTPS, a host, and no embedded credentials or whitespace.
- Local reminder and calendar writes require an exact future time. Ambiguous
  clock phrases and unsupported timezones require correction. Calendar creation
  currently means a one-hour event without invitations.
- External app and Shortcut handoffs always require review. The result reports
  OS acceptance, not delivery, playback, or downstream completion.
- Narrow request guards ask for clarification on unsupported recurrence,
  location triggers, message options, and explicit on/off requests for toggle-only
  Shortcuts. These guards are not a complete natural-language parser.
- Translation requires both text and a target language.

Compiled contracts use version 2, except reminder, calendar and alarm datetime contracts at version 3. Pending cards with a different contract version cannot execute under
the new policy. Users must start a new request. User-defined handoffs retain their
reviewed contract snapshot so missing required fields stay required after restart.

## Verification and limits

The resumed Linux run passed 183 Swift tests with one opt-in live test skipped.
The action tests cover invalid durations and URLs, required fields, editing,
unsupported options, exact text, ambiguous times, external review, and confirmed
reads that cannot consume another request's document.

The privacy fixes mask remembered partner names, prevent provider failover after
cancellation, reject malformed cloud settings, and preserve outbound-payload
visibility when a cloud failure falls back locally. Mock classifiers and fake
executors test these contracts, not model accuracy or real phone effects.

Swift syntax parsing passed for the 18 app files. It is not an Apple-platform
typecheck. Xcode, real permissions, Messages, Mail, Shortcuts, phone latency,
memory, and thermal behavior remain unverified.

Busy-request admission remains open. A busy `AppModel.send` still refuses a new
request before saving it. Passing shared text explicitly fixes cross-request
document consumption, but does not implement durable deferred input. Voice and
camera admission also require the follow-up described in
[request-input grounding](research/REQUEST_INPUT_GROUNDING.md).

The round-3 graders reject altered message casing, unexpected argument fields,
unconfirmed execution, missing outcome traces, duplicate effects, and wrong
terminal states. The combined data, evaluation-harness, and grader checks pass
22 tests. New benchmark categories without enough labeled source groups remain
unmeasured and block promotion where the protocol requires them.
