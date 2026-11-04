# Phone acceptance record

No row in this document has been run on a phone. Use it with
[MAC_DAY_RUNBOOK.md](MAC_DAY_RUNBOOK.md) after the current source builds and installs.
The available phone is an iPhone 17 Pro. Record its actual iOS version and OS build separately from the Mac's installed iOS SDK.

## Build record

| Field | Recorded value |
|---|---|
| Test date and operator | Not recorded |
| iPhone model, iOS version and OS build | Not recorded |
| Git commit, clean/dirty checkout | Not recorded |
| Xcode version, SDK, Release configuration | Not recorded |
| Built-app resource verification log | Not recorded |
| GGUF SHA-256 and calibration SHA-256 | Not recorded |
| Prefix reuse setting, thermal state, battery/charging | Not recorded |
| Network state, configured cloud model, permission states | Not recorded; never record keys |

For each case, record the exact input, observed result, recovery attempt, and evidence path.
Use `PASS`, `FAIL`, `HANDOFF`, `BLOCKED`, or `NOT RUN`. A handoff can pass a handoff-specific
check, but does not prove the downstream task finished. A missing permission is not a pass.

## Current-build checks

| ID | Exercise | Required evidence | Initial status |
|---|---|---|---|
| P01 | Cold launch with the exact bundled model and calibration | One model load; usable Assistant; decision card reports τ=0.90; no calibration fallback | NOT RUN |
| P02 | Launch a separate unsigned test build with a missing or invalid calibration | Startup refuses the incompatible configuration before loading the model; useful error | NOT RUN |
| P03 | Deny Contacts, then grant limited access and change the selected contacts | Clear restricted-contact behavior; next text/photo request uses the currently allowed synthetic names for masking | NOT RUN |
| P04 | Ask for a message, inspect recipient/body, cancel the confirmation or compose sheet | No send; cancellation reported; next request remains usable | NOT RUN |
| P05 | Confirm one planned action twice rapidly, then tap its old card again | At most one side effect or composer for that card; no stale pending action | NOT RUN |
| P06 | Test a missing contact, duplicate names, missing body, and an unavailable Messages/Mail composer | Clarification or accurately labeled handoff; no silently chosen wrong recipient; full body preserved | NOT RUN |
| P07 | Create a clearly dated reminder and calendar event in a test calendar | Inspect actual title, date/time, timezone and calendar; save response alone does not establish crash recovery | NOT RUN |
| P08 | Use an ambiguous date, revoke EventKit permission, and retry after an interruption | No invented time or duplicate write; recoverable failure. Current source gaps must be fixed before marking PASS | NOT RUN |
| P09 | Invoke Ask/Handle Text/Action from Shortcuts while another request is running | Each invocation has its own saved input and explicit resume/discard; never a previous chat reply or automatic replay. Requires deferred-input implementation | NOT RUN |
| P10 | Share distinct text twice, cancel the document picker, and relaunch after a share | No wrong-document summary; cancellation and lost/expired input are explicit; another share works | NOT RUN |
| P11 | Benign cloud request that retrieves synthetic sensitive memory; document with sensitive content near its end | Outgoing-request inspection shows filtered memories and no upload after a blocked segment; local memory remains available | NOT RUN |
| P12 | Voice local-only setting, denied mic access, and a toggle changed before release | No audio upload when local-only; recording stops cleanly; transcript failure is recoverable | NOT RUN |
| P13 | Photo permission denial, sensitive-page check, SAM concept containing a synthetic contact name | Permission recovery, accurate pixel-upload disclosure, masked concept; no zero-retention claim | NOT RUN |
| P14 | Installed, missing, and renamed test Shortcuts; Apple TV handoff | Record each app transition and exact status. URL open is not execution, playback, or a completion receipt | NOT RUN |
| P15 | Request while offline, then after reconnecting; cloud error/timeout using synthetic content | Honest local reading limit or error; UI becomes usable; no automatic replay of an external action | NOT RUN |
| P16 | Kill and relaunch during confirmation, after a write, and during an external handoff | Exercise the integrated durable action journal. Record restored drafts, observed local effects, ambiguous external handoffs, and absence of automatic replay. Core tests alone do not establish phone recovery | NOT RUN |
| P17 | Large text, VoiceOver, a non-hold interaction, and supported-language input | Controls usable and labels truthful; unsupported language/gesture behavior recorded as a limitation | NOT RUN |
| P18 | Export telemetry and the distillation file | Ordinary CSV omits request context by default; distillation export discloses its context and device-backup exposure | NOT RUN |
| P19 | Two same-name contacts, each with multiple phone numbers/email addresses; choose the second contact and a non-first method | Composer uses exactly the reviewed contact and method; removing or editing that method before confirm pauses for review | NOT RUN |
| P20 | While a document request runs, share two other distinct documents and complete a recording | Each input is separately retained with its own request; no overwrite, cross-request summary or automatic effect; explicit resume/discard. Requires deferred-input implementation | NOT RUN |
| P21 | Explicit timezone, DST gap/overlap and device timezone change; inspect selected calendar | Unsupported interpretation asks for correction; draft and result show full resolved time/zone and destination calendar; inspect actual saved item and alarm | NOT RUN |
| P22 | Correct the same memory several times, forget its active version, then relaunch | Selected fact and all predecessor revisions absent; unrelated facts survive. Telemetry/export/backup retention is separately disclosed, not represented as erased | NOT RUN |
| P23 | Export CSV, make new decisions, then export again without restarting | Second export includes the new rows and still omits context | NOT RUN |

Use synthetic contacts, documents, and events. Message cancellation can be tested without
sending. A send test needs an explicitly approved test recipient; record the compose
result separately from delivery. Do not interpret a Shortcut's arbitrary result string as
proof of an external service's state.

## Performance record

Follow the runbook's one cold and five consecutive warm runs. Retain all `PGPERF` lines,
complete request wall time, token counts, peak physical footprint and thermal state. Keep
local-generation timing separate from routing, memory retrieval, decisions and cloud time.
Do not substitute Linux or cloud measurements for this record.

## Release decision

Record the exact tested commit and known failing or blocked cases. Publish only the
capabilities supported by their observed outcomes. A successful build, model decision,
or single happy-path run does not establish the recovery behavior in P08, P15 and P16.
