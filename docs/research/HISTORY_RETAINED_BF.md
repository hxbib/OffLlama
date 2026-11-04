# Retained-history completion: B and F

**Scope:** B and F only. No main-thread, G/H, or other-history reads; no source edits, commits, pushes, model inference, training, paid calls, or tests. Repository reads were against `/home/habib/pocket-glimmer`; historical claims were checked against `581fa3a9d44b5b2460e4f541a5a557f275dfdc06` (baseline) and `159d287`/current. No secret, key, signed URL, or real user private content is reproduced below.

**Read mechanics:** T3 `view: "activity"` with `afterPosition`, `limit`, and `maxCharsPerItem: 50000`; items over 10,000 characters were continued with the returned `itemId` + `textOffset`; every continuation ended at `nextTextOffset: null`. Every read response was actually examined; no title/head, path check, current-file substitution, or keyword sweep is counted as a read. Prior fully-read positions were reused only where the prior report listed them; all remaining B/F positions were read this pass. Exact byte-identical duplicates already read in the prior pass were not reread (F:3, F:5, F:8; the prior report gives exact-equality evidence).

**Coverage verdict: COMPLETE for retained B/F content; RESIDUAL bytes remain.** The union of prior fully-read positions and this pass covers **all 177 B positions and all 122 F positions**, including **all 117 reasoning items** (B 61, F 56). This pass read **177 positions**: **169 previously unread** (B 80, F 89) plus **8 anchor rereads** (B 6, F 2). There is no unresolved tool-pagination item. Twenty-one B/F items retain the harness marker `[Earlier output truncated]`; their pre-marker bytes are not recoverable. One additional B reasoning item (B:48) ends mid-sentence without a marker and has no continuation. Exact historical command-output bytes for those items were not recovered.

---

## 1. Coverage ledger

### 1.1 Totals by thread

| Thread | Link | Items | Prior fully read | Previously unread | Read this pass | Union | Unresolved tool pages |
|---|---|---:|---:|---:|---:|---:|---:|
| B | `<t3-thread://v2/1fc19a6b-4359-418d-a801-4f7fb5e9b320/thread:delegated-task:command%3Amcp%3A1967ec5d-eea6-402e-9f2d-09489ad85fbb%3Adelegate-task%3Aa93c9d04-c8cf-407c-b740-5450cea42df4>` | 177 | 97 distinct positions (94 in the prior headline list + 35, 36, 60) | 80 | 86 (80 unread + 6 anchor rereads) | 177 | 0 |
| F | `<t3-thread://v2/1fc19a6b-4359-418d-a801-4f7fb5e9b320/thread:delegated-task:command%3Amcp%3A1967ec5d-eea6-402e-9f2d-09489ad85fbb%3Adelegate-task%3A36cf8d6c-fdfd-4ff2-9a04-fa95a0c3e3ae>` | 122 | 33 distinct positions (25 in the prior headline list + duplicate/file-change positions 3, 5, 8, 48, 60, 66, 82, 88) | 89 | 91 (89 unread + 2 anchor rereads) | 122 | 0 |

Position-level coverage is the authoritative count; the prior report's headline “94 B / 25 F” is a rounded per-thread count that omits separately listed file-change/duplicate positions.

B type mix: 61 reasoning, 86 command executions, 3 dynamic tools, 18 assistant messages, 5 user messages (including position 0), 3 file changes, 1 checkpoint. F type mix: 56 reasoning, 49 command executions, 8 dynamic tools, 5 file changes, 2 assistant messages, 1 user message (position 0), 1 checkpoint.

All 61 B reasoning items and all 56 F reasoning items were read in this pass. All 5 B user messages (0, 30, 49, 106, 127) and the single F user message (0) were read. All B/F **file changes** were prior-read (B 35, 36, 60; F 48, 60, 66, 82, 88) and are covered by the union. All B/F **checkpoints** were prior-read (B 176; F 121). No B/F error item exists.

### 1.2 Positions covered

Prior full-read positions reused (see the prior report's 1.2, 1.4, 1.6):

```text
B prior 97: 0, 3-4, 6-8, 10-11, 16-18, 20, 22, 24, 26, 30, 34-36, 40, 42, 47,
            49, 51, 54, 57, 59-60, 64, 66-68, 70, 72-74, 76, 78-79, 81, 83,
            85-86, 88, 90, 92, 94-95, 97, 99, 101, 103, 105-106, 108-110,
            113-119, 124-125, 127, 129, 131, 133, 135, 137-138, 140-141,
            143-144, 146, 148, 150-152, 154, 156, 158-160, 162, 164-166,
            168-169, 171, 173, 175-176

F prior 33: 0, 2-3, 5, 8, 24, 34, 38, 48, 54, 56, 60, 66, 68, 70, 72, 74,
            81-82, 88, 92, 94, 96, 100, 102, 106, 108, 112, 114, 116, 118,
            120-121
```

Read in this pass:

```text
B this pass 86: 0-2, 5, 9, 12-15, 19, 21, 23, 25, 27-33, 37-39, 41, 43-46,
                48-50, 52-53, 55-56, 58, 61-63, 65, 69, 71, 75, 77, 80, 82,
                84, 87, 89, 91, 93, 96, 98, 100, 102, 104, 106-107, 111-112,
                120-123, 126-128, 130, 132, 134, 136, 139, 142, 145, 147,
                149, 153, 155, 157, 161, 163, 167, 170, 172, 174-175

F this pass 91: 0-1, 4, 6-7, 9-23, 25-33, 35-37, 39-47, 49-53, 55, 57-59,
                61-65, 67, 69, 71, 73, 75-80, 83-87, 89-91, 93, 95, 97-99,
                101, 103-105, 107, 109-111, 113, 115, 117, 119-120
```

The 8 anchor rereads are B:0, 30, 49, 106, 127, 175 and F:0, 120. They were already in the prior fully-read set; they were reread because they contain the briefs/coordination notes/final claims used to judge findings. They do not change the “169 previously unread” count.

**Per-position type map.** Legend: `u` user, `r` reasoning, `c` command execution, `d` dynamic tool, `a` assistant, `f` file change. B:176 and F:121 are checkpoints (shown as `c` below). Position 0 is a user message in both threads.

```text
B: 0u 1r 2d 3c 4c 5r 6c 7c 8c 9c 10c 11c 12c 13r 14c 15c 16a 17c 18c 19r 20c
   21c 22d 23r 24c 25r 26c 27r 28c 29r 30u 31r 32c 33r 34a 35f 36f 37r 38c
   39r 40c 41r 42a 43c 44r 45c 46r 47c 48r 49u 50r 51a 52c 53r 54a 55c 56r
   57c 58r 59a 60f 61r 62c 63r 64c 65r 66a 67c 68c 69r 70c 71r 72a 73c 74c
   75r 76c 77r 78a 79c 80r 81c 82r 83c 84r 85a 86c 87r 88c 89r 90c 91r 92c
   93r 94a 95c 96r 97c 98r 99c 100r 101c 102r 103c 104r 105c 106u 107r 108a
   109c 110c 111r 112c 113a 114c 115c 116a 117c 118a 119c 120r 121c 122c 123r
   124c 125c 126r 127u 128r 129c 130r 131c 132r 133c 134r 135c 136r 137c 138c
   139c 140c 141c 142r 143c 144c 145r 146c 147r 148c 149r 150c 151c 152c 153r
   154c 155r 156c 157r 158a 159c 160c 161r 162c 163r 164c 165c 166c 167r 168a
   169c 170r 171c 172r 173c 174d 175a 176c

F: 0u 1r 2c 3d 4r 5d 6d 7r 8d 9c 10r 11c 12d 13r 14c 15r 16c 17d 18d 19r 20c
   21r 22c 23r 24c 25r 26c 27r 28c 29r 30c 31r 32c 33r 34c 35r 36c 37r 38c
   39r 40d 41r 42c 43r 44c 45r 46c 47r 48f 49r 50c 51r 52c 53r 54c 55r 56c
   57r 58c 59r 60f 61r 62c 63r 64c 65r 66f 67r 68c 69r 70c 71r 72c 73r 74c
   75r 76c 77r 78c 79r 80c 81a 82f 83r 84c 85r 86c 87r 88f 89r 90c 91r 92c
   93r 94c 95r 96c 97r 98c 99r 100c 101r 102c 103r 104c 105r 106c 107r 108c
   109r 110c 111r 112c 113r 114c 115r 116c 117r 118c 119r 120a 121c
```

### 1.3 Multi-chunk completion

These are the only items that required `itemId`/`textOffset` continuation beyond the first returned chunk. Every final chunk returned `nextTextOffset: null`.

| Position | Type | Chunks (characters) | Continuation itemId |
|---|---|---|---|
| B:33 | reasoning | 2 (12,000 + 3,637) | `turn-item:provider:acpRegistry:native-item:provider-instance%3AacpRegistry_gencode%3Ases_e59ceac66ffeoEJutMrMIFmyE0%3Aturn%3A2%3Areasoning%3Amessage%3Aprt_1a6340804001B1s44KC53LC5kE` |
| B:50 | reasoning | 2 (10,000 + 4,003) | `turn-item:provider:acpRegistry:native-item:provider-instance%3AacpRegistry_gencode%3Ases_e59ceac66ffeoEJutMrMIFmyE0%3Aturn%3A3%3Areasoning%3Amessage%3Aprt_1a63c27f2001lWpORAcRSZlb1k` |
| B:53 | reasoning | 2 (10,000 + 381) | `turn-item:provider:acpRegistry:native-item:provider-instance%3AacpRegistry_gencode%3Ases_e59ceac66ffeoEJutMrMIFmyE0%3Aturn%3A3%3Areasoning%3Amessage%3Aprt_1a63e789d0011zp0zOU2ShWFQW` |
| F:6 | dynamic_tool | 3 (10,000 + 10,000 + 4,551) | `turn-item:provider:acpRegistry:native-item:provider-instance%3AacpRegistry_gencode%3Ases_e59aa340affeyiy7ZcQ1era6B4%3Atool%3Atoolu_01RqVdrj39fYLdpcRs6jCvaT` |
| F:12 | dynamic_tool | 3 (10,000 + 10,000 + 2,304) | `turn-item:provider:acpRegistry:native-item:provider-instance%3AacpRegistry_gencode%3Ases_e59aa340affeyiy7ZcQ1era6B4%3Atool%3Atoolu_01Ca7ggcEykemtbZbKUw9HE3` |
| F:17 | dynamic_tool | 3 (10,000 + 10,000 + 786) | `turn-item:provider:acpRegistry:native-item:provider-instance%3AacpRegistry_gencode%3Ases_e59aa340affeyiy7ZcQ1era6B4%3Atool%3Atoolu_01DeQRRzxsXPstS4TUychKvD` |
| F:25 | reasoning | 2 (10,000 + 8,286) | `turn-item:provider:acpRegistry:native-item:provider-instance%3AacpRegistry_gencode%3Ases_e59aa340affeyiy7ZcQ1era6B4%3Aturn%3A1%3Areasoning%3Amessage%3Aprt_1a6588bcb001xqpFirxgGGZICH` |
| F:27 | reasoning | 3 (10,000 + 10,000 + 622) | `turn-item:provider:acpRegistry:native-item:provider-instance%3AacpRegistry_gencode%3Ases_e59aa340affeyiy7ZcQ1era6B4%3Aturn%3A1%3Areasoning%3Amessage%3Aprt_1a65b4f32001C6EftrWRfO8SHJ` |
| F:33 | reasoning | 3 (10,000 + 10,000 + 6,414) | `turn-item:provider:acpRegistry:native-item:provider-instance%3AacpRegistry_gencode%3Ases_e59aa340affeyiy7ZcQ1era6B4%3Aturn%3A1%3Areasoning%3Amessage%3Aprt_1a65e9ef4001t3RTPAw3dAjW5k` |
| F:35 | reasoning | 3 (10,000 + 10,000 + 1,202) | `turn-item:provider:acpRegistry:native-item:provider-instance%3AacpRegistry_gencode%3Ases_e59aa340affeyiy7ZcQ1era6B4%3Aturn%3A1%3Areasoning%3Amessage%3Aprt_1a6631fa30012bD5TUYiLXCn8Z` |
| F:37 | reasoning | 3 (10,000 + 10,000 + 2,652) | `turn-item:provider:acpRegistry:native-item:provider-instance%3AacpRegistry_gencode%3Ases_e59aa340affeyiy7ZcQ1era6B4%3Aturn%3A1%3Areasoning%3Amessage%3Aprt_1a66679cf001UbPnkHsd2XzunS` |
| F:39 | reasoning | 3 (10,000 + 10,000 + 3,124) | `turn-item:provider:acpRegistry:native-item:provider-instance%3AacpRegistry_gencode%3Ases_e59aa340affeyiy7ZcQ1era6B4%3Aturn%3A1%3Areasoning%3Amessage%3Aprt_1a66a1de3001QCO5Mty0FmOEdc` |
| F:41 | reasoning | 2 (10,000 + 7,899) | `turn-item:provider:acpRegistry:native-item:provider-instance%3AacpRegistry_gencode%3Ases_e59aa340affeyiy7ZcQ1era6B4%3Aturn%3A1%3Areasoning%3Amessage%3Aprt_1a66dcb01001vWTOhBLdx4VeXf` |
| F:43 | reasoning | 2 (10,000 + 5,791) | `turn-item:provider:acpRegistry:native-item:provider-instance%3AacpRegistry_gencode%3Ases_e59aa340affeyiy7ZcQ1era6B4%3Aturn%3A1%3Areasoning%3Amessage%3Aprt_1a670751b001R82g4pu4T5yEd9` |
| F:45 | reasoning | 3 (10,000 + 10,000 + 613) | `turn-item:provider:acpRegistry:native-item:provider-instance%3AacpRegistry_gencode%3Ases_e59aa340affeyiy7ZcQ1era6B4%3Aturn%3A1%3Areasoning%3Amessage%3Aprt_1a672c682001Zj8hJxavVPJtNY` |
| F:47 | reasoning | 2 (10,000 + 4,522) | `turn-item:provider:acpRegistry:native-item:provider-instance%3AacpRegistry_gencode%3Ases_e59aa340affeyiy7ZcQ1era6B4%3Aturn%3A1%3Areasoning%3Amessage%3Aprt_1a675a4fc001TOmKOa73F1rSwY` |
| F:49 | reasoning | 2 (10,000 + 3,527) | `turn-item:provider:acpRegistry:native-item:provider-instance%3AacpRegistry_gencode%3Ases_e59aa340affeyiy7ZcQ1era6B4%3Aturn%3A1%3Areasoning%3Amessage%3Aprt_1a678d734001k78Pv3hGRZUMlY` |
| F:51 | reasoning | 2 (10,000 + 6,391) | `turn-item:provider:acpRegistry:native-item:provider-instance%3AacpRegistry_gencode%3Ases_e59aa340affeyiy7ZcQ1era6B4%3Aturn%3A1%3Areasoning%3Amessage%3Aprt_1a67b2347001FHPW7NyIpffNrB` |

All other items read this pass returned their entire retained text in one call with `nextTextOffset: null`. That includes one-call items of 8,000–14,658 characters (for example B:43, B:48, B:55; F:11, F:14, F:22, F:30, F:53, F:59, F:61, F:107, F:109). B:67 was a prior one-call read of 14,658 characters, not a new read this pass. The API's per-item `textTruncated` flag is not evidence of completeness: B:48 is discussed below. For single-chunk items the exact `itemId` is in the T3 read response and is omitted here only to keep the ledger readable; position + type is unique within its thread and is the ledger key. The 18 multi-chunk continuation IDs are listed above.

### 1.4 Duplicates and prior evidence

No new exact-byte duplicate group was found inside B/F. The prior report's exact-equality groups that touch F were accepted without rereading:

- F:3, G:3, H:3 (generic `Tool` schema, exact 2,022 chars).
- F:5, H:11 (`Decision.swift`, exact 25,945 chars).
- F:8, G:10, H:8 (`Reflex.swift`, exact 11,100 chars).

Those are prior-reported, byte-equality-verified duplicates, not title/path matches. No other exact duplicates were found in this pass.

### 1.5 Residual unavailable payloads

These 21 B/F items retain the harness marker. Their retained text was read in full up to the marker; the omitted bytes are not recoverable from the thread.

```text
B (13): 7, 9, 10, 11, 12, 14, 15, 17, 18, 20, 22, 160, 162
F  (8): 5, 6, 11, 12, 17, 22, 24, 30
```

Recovery evidence and limits:

- **Tracked-file snapshots:** B:7 (`docs/DEMO_SCRIPT.md`), B:9-12/14-15/17-18/20 (core/app sources and tests), B:160/162 (git diffs), F:5 (`Decision.swift`), F:6 (`Assistant.swift`), F:11 (Memory/Calibration), F:12 (`AssistantTests.swift`), F:17 (`SystemActions.swift`), F:22 (`AppModel.swift`), F:24/30 (`AppModel`/demo-script commands). The corresponding files at `581fa3a` can verify a source claim. They **do not** recover the historical command-output bytes, which may include earlier versions, concatenation boundaries, or shell output.
- **B:22 external article:** the prior pass reported that the retained `display.text` duplicate contained the article and was read; the command item itself is truncated. I did not treat the current article path as a substitute for the historical output.
- **F:5/F:6/F:12/F:17/F:22/F:24/F:30:** the retained dynamic-tool/file text was read through the marker; the exact pre-marker content is unavailable. F:5/F:8/F:3 also remain prior-read exact duplicates, not new reads.
- **No tool-limit gap:** every `itemId`/`textOffset` continuation reached `null`; no item was left at a page boundary.

**Additional non-marker residual:** B:48 (reasoning, 9,796 retained chars, `textTruncated: false`, `nextTextOffset: null`, itemId `turn-item:provider:acpRegistry:native-item:provider-instance%3AacpRegistry_gencode%3Ases_e59ceac66ffeoEJutMrMIFmyE0%3Aturn%3A2%3Areasoning%3Amessage%3Aprt_1a63ab718001ji1DFOje7iKsW3`) ends with “I'm rendering the life” mid-sentence. There is no continuation item and no `[Earlier output truncated]` marker. The missing bytes are unavailable; the next item is the B:49 user message. I did not infer the missing plan from the later B:50 item. B:157 ends with a complete sentence and is not counted as a residual.

### 1.6 Claims verified while reading (not substitutes for reads)

- B's final test claims (55 tests at its handoff) are historical; current tests are a later integration state.
- F's final claims (84 tests, 1 skipped, 35 skills) were checked against the current tree only to determine whether later integration changed the artifact. The current registry has 36 skills; the extra Apple TV skill is a later integration, not an F thread read.
- The prior report's “45 truncated items” across four threads is consistent with the 21 B/F markers above.

---

## 2. New findings

These are not N1–N5. N1/N2 are still present and are being handled by the root; N3/N4/N5 were not re-opened as new. Each finding below is present in both `581fa3a` and `159d287` unless stated, so it is not a transient takeover artifact.

### BF-1 — P1/P2: `email_compose` / `send_email` is not reachable on the ordinary email path

**Evidence**

- `core/Sources/PocketCore/Decision.swift:60-69`: the trained `toolChoice` has six tools; there is no `send_email`. The message tool is `send_message`.
- `core/Sources/PocketCore/ActionPlanner.swift:26-33`: the `send_message` override list contains Instagram/X/WhatsApp/FaceTime/auto-reply words, but **not** `email`, `e-mail`, or `mail`.
- `ActionPlanner.swift:45-56`: `explicitRequest` contains `my emails`, `recent emails`, `last emails`, `these emails` (the read-only digest), but no compose word. `isExplicitMessageRequest` at 58-61 only recognizes `text`/`message`/`send text|message`.
- `core/Sources/PocketCore/Skills.swift:394-397`: the `email_compose` skill is a native `send_email` skill with examples “email Dana the slides are ready” and “send an email to my professor”.
- `ActionPlanner.swift:63-67`: `shouldUseSkills` only leaves the trained path for `toolChoice == none`, an `explicitSkill` override, or a `search_memory` + explicit-request case. With a confident `toolChoice == send_message`, “Email Dana the slides are ready” therefore stays on the trained `send_message` path.
- `Assistant.swift:257-285`: the `ArgumentExtractor` has no `send_email` case, and its `send_message` contact pattern is only `(?i:text|message|tell|send)`. “Email Dana the slides are ready” therefore has no contact, so the trained path asks “Who should I message?” rather than opening Mail; a phrasing that does match `message`/`send` opens Messages. `ActionPlanner.swift:259-265` only runs that extractor for executor tools, so even a skill-path `email_compose` has no body extraction for the same utterance (it asks for a body unless “saying”/colon is used).
- B:43 reasoning explicitly noted “there’s no `send_email` option in `toolChoice`, so it’s only reachable if something plans it.” B:175 says `send_email` opens Mail the same way as `send_message`; F:120 lists `email_compose` as a built-in. The routing bridge between those statements is missing.
- The current test suite checks `email_compose` by id/retrieval, but has no end-to-end “confident `send_message` + email wording -> `skill:email_compose`” test.

**Why it matters**

A user who says “Email Dana the slides are ready” gets the trained `send_message` path: with the current extractor it asks “Who should I message?”, and a phrasing that matches `message`/`send` can open Messages instead of Mail. The P1 deliverable added a real `send_email` handler and the skills registry advertises email composition, but the normal route never chooses it. It works only when the model happens to return `none` (or a non-tool route with an explicit phrase that is not in the list).

**Smallest repair**

Add `email`, `e-mail`, `mail` to the `send_message` override list and to `explicitRequest` (or add a dedicated `email` explicit-request check), then add a `send_email`/email-body extraction fallback in `ArgumentExtractor`/`SkillArgs`. Test with a scripted confident `send_message` and “Email Dana the slides are ready”: the plan must be `skill:email_compose`, the body must be “the slides are ready”, and the hard confirmation must run.

### BF-2 — P2: `memory_recall` returns a placeholder, not the memory answer

**Evidence**

- `core/Sources/PocketCore/Skills.swift:480-481`: `memory_recall` is a native `search_memory` skill, advertised as “Recall something I told you”.
- `ActionPlanner.swift:19-20`: `executorTools` includes `search_memory`.
- `ActionPlanner.swift:151-152`: `Assistant.execute` sends every native executor tool to `ActionExecutor.perform`.
- `app/PocketGlimmer/Actions/SystemActions.swift:104-105`: `perform("search_memory")` returns `"Searched memory"` and its comment says PocketCore answers this before `perform()` is reached.
- `Assistant.swift:223-227`: the real memory answer exists only in `toolPath`'s direct `action.tool == "search_memory"` branch. That branch is bypassed when the skill path calls `Assistant.execute`.
- The `memory_recall` path therefore returns the placeholder even though `MemoryStore.retrieve` is available. No SkillsTests case exercises `memory_recall` execution.

**Repro**

Give the Assistant a registry, set the trained `toolChoice` to `none` (or otherwise force the skill path), let `skillPick` choose `memory_recall`, and call `handle("what did I say my locker code was")`; the executed action returns `Searched memory` (or the test recorder's equivalent), not the retrieved facts.

**Smallest repair**

Special-case `.native("search_memory")` in `Assistant.execute` and use the same `memory.retrieve` response as `toolPath`, or remove `search_memory` from `executorTools` and let a core `memory_recall` branch handle it. Add a test that plans and executes `skill:memory_recall` and asserts the recalled text, not the placeholder.

### BF-3 — P1/P2: skill text paths can send to Muse Spark while the app shows an on-device result and omits the sensitivity card/privacy payload

**Evidence**

- `ActionPlanner.swift:145-202`: `Assistant.execute` returns only `String`. `reason()` is used for `email_digest` (153-157), `analyze_document` (158-165), and `cloudReason` summarize/translate (175-178); `html_viz` only asks the local model for a title (166-174). For text over 2,500 characters, online with a configured cloud, and a sensitivity result of `ok`, `reason()` calls `cloud.complete` and returns the cloud answer as a plain string (187-202).
- `Assistant.execute` is called from `planSkillCore` at `ActionPlanner.swift:140`; successful skill execution becomes `.acted(try await execute(action))`.
- `app/PocketGlimmer/AppModel.swift:214`: the `.acted` case renders the badge `onDevice` (“on device · … ms”). `AppModel.swift:239`: confirm-path skill results are appended with no provider/badge and no `cloudPromptSent`.
- `Assistant.swift:32` defines `cloudPromptSent` on `AssistantTurn`, but it is set only on the main cloud branch (`Assistant.swift:167`). Skill cloud calls never set it.
- `ActionPlanner.reason` performs a `sensitivity` decision but does not append it to the `decisions` inout array; unlike the main `Assistant.handle` path, the user does not see the sensitivity card for a cloud-bound shared document/email.
- `docs/SKILLS.md:72-77` says long email/document threads escalate to Muse Spark “only when online and configured, and only if the sensitivity decision says the text is OK”; the UI path above does not expose that this happened or show the sent payload.
- This is distinct from N2. N2 is the first-400-character screening weakness; this finding remains even if N2 is fixed: the result is mislabeled and the cloud prompt is not surfaced.

**Why it matters**

A user shares a long email/document, sees a skill confirmation such as “Summarize my recent emails: 5?”, and can receive a Muse Spark answer while the app’s ordinary `.acted` badge says “on device” and there is no privacy-sheet/`cloudPromptSent` record. The sensitivity card that the product uses to explain withholding is absent on this path.

**Smallest repair**

Return a typed result from skill execution (or a small `SkillExecution` carrying text, provider, `cloudPromptSent`, and the sensitivity decision) and have `AppModel.send` render `.cloud`/a cloud badge when `reason()` used the network. Append the sensitivity decision to `turn.decisions`. If that plumbing is too large for the deadline, keep long shared-text summaries local-only until it exists.

### BF-4 — P2 data contract: the distillation JSONL includes null-context rows that the labeling script expects to be strings

**Evidence**

- `core/Sources/PocketCore/Telemetry.swift:16`: `DecisionRecord.context` is `String?` with a nil default; the pre-P0.5 migration at 52-54 adds a nullable `context` column.
- `Telemetry.swift:83-98`: `exportDistillationQueue` selects every escalated row and writes `"context": r.context ?? NSNull()`; it does not skip rows without context.
- `Telemetry.swift:152-160`: old rows decode `context` as nil; they remain in the table.
- `training/round2/label_round2.py:46` admits rows whose `r["context"]` is `None` (it only filters against `seen`), and `:102` passes `r["context"]` to `prompts.chat_messages`. The app's export row count includes those rows.
- B:107 reasoning explicitly planned to skip rows without a context “since they can’t be labelled”; B:175/§P0.5 describes the schema but does not mention the skip. The implementation did not land.
- This is present at `581fa3a` and `159d287`.

**Why it matters**

The app can export a JSONL line with `"context": null` for decisions made before the P0.5 schema migration. The downstream teacher-labeling path expects a string and may mislabel or fail on those lines; the Settings row counts them as exportable rows.

**Smallest repair**

In `exportDistillationQueue`, `guard let context = r.context, !context.isEmpty else { continue }` (or explicitly mark/drop non-labelable rows) and add a test that writes a pre-context escalated row, migrates, exports, and asserts no null-context JSON line.

### BF-5 — P2 privacy: memory aliases are rendered in the cloud profile but are not in the scrubber’s known names

**Evidence**

- `core/Sources/PocketCore/MemoryProfile.swift:54-55`: `entityNames()` returns only non-user **subjects** (`active().map(\.subject)`), not `MemoryFact.aliases`.
- `MemoryProfile.swift:109-113`: `profileOnePager` renders each entity as `Subject (aka alias1, alias2): …`, so aliases are in the 400-character cloud profile when the entity has a non-sensitive fact.
- `Assistant.swift:94-97`: `cloudScrubber()` adds `memory.entityNames()` to `PrivacyScrubber.knownNames`. It does not add aliases.
- `Scrubber.swift:36-38`: only `knownNames` are masked as `[PERSON_n]`.
- B:33 and B:53 reasoning explicitly said entity **names and aliases** should be fed to the scrubber; B:175 says “memory entity names”, not aliases. The alias half did not land.
- This is separate from N1: N1 is the lack of sensitivity filtering on retrieved facts. This is name masking for aliases in the profile and in the user utterance.

**Why it matters**

If an alias is a private nickname or a name not present in Contacts (a supported alias use), the cloud profile can contain the alias and the user utterance can contain it while the scrubber does not know it. The profile is otherwise described and tested as scrubbed.

**Smallest repair**

Make `entityNames()` return the union of non-user subjects and their active aliases, or append `aliases(forSubject:)` in `cloudScrubber()`. Add a cloud-prompt test with a synthetic alias and assert the alias is replaced with `[PERSON_n]` and restored in the answer.

### BF-6 — P2 risk (interaction): uncertain offline sensitivity bypasses the offline answerability gate

**Evidence**

- `core/Sources/PocketCore/Decision.swift:113-117`: `sensitivity` has `fallbackID: "sensitive"`.
- `core/Sources/PocketCore/Reflex.swift:53`: `chosen = escalated ? fallback : argmax`. A below-τ sensitivity decision is therefore `chosen.id == "sensitive"` even when the model did not confidently choose it.
- `Assistant.swift:151-165`: the `escalate_cloud` branch returns a local answer with `cloudWithheldForSensitivity: true` as soon as `sens.chosen.id == "sensitive"`. The `guard online`/`answerability` block (167-177) is after that return and is not reached.
- B:37/B:39 reasoning recognized that uncertain offline sensitivity would be treated as withheld; B:175 does not disclose that this bypasses the later answerability/no-guess gate.
- Present at `581fa3a` and `159d287`.

**Why it matters**

For an offline question that the route wanted to escalate, a low-confidence sensitivity result produces an unverified local generation and the “kept on device” badge instead of the “can’t answer that offline” path. It is privacy-safe but can produce a made-up answer, which is the behavior the answerability gate exists to prevent. If this is intentional (safe-default semantics), it should be documented; if not, the answerability check should run for `sens.escalated` as well, or the sensitive fallback should be distinguished from a confident sensitive choice.

### BF-7 — P3 honesty: `autoreply_rule` promises a reminder that no code consumes

- `app/PocketGlimmer/Actions/SkillRunner.swift:102-110` saves an `autoreply_rule` fact and returns “For Instagram, I'll remind you when you open it.”
- A tree-wide search finds no consumer of the `autoreply_rule` attribute in `Proactive.swift`, `MemoryProfile.swift`, or the nudge rules; it is only stored and displayed/retrieved.
- The skill/docs otherwise honestly say iOS cannot answer Instagram DMs and point to Shortcuts. The specific “I'll remind you” promise is not backed by a rule. Either add a nudge rule for the fact or change the status to “saved; I won't be able to act on it automatically.”

### BF-8 — P3 process/authorization: F's Assistant.swift change exceeded the coordination note's single-hook scope

- B:127 authorized F's `Assistant.swift` change as **one ≤15-line hook in `toolPath`** (the `tool.chosen.id != "none"` line) plus a `public var skills` property, and a `.skillPick` case at the end of `DecisionType`.
- F:120 reports `skills`, `skillRunner`, a hook in `toolPath`, **a second guarded hook after `route`**, and `confirm` now calling `execute` — plus the decision case and the CoreTests 12→13 update. The extra `skillOverride` hook is what makes non-tool routes reach the skill planner; it is functionally useful but was not in the stated narrow scope. F disclosed it in the final, and B's tests remained green; this is a sign-off item, not a hidden change.
- No conflicting edit was found, and B's `toolPath` guard structure was preserved. The only authorization discrepancy is the extra `Assistant.swift` surface described above; it was disclosed in F:120 rather than hidden.

### Additional low-severity observations (not counted as new findings)

- **Intent-blind lexical override:** `ActionPlanner.explicitRequest` includes `battery`, `storage left`, `chart`, `graph`, and `weather`, and `shouldUseSkills` applies it when `toolChoice == search_memory`. A memory question such as “what did I say about my battery replacement?” can therefore be routed to `device_status` rather than recall; `create_reminder` + “alarm” similarly catches “remind me to buy an alarm clock.” There is no test for these false positives.
- **Stale latency claim:** `README.md:199` still says phone latency will differ “(Metal, KV-prefix reuse)”, while `LlamaCppEngine.prefixReuseDefault` is now `false` and the Settings toggle defaults off. The same file's rehearsal note says prefix reuse is off. This is a documentation mismatch, not a code path.
- **Shared-text phrasing:** `HandleTextIntent.utterance(for:source:)` with the default instruction `Summarize this` and a Mail source produces “Summarize this these emails”. Retrieval still reaches `email_digest`, so this is cosmetic.
- **Compose-sheet continuation failure:** `ComposeSheets.message`/`mail` (`SystemActions.swift`) await a `CheckedContinuation` and only resume in the delegate callbacks. `isModalInPresentation` prevents swipe-dismiss, but a failed `top.present(...)` or a delegate that never fires would leave `Assistant.confirm`/`AppModel.busy` waiting indefinitely. B:167 reasoning identified the general risk; this is an unverified iOS-only edge (P3 app risk).

---

## 3. Known items deliberately not counted as new

- **N1 (retrieved-memory sensitivity filter):** still present in the current `Assistant` cloud path (`mem` is concatenated unfiltered before scrubbing). This is the root's known P1; I did not re-report it as a discovery. The alias-masking gap in BF-5 is a different predicate (name masking, not health/money sensitivity).
- **N2 (first-400-character screening):** still present at `ActionPlanner.reason` (`String(text.prefix(400))` then up to 24,000 characters sent). This is the known root P1/P2; BF-3 is the separate disclosure/consent gap and would remain after an N2 fix.
- **N3:** the Settings/footer backup wording is corrected in the current tree (“device backup settings may include it”); not re-opened.
- **N4:** the numeric timing comment is removed from `LlamaCppEngine.swift`; the remaining `addBOS` comment is the corrected token-stream note. Not re-opened.
- **N5:** `store:false` versus ZDR is documented; not re-opened.

---

## 4. Coverage verdict and residual gaps

**Retained-content verdict: COMPLETE.** All 177 B and 122 F positions have a full retained-body read in the union of the prior pass and this pass (to the marker or retained end); all 117 B/F reasoning items were read here to their retained end; all command, dynamic-tool, assistant, user, file-change, and checkpoint positions are accounted for. No item was skipped on the basis of a title/head/path/current file/keyword match.

**Byte-completeness verdict: NOT COMPLETE.** Twenty-one B/F items retain `[Earlier output truncated]`; B:48 has an unmarked mid-sentence cut. Their exact historical bytes are not recoverable from the retained history. Baseline files at `581fa3a` can verify source claims for tracked paths, but they are not the historical command outputs. I cannot claim that no material finding could be hidden in those missing bytes; I can claim that every available retained byte in B/F was read and that the findings above are supported by current code and retained reasoning.

**No unresolved tool limit:** there is no item left at an arbitrary pagination stop. The only continuations were the 18 multi-chunk items listed in 1.3, all completed to `nextTextOffset: null`.

**Effect on readiness:** BF-1 and BF-3 are the important integration/claims gaps. BF-1 leaves the P1 `send_email` handler effectively unreachable for ordinary email wording; BF-3 can let a skill cloud call look on-device and hide both the sensitivity card and the sent-payload view. BF-2 is a concrete broken advertised skill; BF-4 is a distillation-data contract defect; BF-5 is a narrow but real privacy gap in the alias path. BF-6–BF-8 are lower-severity behavior/scope notes.

Report: `/tmp/pocket-glimmer-takeover/history-retained-bf.md`
