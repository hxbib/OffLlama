# Voice and camera: Muse Voice Transcribe, Muse Spark vision, SAM 3.1

> November 4 hardening: SAM concepts are masked and requests set `store: false`; the latter is schema-verified, not a new live API result. Standard mode is a training-use setting, not a promise of zero server retention. Voice audio uploads before transcript screening; image pixels are not anonymized.

Added 2026-11-04. Three Meta Model API capabilities with different privacy paths. Photos get an on-device
sensitivity check and metadata stripping before upload. Voice sends the recording for cloud transcription first;
only the returned transcript then enters the normal text decision path. Spoken names and other audio contents
are not masked before transcription. Neither metadata stripping nor text masking anonymizes image pixels.

| Capability | What the user does | What runs |
|---|---|---|
| **Muse Voice Transcribe** | Holds the mic, speaks, lets go | The audio is transcribed once. The transcript then goes into `Assistant.handle` exactly like typed text, so the same Reflex decisions, telemetry, confirmation rule and sensitivity check before any Spark call apply |
| **Muse Spark 1.3 vision** | Camera → "Ask Spark" | Reflex sensitivity check on the request (plus on-device OCR text) → EXIF/GPS strip → masked question + image → `muse-spark-1.3` |
| **SAM 3.1** | Camera → "Find" / "Both" | Same gate → `sam-3.1` returns a box and a pixel mask per match. Masks are decoded **on the phone** (Swift port of Meta's one_bit codec) and drawn over the photo |

"Both" chains them, which is the pairing [Meta's own SAM docs recommend](https://dev.meta.ai/docs/media-segmentation):
Spark answers the question **and names the object to outline** (`CONCEPT: yellow sticky note`), then SAM 3.1 segments
that concept. Two Meta models work as one tool, and one gate covers both calls.

Code: `core/Sources/PocketCore/MetaMultimodal.swift` (Linux-buildable; 13 offline tests + 1 opt-in live test in
`core/Tests/PocketCoreTests/MetaMultimodalTests.swift`); app: `app/PocketGlimmer/Capture/VoiceCapture.swift`,
`app/PocketGlimmer/Capture/CameraGlimpse.swift`, `app/PocketGlimmer/Views/GlimpseView.swift`.

## Endpoints, verified live on 2026-11-04

`GET /v1/models` with Habib's key lists `muse-voice-transcribe-1.0`, `sam-3.1`, `muse-spark-1.3` (plus
`muse-wonder-1.0`, `muse-image-1.0`, `muse-spark-1.2`, `muse-spark-1.1` and the `-contributor` ids we never use).

| Capability | Path | Model id | Request shape | Verified by |
|---|---|---|---|---|
| Speech to text | `POST /v1/asr/transcribe` | `muse-voice-transcribe-1.0` | `multipart/form-data`: part `request` = JSON `{"model","audioEncoding":"WAV","mode":"PUSH_TO_TALK","languageBias":["English"]}`, part `audio` = WAV (mono 16-bit PCM, 16 or 24 kHz; ≤ 10 min, ≤ 32 MB). Response `{sessionId, transcript, audioDurationMs, turns}` | [api-reference/voice/transcribe](https://dev.meta.ai/docs/api-reference/voice/transcribe), [voice/schemas](https://dev.meta.ai/docs/api-reference/voice/schemas); live: `eval/meta_api/voice_transcribe.json` (200) |
| Image Q&A | `POST /v1/chat/completions` | `muse-spark-1.3` | user `content: [{"type":"text"}, {"type":"image_url","image_url":{"url":"data:image/jpeg;base64,…"}}]`, `reasoning_effort: "low"` | [image-understanding](https://dev.meta.ai/docs/image-understanding#chat-completions); live: `eval/meta_api/vision_describe.json`, `vision_whiteboard.json` (200) |
| Segmentation | `POST /v1/responses` | `sam-3.1` | `input: [{type:"message", role:"user", content:[{"type":"input_text","text":"<noun phrase>"}, {"type":"input_image","image_url":"data:image/jpeg;base64,…"}]}]`, `metadata: {"mask_encoding":"one_bit","include_confidence":"true"}`, `stream:false`. Output is token text `<0f>ID<\|box;x1=…;y1=…;x2=…;y2=…;w=…;h=…;c=…\|><\|mask;x=0;y=0;c=…;data=H,W,!payload\|>,…` | [media-segmentation](https://dev.meta.ai/docs/media-segmentation), [sam/segmenting](https://dev.meta.ai/docs/sam/segmenting), [sam/reading-segmentation](https://dev.meta.ai/docs/sam/reading-segmentation); live: `eval/meta_api/sam_segment.json`, `sam_segment_bars.json` (200) |

Probed and **not** supported (kept so nobody re-guesses them): `POST /v1/audio/transcriptions` → 404
(`probe_audio_transcriptions.json`); `sam-3.1` on `/v1/chat/completions` → 404 *"The model `sam-3.1` is not available on
this endpoint. Use /v1/responses."* (`probe_sam_chat_completions.json`).

Prices (from [pricing-rate-limits](https://dev.meta.ai/docs/pricing-rate-limits)): Spark $1.25 / $4.25 per M in/out
tokens; Voice Transcribe $0.18 per audio hour; SAM 3.1 $2.50 per 1,000 images. `muse-image-1.0` (image generation,
$0.01/image) is also on the API. It is **not integrated**: a private assistant has no use for it today.

## Photo checks and voice handling in `MultimodalGate`

1. **Sensitivity Reflex runs first, on device.** It's the same trained `OptionSets.sensitivity` decision (Decision.swift
   unchanged) on `User: <intent> [photo attached; text in photo: <on-device OCR>]`. The OCR comes from Apple Vision
   (`VNRecognizeTextRequest`), and its text is used only for this local decision. It is never sent. "sensitive" →
   `.keptOnDevice`, nothing sent, and the decision card shows the probability.
2. **A lexical floor for photos.** Receipts, statements, cards/card numbers (`**** 4421`), IDs, prescriptions, lab
   reports and similar stay local even when the model says "ok". A photo carries more than the words that come with it.
   The hint and the user toggle **"Photos stay on this iPhone"** (in the Glimpse sheet, `@AppStorage("photos_stay_on_device")`)
   both refuse with `.keptOnDevice`.
3. **Online check.** Offline → "Voice and camera understanding need the cloud; nothing was sent." The sensitivity card
   still shows, as it does for text turns in airplane mode.
4. **Downscale + re-encode on device.** ≤ 1024 px long side, JPEG q0.8, rotation baked into pixels. The original
   HEIC/JPEG is never read into the request. Byte counts are shown (`Prepared on device: <original> KB → <sent> KB JPEG`).
5. **EXIF/GPS strip.** `JPEGMetadataStripper` is a pure-Swift JPEG marker walker. It drops APP1 (Exif with GPS, XMP),
   APP2 (ICC/MPF), APP13 (IPTC) and COM, and keeps SOI/APP0/DQT/SOF/DHT/SOS/EOI byte-for-byte (a unit test checks the
   output is identical to the same JPEG built without metadata). It **fails closed**: if it can't parse the file, the
   photo is not sent.
6. **Masked text.** The question goes through the same `PrivacyScrubber`, with memory entity names, as text escalation.
   `[PERSON_1]` is restored only on the phone (tested: "Priya" never appears in either request body).
7. **Standard mode only.** `MetaAPI.requireStandardMode` throws on any `*-contributor` id, so user media is never used to
   train Meta models.
8. **Receipt.** Every request returns a `CloudPayloadSummary` (endpoint, model, total bytes, media bytes, masked text,
   removed segments). The Glimpse sheet shows it as **"What left the phone"**, and the chat turn opens the same privacy
   sheet as text escalations.
9. **Voice audio doesn't persist.** The WAV goes to a temp file and is deleted as soon as it's read, unless the user
   opts in (`keep_voice_recordings`). Contact/memory names are **not** sent as transcription keywords, because that would
   leak names the user never said.

```
VOICE   hold mic ─► 16 kHz mono WAV (temp) ─► [online? key? voice allowed?] ─► Muse Voice Transcribe ─► transcript
                                                       │ no: "nothing was sent"                         │ (temp file deleted)
                                                       ▼                                                ▼
                                                                         Assistant.handle(transcript)   ◄── same as typed text
                                                                         rememberOrNot → route → tool / clarify / answer_local
                                                                         / escalate (sensitivity → scrub → Spark text)

CAMERA  photo ─► downscale ≤1024px JPEG ─► on-device OCR ─► Reflex sensitivity("User: … [photo attached; text in photo: …]")
                                                               │ sensitive / receipt-ID-health floor / user toggle
                                                               ├──────────────► Kept on device · nothing sent
                                                               │ offline ─────► "nothing was sent"
                                                               ▼ ok
                                               strip APP1/APP2/APP13/COM (fail closed) ─► scrub question
                                                               ├─ Ask  ─► muse-spark-1.3  (chat/completions, image_url)
                                                               ├─ Find ─► sam-3.1         (responses, boxes + one_bit masks)
                                                               └─ Both ─► Spark answers + names CONCEPT ─► SAM 3.1 outlines it
                                               ─► CloudPayloadSummary per request ─► "What left the phone"
```

## Measured smoke results (2026-11-04, live, Habib's key)

Fixtures are generated, not downloaded (`eval/meta_api/fixtures/mk.py`): `remind.wav` is ffmpeg's built-in flite TTS
saying "Remind me to call Mom at seven tonight." (2.64 s, 16 kHz mono, 84 KB); `bars.jpg` is a 640×400 matplotlib bar
chart (Thu = 9 is tallest); `whiteboard.jpg` is an 800×500 whiteboard with five yellow sticky notes.

| Test | Result | Latency |
|---|---|---|
| Voice (python `smoke.py`) | `"remind me to me to call mom at seven tonight."` (TTS stutter transcribed faithfully) | 1.8 s |
| Voice (Swift, through `MultimodalGate.transcribe`) | `"remind me to call Mom at seven tonight."`; 84,783 bytes sent | 0.9–1.2 s |
| Spark vision, bar chart, "tallest bar?" | `"The tallest bar is Thu with 9 thousand steps."` (correct) | 3.6 s |
| Spark vision, whiteboard | All five notes, verbatim | 3.6 s |
| SAM 3.1, bars, prompt `bar` | 5 boxes, conf 0.91; tallest box x1=404 y1=52 x2=490 y2=360 (= Thu) | 1.4 s |
| SAM 3.1, whiteboard, prompt `yellow sticky note` | 5 boxes, conf 0.82–0.92 | 1.0 s |
| Swift live gate, "Both" on whiteboard | Spark lists the 5 notes and picks `yellow sticky note`; SAM 3.1 returns 5 segments; all 5 masks decode on device; 78 KB sent across 2 requests | 5.8 s |

Lessons from the live runs that are now in the code:
- **Spark spends output on reasoning.** At `max_tokens: 120` both vision calls came back with `content: null`
  (118/120 tokens were reasoning; `run1/`). The client now sends `reasoning_effort: "low"` with `max_tokens: 700` and
  treats null content as a typed `emptyAnswer` error.
- **SAM 3.1 needs a concrete attribute.** `sticky note` → 0 matches on the whiteboard, `yellow sticky note` → 5. Spark is
  told to name the concept starting with its color.
- **Mask decoder cross-check.** The Swift one_bit decoder matches Meta's `meta-sam-parser` 0.1.0 (MIT) bit for bit on all
  five live bar masks (pixel counts 20611/14945/8849/26750/11885 plus an index checksum, asserted in the tests).

Re-run: `source /tmp/gencode/sec/meta.env && python3 eval/meta_api/smoke.py [--probes]`; Swift live test:
`docker run --rm -e META_API_KEY -e PG_LIVE_META=1 -e PG_META_DIR=/meta -v "$PWD/core:/src" -v "$PWD/eval/meta_api:/meta" -w /src swift:6.1-noble swift test --filter testLiveMetaAPIThroughTheGate`.
It is skipped unless `PG_LIVE_META=1`. Saved responses keep `Authorization: Bearer <REDACTED>`; image and audio bytes are
replaced by `<N bytes …>`.

**Spend:** $0.0276 total across all live calls (python runs 1 + 2: $0.0166; Swift live gate ×2: $0.0110), itemised in
`eval/meta_api/spend.jsonl` (estimated from reported usage × list price). The cap was $3.

## Limitations (honest list)

- **Online-only.** Voice and camera need the network. There's no on-device ASR or vision model in this build. Offline, the
  mic and camera say so and send nothing.
- **The sensitivity decision was trained on text.** For photos it sees the user's words plus on-device OCR, not pixels. A
  photo of a document with no readable text and an innocent question could pass the model. The lexical floor and the
  "Photos stay on device" toggle are the backstops. This is a known gap, not a solved problem.
- **SAM 3.1 is shown, not acted on.** Segments are drawn (boxes plus masks) and counted. They don't yet feed tools (for
  example, "make a reminder per sticky note" still goes through Spark's text answer and the normal tool path).
- **One concept per SAM request** (an API rule). "Both" mode segments only the concept Spark names.
- **Settings has no voice/photo toggles yet** (SettingsView belongs to another work stream). The photo toggle lives in the
  Glimpse sheet. `voice_stays_on_device` and `keep_voice_recordings` are UserDefaults keys that default to off.
- **The voice file endpoint takes WAV only.** We record PCM WAV directly (~32 KB/s), not AAC. A 10 s request is ~320 KB.
  Realtime streaming (`wss://api.meta.ai/v1/asr/realtime`) would cut latency but isn't wired.
- **App code was not compiled on this box** (no Xcode). See the iOS caveats below.

## Demo beats

1. **Hold mic:** "Remind me to call Mom at 7". The transcript appears with a `Muse Voice Transcribe · 2.6 s · 83 KB
   sent · recording deleted` line, then the **same decision cards** as typed text (rememberOrNot → route → toolChoice →
   confirmBeforeAct; the unit test asserts this exact sequence for a transcript).
2. **Camera on a receipt:** "split this receipt". The sensitivity card shows its verdict, and the receipt/card floor
   (word "receipt", or on-device OCR such as `**** 4421`) keeps it local either way → **Kept on device · nothing sent**.
   No request is made (unit-tested).
3. **Camera on a whiteboard → Both:** Spark lists the notes and picks "yellow sticky note", SAM 3.1 draws five tinted masks
   with boxes and confidences, and **What left the phone** shows two lines (~38 KB each, EXIF/GPS removed, masked text).

### How to add it to the demo video (for Habib)
1. Record on the iPhone (online), right after the airplane-mode beat. Hold the mic and say "Remind me to call Mom at 7";
   let the decision strip and cards play. That's ~8 s.
2. Point the camera at a real receipt and type "split this receipt" → hold on the lock badge for 2 s. Then do a
   whiteboard with 3–5 sticky notes → **Both** → hold on the overlay and the "What left the phone" box. That's ~12 s.
3. Voice-over: "Voice and camera use three more Meta models (Muse Voice Transcribe, Muse Spark vision, SAM 3.1), and they
   go through the same on-device gate. Sensitive photos never leave."

## iOS compile caveats (unverified on this box)

PocketCore compiles and tests green on Linux (swift 6.1). The three app files use only system frameworks (SwiftUI,
AVFoundation, PhotosUI, UIKit, Vision, CoreGraphics) and target iOS 18. The calls most worth a first build on the Mac:
`AVAudioApplication.requestRecordPermission()` (iOS 17+), `.photosPicker(isPresented:selection:matching:)`,
`Canvas` + `ctx.draw(Image(uiImage:), in:)`, `VNRecognizeTextRequest` inside `withCheckedContinuation`, and the
`DragGesture(minimumDistance: 0)` hold-to-talk. `Vision`, `PhotosUI` and `AVFoundation` auto-link from `import`. No
`project.yml` dependency is needed (the file only lists `MessageUI` explicitly, for a weak-link reason that doesn't apply here).
