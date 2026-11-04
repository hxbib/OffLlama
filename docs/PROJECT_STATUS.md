# What Pocket Glimmer does

Pocket Glimmer is an iPhone assistant prototype. A small Meta model chooses everyday actions on the phone. A local database remembers facts the user shares. Harder questions can go to a larger Meta model online.

The project includes the app, its trained model, training tools, evaluation data, and a demo kit. It is not yet a verified finished iPhone release. The last successful unsigned Simulator build used older source at `e0e5b82`; the success was recorded in `613a612`, with no app/core source change between those commits. The current app needs a Mac build and physical-device testing.

## What the user can ask for

| Request | Implementation | Current evidence and limits |
|---|---|---|
| Remember a fact, recall it, or correct it | Local SQLite memory, rule-based fact extraction, retrieval, conflict decisions, and a profile | Swift core tests. This is not unlimited understanding or automatic learning of new model weights. |
| Set a reminder or calendar event | Local routing and argument extraction, then Apple's EventKit | Core planning tests. Current permission prompts, dates, and actual saves need phone testing. |
| Find a contact or calendar event | Contacts/EventKit search, then a confidence-gated choice | Core decision tests. Some ambiguous requests ask for clarification. |
| Draft a message | Contact lookup and a confirmation step, then the system Messages composer | The user still taps Send. Opening a composer does not mean a message was delivered. Offline drafting does not provide offline delivery. |
| Open an app or use a supported phone action | A registry of 36 built-in skills using public links, Shortcuts, and native handlers | Skill selection and argument tests. Many actions need an installed Shortcut, an account, or a final tap in the destination app. |
| Play a show in Apple TV | A user-configured Shortcut receives the show name | Playback is device-dependent and unverified. Opening Shortcuts does not prove that the named Shortcut exists or that playback began. |
| Summarize email or a document | The user shares text or picks a PDF/text document | No automatic access to the Mail inbox. No general search through other apps' private files. |
| Create a chart | Local parsing of supplied labels and numbers into HTML/SVG bars | Core tests. This is a limited chart generator, not a general coding agent. |
| Answer a simple question offline | The same small model generates text, with an answerability fallback on uncertain routes | Limited general ability. Decision accuracy does not measure answer quality. |
| Reason about a difficult question | Optional Muse Spark 1.3 or a self-hosted Muse Glimmer 30B endpoint | Recorded Swift/API smoke tests. Requires internet, credentials, and an available server. Glimmer does not run on the phone. |
| Speak a request | Cloud transcription, followed by the normal text-request path | Recorded API smoke tests. Audio leaves the phone before its transcript can be checked for sensitive content. |
| Ask about a photo or outline an object | Local image preparation/OCR, a sensitivity check, then cloud vision or SAM | Recorded API smoke tests. Current camera, picker, and display behavior need phone testing. |
| Receive a timely reminder or brief | User-created Shortcuts automations call an App Intent and the local nudge logic | Core tests. This is not an always-running agent, and the nudge model is weak on the small evaluation set. |

## What the measurements mean

The main test contains 120 hand-labeled multiple-choice decisions. These are individual choices such as selecting a contact or deciding whether to ask for confirmation. They are not 120 complete real-world phone tasks.

| Saved measurement | Result | Scope |
|---|---|---|
| Decision accuracy | 98 of 120 correct, about 82%, versus about 74% before training | Frozen evaluation rows. One item changes the result by about 0.83 percentage points. |
| Decisions accepted at the shipping threshold of 0.90 | 44 of 120 accepted, 41 of those correct | The model hands off or takes a fallback for the other decisions. |
| Earlier comparison threshold of 0.80 | 61 of 120 accepted, 56 correct | This is the source of the 51% figure. It is not the shipping threshold. |
| Calibration error | 0.064 after training, versus 0.150 before | Lower means confidence better matches observed correctness on this test. |
| Shipping model file | 807,694,080 bytes, about 808 MB | File size, not the app's running memory use. |
| Phone speed, memory, and battery life | Not measured yet | Linux CPU and cloud GPU numbers cannot replace iPhone measurements. |

Sources are [the shipping evaluation](../eval/results/AFTER_FLOOR.md), [results at the shipping threshold](../eval/results/PER_TYPE_TAU090.md), and [the model record](../models/README.md). The earlier 10.2% certificate claim was too strong because model selection reused the calibration data. [The evaluation correction](EVALUATION_CLAIMS.md) explains the nominal calculation, sampling limits and future independent protocol. No error guarantee for new phone tasks or the skill registry is established.

## What remains before calling the phone app finished

1. Build the current source with Xcode and the pinned llama.cpp framework.
2. Install a signed Release build with the exact shipping model and bundled calibration.
3. Verify first launch, permissions, offline actions, confirmation/cancellation, cloud privacy behavior, and Shortcuts on the phone.
4. Measure phone time to first token, decoding speed, peak memory, and thermal behavior.
5. Record and upload the real demo, make the repository public at submission, and submit the form.

The [Mac runbook](../ios/MAC_DAY_RUNBOOK.md) owns the build steps. [Final hours](FINAL_HOURS.md) owns the submission steps. No phone measurements, video link, or completed submission should be inferred from passing core tests.

## Boundaries of the original vision

The original request included an assistant that could do virtually anything on an iPhone without losing intelligence. This project does not meet that full ambition. A small local model is less capable than a large reasoning model. Public iOS integrations do not give this app unrestricted control of Instagram, X, Mail, or arbitrary third-party screens.

The implementation can prepare supported actions and ask the user to finish actions that another app controls. It cannot independently read all messages, automatically answer every reel, log into arbitrary apps, claim daily rewards, or recover through any sequence of screens. The current request handler is primarily a single-request decision chain, not a general multi-step planning and recovery agent.

Memory stays in a local database, but selected memory text can accompany an online question. The scrubber masks known names and common identifier patterns; it cannot guarantee removal of every private detail. Audio and image contents are not fully anonymized. Users who need those contents to stay local must avoid the corresponding cloud features.
