# What OffLlama does

OffLlama is an iPhone assistant prototype. A small Meta model makes bounded decisions on the phone. A local database remembers facts the user shares. Harder questions can go to a configured Muse model online. The repository and bundle identity retain the original Pocket Glimmer name.

The project includes the app, its trained model, training tools, evaluation data, and a demo kit. Source **`4376810` is reviewed, signed and installed on the iPhone 17 Pro**. The [Apple release report](verification/RESUMED_FINAL_APPLE_2026-11-05.md) records matching model/calibration hashes, a signed Release build, and successful installation. Its review found no critical or warning issues in the repair diffs. It did not launch or exercise the phone UI.

The user previously confirmed an answer of **4 to “What is 2 + 2?” with Airplane Mode on and Wi-Fi off**. On `805debf`, the user confirmed that the multi-line composer and whole-message Copy work, and that reminder review and the actual Reminders save both work. Apple TV still produced generated chat instead of a card. Parent repair `b5fdfb0` now passes 398 Linux core tests (one skipped, zero failures), including explicit Apple TV routing regardless of the model's route choice. A fresh River02 review found no blocking regressions. That repair and the UI cleanup are installed as `4376810`; the user confirmed that “Open Ted Lasso on Apple TV” shows a review card and Confirm opens the search results. Chart, Chats and storage-readback checks are still open.

Core verification is **398 executed, one skipped, zero failures on Linux**, and **399 executed, one skipped, zero failures in the Apple review**. These platform-specific runs do not establish complete phone task success. The repository is still private; public video and submission confirmation are pending.

## What the user can ask for

| Request | Implementation | Current evidence and limits |
|---|---|---|
| Remember a fact, recall it, or correct it | Local SQLite memory, rule-based fact extraction, retrieval, conflict decisions, and a profile | Swift core tests. This is not unlimited understanding or automatic learning of new model weights. |
| Set a reminder or calendar event | Local routing and argument extraction, then Apple's EventKit | Core planning tests. Current permission prompts, dates, and actual saves need phone testing. |
| Find a contact or calendar event | Contacts/EventKit search, then a confidence-gated choice | Core decision tests. Some ambiguous requests ask for clarification. |
| Draft a message | Contact lookup and a confirmation step, then the system Messages composer | The user still taps Send. Opening a composer does not mean a message was delivered. Offline drafting does not provide offline delivery. |
| Use a supported phone action | A registry of 36 built-in skills with native handlers and public links | Eight unimplemented helper actions are unavailable. Native and link actions do not require preinstalled Shortcuts. Destination apps may require an account or final tap. |
| Find a show on Apple TV | An encoded tv.apple.com search link | User confirmed the review card and search results on the iPhone at `4376810`. No latest-episode or playback claim. |
| Summarize email or a document | The user shares text or picks a PDF/text document | No automatic access to the Mail inbox. No general search through other apps' private files. |
| Create a chart | Local parsing of supplied labels and numbers into HTML/SVG bars, displayed inline | Core tests and independent parser probes pass. Rehearse `Make a chart: rent 1200, food 400, transit 130`. Some loose comma/value-first forms still lose labels. This is a limited chart generator. |
| Answer a simple question offline | The same small model generates text, with an answerability fallback on uncertain routes | Limited general ability. Decision accuracy does not measure answer quality. |
| Reason about a difficult question | Optional Muse Spark 1.3 or a self-hosted Muse Glimmer 30B endpoint | Recorded Swift/API smoke tests. Requires internet, credentials, and an available server. Glimmer does not run on the phone. |
| Speak a request | Apple keyboard Dictation, or the separate Muse Voice Transcribe upload | Apple input availability depends on device settings. The Muse path has recorded API smoke tests; audio leaves the phone before transcript screening. |
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

1. Complete manual acceptance of the installed build, including keyboard visibility, Chats, inline chart, repeated-message intent, native composer cancellation and the protection/backup readback in Settings → Advanced.
2. Verify permission variants, EventKit saves, cloud privacy and any Shortcut selected for the demo on the phone.
3. Measure phone time to first token, full-request time, peak memory and thermal behavior before publishing phone performance claims.
4. Wire and verify durable busy-input/voice/camera admission and the multi-step plan core before presenting those as working app features. They are currently core units only.
5. Continue improving action-to-chat fallback beyond the explicit message, reminder and calendar commands now protected. The route-context repair improves a CPU diagnostic but still leaves many action requests below the threshold.
6. Record and upload the real demo, finalize the public repository, verify public links and submit the form.

The [Mac runbook](../ios/MAC_DAY_RUNBOOK.md) owns the build steps. [Final hours](FINAL_HOURS.md) owns the submission steps. No phone measurements, video link, or completed submission should be inferred from passing core tests.

## Boundaries of the original vision

The original request included an assistant that could do virtually anything on an iPhone without losing intelligence. This project does not meet that full ambition. A small local model is less capable than a large reasoning model. Public iOS integrations do not give this app unrestricted control of Instagram, X, Mail, or arbitrary third-party screens.

The implementation can prepare supported actions and ask the user to finish actions that another app controls. It cannot independently read all messages, automatically answer every reel, log into arbitrary apps, claim daily rewards, or recover through any sequence of screens. The current request handler is primarily a single-request decision chain, not a general multi-step planning and recovery agent.

Memory stays in a local database, but selected memory text can accompany an online question. The scrubber masks known names and common identifier patterns; it cannot guarantee removal of every private detail. Audio and image contents are not fully anonymized. Users who need those contents to stay local must avoid the corresponding cloud features.
