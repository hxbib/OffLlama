# Retained-history completion: threads G and H

**Assigned threads**

- **G** — `thread:delegated-task:command%3Amcp%3A1967ec5d-eea6-402e-9f2d-09489ad85fbb%3Adelegate-task%3Afa5aca6f-fc9b-4ecf-b18c-9b222242d94d`, 141 items, positions 0–140, terminal provider 429.
- **H** — `thread:delegated-task:command%3Amcp%3A1967ec5d-eea6-402e-9f2d-09489ad85fbb%3Adelegate-task%3A84ca6034-c35e-4d8e-9ce7-87e219f671e7`, 136 items, positions 0–135, completed.

**Comparison commits:** baseline `581fa3a9d44b5b2460e4f541a5a557f275dfdc06`; current `159d287` (the comparison point named by the parent). The working tree is later than `159d287`; findings marked “still open” were rechecked at `159d287` and, where relevant, in the working tree.

**Scope:** read-only. No source edits, commits, pushes, tests, training, model inference, or paid calls. Only this report was written, mode 600. No secret, key, signed URL, or real user private content is reproduced. The few quoted strings are synthetic fixtures or generic test data.

---

## 1. Verdict

**Item coverage: complete for G and H.** All 277 items are accounted for: 159 unique items read in full in this pass, 117 items already read in the prior pass (including 8 exact duplicates read in another thread), and 1 item (`H:8`) skipped only because it is byte-identical to `G:10`, which was read. There is no unread retained item left in either thread.

**Byte coverage: still incomplete.** 24 retained items in G/H carry `[Earlier output truncated]` in their stored payload. Those bytes were never in the thread and were not recovered. This is separate from tool paging: every retained item is below 50,000 characters (largest: `H:19`, 33,648 chars of tool text), and sampled `t3_thread_read` calls returned `textTruncated: false` and `nextTextOffset: null`. The truncations are harness markers embedded in the retained text, not `itemId`/`textOffset` cutoffs.

**Reasoning coverage: closed for these threads.** G has 55 reasoning items; H has 58. All 113 were read in full (110 in this pass; `H:32`, `H:83`, `H:100` were read in the prior pass). The prior report’s “227 reasoning items keyword-swept” gap no longer applies to G/H.

**New findings: 2 P2 and 4 P3, with the last two P3s being minor data/doc precision notes.** They do not change the existing app-release BLOCKED verdict, which rests on the iOS app never having been compiled. They do falsify the prior report’s claim that “no new material finding is hidden behind those residual gaps”: both P2s were present in unread reasoning and were dropped from H’s or G’s delivered artifact.

- **R1 (P2, privacy/data retention):** “Forget” deletes only the current fact; superseded history remains on disk and is no longer visible or deletable, contradicting the onboarding promise. H found this in reasoning, planned a recursive delete, and neither implemented nor reported it.
- **R2 (P2, privacy/claims):** the advertised photo lexical floor does not catch a receipt whose only sensitive text is `TOTAL 42.10` (or similar), because G’s planned money-amount pattern was never added. The docs say receipts stay local “even when the model says ok” and the demo voice-over says “Sensitive photos never leave.”
- **R3 (P3, data freshness):** the Reflex telemetry CSV share is cached after the first tap and is never regenerated, so later decisions are missing. H found and planned a fix; it was not implemented or reported.
- **R4 (P3, reliability):** a telemetry write failure still throws out of `Reflex.decide` and aborts the turn. H flagged it and planned a non-fatal test; neither landed.
- **R5 (P3, data precision):** the docs’ whiteboard SAM confidence range `0.82–0.92` is not reproduced by the saved whiteboard response (`0.812865–0.816092`); the `0.92` bound matches neither saved SAM artifact.
- **R6 (P3, stale doc):** `docs/META_MULTIMODAL.md:135` still says Settings has no voice/photo toggles; at `159d287` Settings has a working “Voice stays on this iPhone” toggle.

The already-tracked N1–N5 items were confirmed and are **not** counted as new. Section 5 records their status only.

---

## 2. Reading method and evidence

1. Enumerated both threads with `t3_thread_read`, `view: "activity"`, paging by `afterPosition`, and checked item type/title/length. All 277 positions were enumerated.
2. Read the 159 previously-unread unique bodies in 10 chunks of 55–67k characters. Every chunk was read from start to finish, including the continuation when the display cap split a chunk; the chunk boundaries are listed in §2.1. Temporary chunk files were removed after reading; only this report remains.
3. For byte fidelity, the chunk text was extracted from the same retained `payload_json` in the local T3 projection store (`orchestration_v2_projection_turn_items`) rather than re-requested through the 50k tool cap. I cross-checked the extraction against `t3_thread_read` on `G:16`, `G:17`, `G:18`, `H:19`, and `H:20`: same text, same embedded truncation markers. No summary, title, path check, or keyword sweep was used as a substitute for a body.
4. `H:8` was skipped only after its extracted content hash (`9f927617a5`, 10,937 chars) matched `G:10`, the same Reflex.swift read already covered by the prior pass’s exact-duplicate group. No other unread item was skipped.
5. Prior-read positions were taken from `history-output-app.md` §1.2–1.4 and spot-checked where they mattered. The 17 file-change records are 28-character “Wrote file successfully” entries; G has 8 and H has 1, all previously read.
6. No new command output, test, model call, or source read was used as “recovered history.” Baseline/current files are used only to test whether a historical finding is still open.

### 2.1 Chunk completion

| Chunk | Items | Positions | Completion |
|---|---:|---|---|
| `c01` | 33 | G:1, 4–7, 11–13, 15–20, 22, 27, 31–32, 34, 36–49 | full, 1,142 lines |
| `c02` | 14 | G:50, 53–54, 56, 58, 60–62, 64–66, 68–70 | full, 744 lines |
| `c03` | 10 | G:71–76, 78, 80, 82, 84 | full, 528 lines |
| `c04` | 20 | G:85, 87, 89, 91–92, 94–97, 99, 103, 105–109, 111, 113, 115, 117 | full, 642 lines |
| `c05` | 14 | G:121, 123, 125, 127–129, 133, 137; H:1, 4, 6–7, 9–10 | full, 827 lines |
| `c06` | 14 | H:12, 14–16, 18–19, 21, 23–25, 27–28, 30, 34 | full, 763 lines |
| `c07` | 6 | H:36–37, 40, 43, 45, 47 | full, 377 lines |
| `c08` | 15 | H:48–49, 51–55, 57, 59–61, 63, 65–67 | full, 456 lines |
| `c09` | 7 | H:69, 71, 73, 75–77, 79 | full, 408 lines |
| `c10` | 26 | H:81, 85, 87, 89, 91, 94, 96, 98, 101–102, 104, 107, 110, 112, 114, 116, 118, 120–122, 124–126, 128, 131, 133 | full, 453 lines |

**Totals:** 85 G items (`55 reasoning`, `23 command`, `7 dynamic tool`) and 74 unique H items (`55 reasoning`, `14 command`, `5 dynamic tool`), plus `H:8` duplicate. 567,771 characters of newly-read unique content.

**Per-item type map** (the activity position is the stable id; the full `itemId` is the thread’s `turn-item:` id). `R` = reasoning, `C` = command, `D` = dynamic tool. `c05` contains the G/H boundary.

```text
c01: G:1R 4R 5C 6R 7D 11C 12R 13C 15R 16D 17D 18D 19R 20D 22R 27R 31R 32C 34R
     36R 37C 38R 39C 40R 41C 42R 43C 44R 45C 46R 47C 48R 49C
c02: G:50R 53R 54C 56R 58R 60R 61C 62R 64R 65C 66R 68R 69D 70R
c03: G:71C 72R 73C 74R 75C 76R 78R 80R 82R 84R
c04: G:85C 87R 89R 91R 92C 94R 95D 96C 97R 99R 103R 105R 106C 107R 108C
     109R 111R 113R 115R 117R
c05: G:121R 123R 125R 127R 128C 129R 133R 137R
     H:1R 4R 6D 7D 9R 10C
c06: H:12R 14R 15D 16D 18R 19D 21R 23R 24C 25R 27R 28C 30R 34R
c07: H:36C 37R 40R 43R 45R 47R
c08: H:48C 49R 51R 52C 53R 54C 55R 57R 59C 60R 61C 63R 65R 66C 67R
c09: H:69R 71R 73R 75R 76C 77R 79R
c10: H:81R 85R 87R 89R 91R 94R 96R 98R 101C 102R 104R 107R 110R 112R 114R
     116R 118R 120R 121C 122R 124R 125C 126R 128R 131R 133R
```

### 2.2 Prior coverage reused

| Thread | Prior-read positions | Duplicates read elsewhere | New this pass | Total accounted |
|---|---:|---:|---:|---:|
| G | 44 + 8 file changes = 52 | 4 (`G:3`, `G:8`, `G:9`, `G:10`) | 85 | 141/141 |
| H | 53 + 1 file change + 3 reasoning = 57 | 4 (`H:3`, `H:11`, `H:17`, `H:20`) | 74 + `H:8` duplicate | 136/136 |

The prior report’s exact-duplicate groups were: `F:3/G:3/H:3`, `F:5/H:11`, `F:8/G:10/H:8`, `G:8/H:17`, `G:9/H:20`. No other exact duplicate was found among the unread items. `H:8` is the only skip in this pass.

---

## 3. Retained truncations (exact unresolved items)

These 24 items retain only a truncated body. **None is a paging failure.** `textTruncated` is false and `nextTextOffset` is null on the sampled items; the marker is inside `output`/`results`. The largest retained item is 33,648 characters, below the 50,000 cap.

| Positions | What is missing | What can be checked | What cannot be recovered |
|---|---|---|---|
| G:9, 16, 17, 61 | Start of a source read. `G:9` Assistant.swift; `G:16` ChatView lines 1–22; `G:17` AppModel lines 1–92; `G:61` `_mask_codec.py` from line 135. | `git show 581fa3a:path` gives a later baseline file; the `meta-sam-parser` 0.1.0 wheel and extracted `_mask_codec.py` are still at `/tmp/gencode/samparser`. | Exact historical bytes. `G:16/17` were read around 7:05, before G added the mic/camera edits and before H/B changed AppModel; `581fa3a` is not the same file. |
| H:11, 16, 19, 20 | Start of a source read. `H:11` Decision.swift; `H:16` Telemetry lines 1–48; `H:19` Memory lines 1–254; `H:20` Assistant top. | `git show 581fa3a:path`; current `159d287` for endpoint behavior. | Exact historical bytes. These files were edited later by H and others, so the baseline is not the read-time snapshot. |
| G:21, 23, 24, 25, 28, 29, 30, 33, 35, 55 | Web result snippets start mid-page (`[Earlier output truncated]` at the head of each `results[].snippet`). | The retained snippet text, the docs URLs, and the claims cited in the prior report. | Full fetched pages; only the retained snippets exist. |
| H:22, 24, 26, 33, 38, 95 | Command output starts mid-file. `H:24` is a concatenation of project.yml + AppModel + LlamaCppEngine; the others are diffs/concatenations. | Baseline/current files and `git diff` for the endpoints. | Exact concatenated output bytes. |

No `[Earlier output truncated]` bytes were recovered from upstream, and none are claimed as recovered. The prior report’s G/H truncation list is complete: exactly these 24 positions, no new truncation position was found.

---

## 4. New findings

### R1 — P2 privacy/data retention: “Forget” leaves superseded memories on disk

**Status: still open at `159d287`.** H identified this in reasoning, planned a fix, and then omitted it from both the code and the 20-row delivered review.

**Evidence**

- `H:34`: “forgetting an active fact that had replaced an older one leaves that older fact still marked as superseded and hidden.”
- `H:43`: “I'm noting that `forget` only removes the single row, so superseded history rows stay in the database even after the user deletes a memory, which conflicts with the ‘delete every memory’ promise in onboarding.”
- `H:73`: “I'm adding a recursive delete so that forgetting a fact also removes its superseded history, since leaving those rows behind would conflict with the promise that users can delete every memory.”
- `H:79`: “if a newer version is deleted, the older rows that pointed to it are left orphaned, and `corrections()` drops them.”
- `H:81`: “I think `forget(id:)` should also remove the supersede chain” and “those would otherwise stay on disk and become unreachable.”
- Code at `159d287`: `core/Sources/PocketCore/Memory.swift:259` is still a one-row `DELETE FROM facts WHERE id=?`. `active()` (`:247`) and the Memory tab (`app/PocketGlimmer/Views/MemoryView.swift:59`) only show active facts. `corrections()` (`:255–257`) drops an old row once its `superseded_by` target is gone, so the old value becomes invisible rather than deleted. `app/PocketGlimmer/Views/OnboardingView.swift:10` still says “You can see and delete every memory.”
- The delivered `docs/CODE_REVIEW_NOV4.md` has 20 rows and no memory-deletion row; `history-output-app.md`’s H open-items list also omits it.

**Why it matters**

A corrected health, money, or credential fact can remain in `pocket.sqlite` indefinitely after the user taps Forget. It is local-only (no network call), but it is exactly the data the user believed they deleted, and it may be included in a device backup. This is a retention promise mismatch, not a cloud leak.

**Smallest repair**

Make `forget(id:)` delete the row and its superseded chain in one transaction (iteratively collect `WHERE superseded_by = ?`, or a recursive CTE), then update `corrections()`/tests. Add a test: create fact A, supersede it with B, call `forget(B)`, assert neither A nor B remains. Alternatively, change the onboarding copy and expose history, but that is a larger product change.

---

### R2 — P2 privacy/claims: the receipt floor does not cover a total-only receipt

**Status: still open at `159d287`.** G identified the exact gap in reasoning and planned a money-amount pattern; it was never added. This is a different path from N2’s long-shared-text first-400 screening: R2 is the photo OCR + lexical-floor path, and the missing pattern is independent of the 400-character issue.

**Evidence**

- `G:94`: “The current regex doesn't catch ‘TOTAL,’ so I'm considering adding a money-amount pattern to cover receipts.”
- `core/Sources/PocketCore/MetaMultimodal.swift:541–546` at `159d287`: the lexical floor catches `receipts?`, `statements?`, `credit`, `debit`, card brands, `card number`, `bank`, `tax`, `passport`, `driver's license`, `id card`, `ssn`, prescriptions, lab/medical, `password`, `pin`, and the card-number regexes. It does **not** catch `TOTAL`, `SUBTOTAL`, `AMOUNT DUE`, `BALANCE`, `$42.10`, or a bare currency amount.
- `core/Tests/PocketCoreTests/MetaMultimodalTests.swift:244–252`: the “receipts never leave” test uses the literal word `receipt`; the second case is `VISA **** 4421 TOTAL $42.10`, where the **card digits** trigger the card regex, not `TOTAL`. There is no test with `TOTAL 42.10` alone.
- `docs/META_MULTIMODAL.md:49–51` says “Receipts, statements, cards/card numbers … stay local even when the model says ‘ok’.” The demo voice-over at `:158` says “Sensitive photos never leave.” The limitations at `:129` only admit a document “with no readable text”; this case has readable text that the floor ignores.
- Secondary limit: `MetaMultimodal.swift:608` feeds only `String(t.prefix(240))` of OCR text into the Reflex sensitivity context. The lexical regex scans the full string, but the model verdict cannot see text after 240 characters.

**Why it matters**

A cash receipt with OCR `TOTAL 42.10`, a benign intent such as “what’s this?”, and no card digits is not caught by the lexical floor. It is sent to Spark if the 1B sensitivity decision says `ok` (the test’s scripted “model says ok” case) and the user has not enabled the photo toggle. That contradicts the advertised floor and the demo claim. The photo toggle remains a real backstop, and the model may often say sensitive; the claim is still stronger than the code.

**Smallest repair**

Add a money-amount pattern to `PhotoSensitivityHint` for amount-bearing words not already covered (for example `\b(total|subtotal|amount due|balance)\b` plus a currency/amount form), and add a test with `photoText: "TOTAL 42.10"`, intent `"what's this?"`, and a scripted `ok` verdict asserting `keptOnDevice`. If the product does not want that breadth, change the docs and demo voice-over to “kept on device when detected” and disclose the 240-character prefix.

---

### R3 — P3 data freshness: the Reflex CSV share is stale after the first tap

**Status: still open at `159d287`.** H identified it and planned to regenerate; the delivered review only records the context-column opt-out.

**Evidence**

- `H:43`: “`exportURL` gets set on the first export and never refreshed, so the share sheet could keep handing over a stale CSV.”
- `H:71`: “the ShareLink holds the URL from the first tap, so it keeps sharing an old CSV because the file only gets rewritten on a fresh export.”
- `H:124`: “the export already omits the context field” — the privacy fix, not the freshness fix.
- `app/PocketGlimmer/Views/ReflexView.swift:37–38` at `159d287`: once `exportURL` is non-nil, the view shows `ShareLink(item: u)` and never calls `model.exportCSV()` again. `.onAppear` at `:41` only calls `model.refresh()`.
- `docs/CODE_REVIEW_NOV4.md` row 6 covers only `includeContext: false`; no stale-share row.

**Why it matters**

After the first export, later decisions are absent from every subsequent share. The CSV still omits context (privacy is preserved), but the artifact is silently stale.

**Smallest repair**

Reset `exportURL = nil` in `.onAppear`, or replace the cached `ShareLink` with a button that regenerates the file and presents the share sheet on each tap.

---

### R4 — P3 reliability: a telemetry write failure aborts the turn

**Status: still open at `159d287`.** H flagged it in reasoning and planned a non-fatal test; neither the code change nor the test is present.

**Evidence**

- `H:43`: “a telemetry write failure throws and aborts the whole decision and turn, which seems wrong for an assistant that shouldn't fail a user's reply over logging.”
- `core/Sources/PocketCore/Reflex.swift:57` at `159d287`: `let id = try telemetry?.log(...)`. `Reflex.decide` does not catch it; `Assistant.handle` propagates it to `AppModel.send`’s catch, which renders “Error: …”.
- `docs/CODE_REVIEW_NOV4.md` row 14 documents that telemetry logs the argmax; it does not address failure handling. No `ReviewTests` test simulates a failing telemetry store.

**Why it matters**

A full disk, a closed/corrupt SQLite handle, or a write error turns every decision into a user-visible failure even though logging is nonessential. Rare, but a poor failure mode for the demo.

**Smallest repair**

Use `try? telemetry?.log(...)` with a `print`/`os_log` warning, or catch and continue with `telemetryID = nil`. Add a test with a closed or read-only database asserting the decision still returns.

---

### R5 — P3 data precision: whiteboard SAM confidence range

**Status: still open at `159d287`.**

`docs/META_MULTIMODAL.md:105` reports the whiteboard SAM run as “5 boxes, conf 0.82–0.92.” The saved `eval/meta_api/sam_segment.json` is the 800×500 whiteboard response with 5 boxes and 5 masks, confidences **0.812865–0.816092**. The saved bars response (`sam_segment_bars.json`) is **0.910112–0.913979**. The `0.92` upper bound is in neither saved artifact. If the Swift live gate produced it, that response was not saved; `eval/meta_api/swift_live_gate.txt` records only the 5-segment count. This is a reporting precision issue, not a behavior bug; the box coordinates and segment count are correct.

**Smallest repair:** report `0.81–0.82` for the saved whiteboard response and `0.91` for bars, or save the Swift response and cite it.

### R6 — P3 stale doc: Settings voice toggle

`docs/META_MULTIMODAL.md:135` still says “Settings has no voice/photo toggles yet.” At `159d287`, `app/PocketGlimmer/Views/SettingsView.swift:8,31` has `@AppStorage("voice_stays_on_device")` and a working “Voice stays on this iPhone” toggle. The photo toggle is still only in the Glimpse sheet, so the sentence is half true. This understates a shipped privacy control; update the limitation.

---

## 5. Confirmed existing findings (not counted as new)

These were rechecked only to decide whether they remain open; the root already has them.

- **N1, retrieved-memory redaction:** still present at `159d287`. `Assistant.swift` builds `mem` from retrieval and sends `(prof + mem + utterance)` after `cloudScrubber()`, which only adds names; `profileOnePager(redactSensitive: true)` applies to the profile, not `mem`. H’s reasoning `H:43`, `H:71`, `H:75` repeats the gap; H’s delivered review has no row for it. Root is fixing; not re-reported.
- **N2, first-400 document screening:** still present at `159d287`. `ActionPlanner.swift` uses `String(text.prefix(400))` for sensitivity and sends up to 24,000 characters after scrubbing. Root is fixing; not re-reported.
- **N3, backup wording:** the app copy at `159d287` now says “The app does not upload this file. Your device backup settings may include it.” The code still does not set `isExcludedFromBackup`; the root’s correction is the copy, not a code exclusion. This is the known N3 status, not a new finding.
- **N4, pre-fix timing comment:** the old “73.6 s vs 87.0 s on cal180” timing comment is gone from `LlamaCppEngine.swift` at `159d287`. The current comment explains the double-BOS parity instead. Known correction; not re-reported.
- **N5, `store:false` vs ZDR:** current `docs/META_MULTIMODAL.md` says the SAM request sets `store:false`, that this is schema-verified rather than a new live result, and that Standard mode is a training-use setting, not a zero-retention promise. Known; not re-reported.
- **Known app.md items:** first-session contact names (P1 3), SAM concept scrub (P1 4), text-model contributor bypass (P1 5), SAM `store:false` (P1 6), Apple TV claim (P1 7), voice-before-gate (P2 8), Fireworks row (P2 9), long-text memory names (P2 10), Assistant `cloud`/`scrubber` race (P2 11), stale judge docs (P2 12). No new duplicate is added here.

---

## 6. Authorization, spend, and scope

- **Spend:** G’s `eval/meta_api/spend.jsonl` has 15 rows totaling **$0.027599** (saved artifact at `581fa3a`). This is under the stated $3 run cap and far under the $150 credit authorization. The two Swift live gate runs include one failed SAM run (`segments: 0`, 5,261 ms) and one successful run (`segments: 5`, 5,821 ms); both are logged. No other thread in scope made paid calls. This pass made none.
- **Secrets:** G checked `/tmp/gencode/sec/env.sh` and `/tmp/gencode/sec/meta.env` without printing values; `G:43` echoes only `key len 48`. `G:110`’s grep found no Meta key in repo files. No key, signed URL, or user private content is reproduced here.
- **File ownership:** G used only its allowed new files plus the two explicitly allowed small additive edits (`ChatView.swift` mic/camera buttons at `G:126`; `project.yml` microphone/camera/photo usage strings at `G:128`) and the allowed `CloudBrain.swift` preset. It did not touch `Decision.swift`, `Assistant.swift`, or Memory/Telemetry.
- **H ownership:** H’s brief allowed “app files OTHER than ChatView.swift/project.yml/SystemActions.swift” and explicitly listed `AppModel.swift`, `Views/{Components,MemoryView,OnboardingView,ReflexView,SettingsView}.swift`, `Engine/LlamaCppEngine.swift`, and `Support/*`. H’s edits to `PocketGlimmerApp.swift`, `Components.swift`, `MemoryView.swift`, `AppModel.swift`, `LlamaCppEngine.swift`, and the core files are within that grant. H did not edit ChatView, project.yml, SystemActions, or Assistant. H’s own `H:104` uncertainty about `PocketGlimmerApp.swift` is resolved by the brief’s “app files OTHER than” wording and its explicit file list.
- **No out-of-scope edit was found** in either thread. The one ambiguity is H’s edit to `Theme.confidenceColor` in `PocketGlimmerApp.swift`; the file is covered by the grant above.

---

## 7. Artifacts and integration

- **G:** every code/artifact G produced is present at `581fa3a`: `core/Sources/PocketCore/MetaMultimodal.swift`, `core/Tests/PocketCoreTests/MetaMultimodalTests.swift` (14 test functions: 13 offline + 1 live), `app/PocketGlimmer/Capture/VoiceCapture.swift`, `CameraGlimpse.swift`, `Views/GlimpseView.swift`, `docs/META_MULTIMODAL.md`, and `eval/meta_api/` (fixtures, saved responses, `spend.jsonl`, probes). The only missing G artifact is its final prose summary, lost to the provider 429 at `G:140`; no code or test work was lost.
- **H:** `docs/CODE_REVIEW_NOV4.md`, `core/Tests/PocketCoreTests/ReviewTests.swift` (10 tests), the BOS/top-40 engine changes, the boot/calibration/contacts AppModel changes, the Scrubber/Telemetry/Memory changes, and the UI tau/copy changes are all in the baseline tree. H’s final test line at `H:130/H:134` is `Executed 94 tests, with 1 test skipped and 0 failures`, matching the prior baseline reproduction.
- **Not integrated:** R1–R4 are the H/G reasoning commitments that did not become code or review rows. R6 is the docs line that did not get updated after another agent added the Settings voice toggle.

---

## 8. Corrections to the prior report

1. **“236/576 fully read” was honest for that pass but is now superseded for G/H.** G and H have 277/277 items accounted for: 159 new unique reads, 117 prior reads, 1 exact duplicate. The prior report’s G/H fully-read counts (44 and 53) excluded many reasoning and source-read items; those are now read.
2. **The prior report’s “no new material finding is hidden behind those residual gaps” is too strong.** R1 and R2 came directly from unread reasoning (`H:34/43/73/79/81`, `G:94`) and are absent from the delivered review and the prior report. The gap was not in runtime output; it was in unread reasoning and a lost code requirement.
3. **H’s review still has 20 rows and still lacks N1 and R1.** The prior report correctly found N1 missing. R1 is a second omission: H’s reasoning says the deletion promise is false, but the delivered review has no memory-deletion row.
4. **The G/H truncation list is accurate.** Exactly 24 positions carry `[Earlier output truncated]`; no new truncation position was found. The prior report did not distinguish paging from payload markers as sharply as it could; this report does.
5. **No correction is needed** to the previously verified G/H items: the 15-row spend total, the 868 ms/1,247 ms voice runs, the five-mask live SAM run, the `0.10217188684` cal180 bound, the 64/180 handled count, the 135-row zero-error requirement, the 94-test/1-skip baseline, the BOS 18/36 figures, or the top-40 parity fix. These reproduce from the retained text and saved artifacts.

---

## 9. Bottom line

- **Coverage:** 277/277 G/H items accounted; 159 unique items read in full this pass; 113/113 G/H reasoning items read across the two passes.
- **Residual:** 24 retained payloads are truncated by the harness; exact bytes are unavailable and none were recovered. No item was skipped for tool size; `H:8` is the only duplicate skip.
- **Findings:** R1 and R2 are new P2s that were in the unread record and not in the delivered artifacts. R3–R6 are P3s. None changes the BLOCKED release verdict, which remains driven by the never-compiled iOS app and the already-known privacy blockers.
- **Do not** treat the compressed final summaries as complete: H’s final table omits R1, and G’s docs overstate the receipt floor that G itself knew was incomplete.

Report: `/tmp/pocket-glimmer-takeover/history-retained-gh.md`
