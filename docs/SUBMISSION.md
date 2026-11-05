# OffLlama submission packet

**Built with Llama.** Prepared for Habib's final review. The planned track is
Indie Developer and the theme is Build for Your World. Confirm the current form's
fields and eligibility before submitting. No form submission is recorded.

## Name and short description

**OffLlama**

An iPhone assistant for moments without a signal. A distilled Llama 3.2 1B model
makes local decisions and answers simple questions. Typed action drafts connect
supported requests to native iOS features, with explicit messaging confirmation
and optional screened Muse cloud reasoning.

## Project description

I'm Habib, a computer science student at Hunter College. My New York subway
commute often has no signal. I wanted an assistant that could answer locally,
remember useful facts on my phone, and show me what it was about to do.

OffLlama runs Llama-Reflex-1B, a Llama 3.2 1B model distilled from 892 Muse Glimmer
teacher examples and packaged as an 808 MB Q4_K_M file. For structured decisions,
it scores a small set of options rather than generating a long plan. The app
combines those decisions with local memory, explicit request rules, typed action
contracts and a persistent action journal.

Supported integrations include EventKit reminders and calendar, contact lookup,
Messages and Mail compose sheets, and a registry of 36 skills. Available actions use native integrations or direct app links. Eight helper
actions without native implementations are unavailable; they do not launch
missing Shortcuts. External app handoffs can require a final step there. A
message request becomes a visible recipient/body draft. The user confirms and
still controls the final send in the native composer. Opening a composer is not
proof of delivery.

Separate chats keep local answer context organized. Small label-and-value lists
can become HTML/SVG charts rendered inside chat. Optional online text reasoning
uses a configured Muse model after sensitivity checks and identifier masking,
with the outbound request text available for inspection. API keys are kept in
Keychain and concealed in Settings.

On 120 authored Linux decision examples, the shipping model chose the correct
option 98 times, compared with 89 before distillation. At its shipping threshold
of 0.90, it accepted 44 decisions and got 41 of those correct. These are individual
model choices, not end-to-end phone success rates. The repository includes raw
results, negative experiments and the limits of the measurements.

The user has verified a local answer of 4 to “What is 2 + 2?” with Airplane Mode on
and Wi-Fi off. The current release candidate, source `805debf`, passed independent
repair review, a signed Release build, resource checks and installation
on an iPhone 17 Pro. Final UI and action rehearsal on that build is in progress.

## Models and their actual roles

| Model | Role |
| --- | --- |
| Llama 3.2 1B Instruct, distilled as Llama-Reflex-1B | Shipping on-device decision model and local text generation |
| Muse Glimmer 30B | Teacher for the shipping student; also used in later candidate experiments |
| Muse Spark Open | Experimental labeling and training; no Spark-trained candidate has been promoted |
| Configured Muse Standard API model | Optional online reasoning, subject to the app's model validation |
| Muse Voice Transcribe | Optional cloud audio transcription; Apple keyboard Dictation is a separate input option |

Model and dataset licenses are separate from the MIT source-code license.
[Attribution and licensing](LICENSING.md) records them. The project retains its
original GitHub repository and bundle identity under the visible name OffLlama.

## Evidence and limits

- [Benchmarks in plain language](BENCHMARKS.md) includes the meaning, denominator
  and source of each headline number. No real-world error guarantee is claimed.
- [Apple release-candidate verification](verification/FIX_DIFF_REVIEW_805debf.md)
  records the reviewed, built and installed SHA, signatures and resource hashes.
- [Project status](PROJECT_STATUS.md) separates implementation, build checks and
  user-observed phone behavior. Phone speed, memory and thermal figures remain
  unmeasured.
- The action model still falls back too often on unfamiliar phrasing. Application
  rules address explicit messages and charts; universal action reliability is
  not established.
- Existing group chats cannot be resolved by display name. The app cannot control
  arbitrary screens or read other apps' private inboxes.
- The multi-step action core and durable input store have tests but are not wired
  into complete app workflows. They are not demo features.
- Local memory is stored on the phone, but selected screened facts can accompany
  cloud text requests. The scrubber can miss identifiers. Voice uploads audio
  before transcript screening; image features can send recognizable pixels.
- The earlier statistical certification claim was withdrawn because model selection
  reused calibration data. [Evaluation limits](EVALUATION_CLAIMS.md) explains this.

## Recording and links

Use the [three-minute script and action flow](demo/OFFLLAMA_THREE_MINUTE_DEMO.md).
Rehearse the actual installed build. Use a demo contact controlled by Habib, and
cancel the native message composer. Keep keys, private contacts and old chats out
of the recording. Demonstrate only flows that pass rehearsal.

- Repository: [hxbib/pocket-glimmer](https://github.com/hxbib/pocket-glimmer).
  It remains private until final publication.
- Model: [shipping model record](../models/README.md) and Git LFS artifact.
- Video: recording and verified public upload are pending.
- Submission receipt: pending. Check both public links before submitting.

## Optional social-post draft

> I built OffLlama for the parts of my subway commute with no signal. A small
> Llama model runs on my iPhone, with local memory, visible action drafts and
> native iOS handoffs. The repo includes the model, benchmarks and experiments
> that did not make the cut. Built with Llama.

Add the verified repository and video links after publication. This is an
unpublished draft; no social post has been sent.
