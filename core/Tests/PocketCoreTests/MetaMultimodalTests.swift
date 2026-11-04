import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PocketCore

/// Records every request the multimodal clients send and replies from a script keyed by URL path.
final class FakeTransport: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requests: [URLRequest] = []
    var replies: [String: (Int, Data)] = [:]
    func record(_ req: URLRequest) -> (Data, Int) {
        lock.lock(); defer { lock.unlock() }
        requests.append(req)
        let path = req.url?.path ?? ""
        for (k, v) in replies where path.hasSuffix(k) { return (v.1, v.0) }
        return (Data("{}".utf8), 404)
    }
    var transport: HTTPTransport {
        { [self] req in
            return self.record(req)
        }
    }
}

final class MMActions: ActionExecutor, @unchecked Sendable {
    func searchContacts(_ q: String) async throws -> [String] { [] }
    func searchEvents(_ q: String) async throws -> [String] { [] }
}

final class MetaMultimodalTests: XCTestCase {
    // Live SAM 3.1 output for eval/meta_api/fixtures/bars.jpg, prompt "bar" (eval/meta_api/sam_segment_bars.json).
    static let samBars = #"<0f>0<|box;x1=188;y1=120;x2=273;y2=360;w=640;h=400;c=0.9139785170555115|><|mask;x=0;y=0;c=0.9139785170555115;data=241,86,!!!!!KK.2_x7U^wU=U[[P(_o:/){Mb4SnANFtS_$6J2/aOoxG'`!!|>,1<|box;x1=512;y1=189;x2=598;y2=360;w=640;h=400;c=0.9139785170555115|><|mask;x=0;y=0;c=0.9139785170555115;data=172,87,!!!!!6LBrHND0Nz_?#5]SVfC4RwS[%|>,2<|box;x1=80;y1=258;x2=165;y2=360;w=640;h=400;c=0.9139785170555115|><|mask;x=0;y=0;c=0.9139785170555115;data=103,86,!!!!!0Na'T(.x`xFE`4xx!!|>,3<|box;x1=404;y1=52;x2=490;y2=360;w=640;h=400;c=0.9101123809814453|><|mask;x=0;y=0;c=0.9101123809814453;data=309,87,!!!!!NK.2Z[y$S4KK-7[W-_?PjL+2cPTflZbAHnOTGK2NgvG!B-BubT'|>,4<|box;x1=296;y1=224;x2=382;y2=360;w=640;h=400;c=0.9139785170555115|><|mask;x=0;y=0;c=0.9139785170555115;data=137,87,!!!!!=LBo9Ye2Pd134B=ZPppuo&3L7*=4hlp|>"#

    static let wav = WAVFile.make(pcm: Data((0..<3200).map { UInt8($0 % 251) }))     // 100 ms, 16 kHz mono s16le

    /// SOI, APP0/JFIF, APP1/Exif (with a fake GPS IFD), APP2/ICC, DQT, SOF0, DHT, SOS + entropy data (with FF00 stuffing), EOI.
    static let jpeg = makeJPEG(withMetadata: true)
    static func makeJPEG(withMetadata: Bool) -> Data {
        func seg(_ m: UInt8, _ payload: [UInt8]) -> [UInt8] { let n = payload.count + 2; return [0xFF, m, UInt8(n >> 8), UInt8(n & 0xFF)] + payload }
        var b: [UInt8] = [0xFF, 0xD8]
        b += seg(0xE0, Array("JFIF".utf8) + [0, 1, 1, 0, 0, 1, 0, 1, 0, 0])
        if withMetadata {
            b += seg(0xE1, Array("Exif".utf8) + [0, 0] + Array("MM\u{0}*GPSLatitude=40.7128N;GPSLongitude=74.0060W".utf8))
            b += seg(0xE2, Array("ICC_PROFILE".utf8) + [0, 1, 1] + [UInt8](repeating: 0xAB, count: 20))
        }
        b += seg(0xDB, [0] + [UInt8](repeating: 1, count: 64))
        b += seg(0xC0, [8, 0, 16, 0, 16, 1, 1, 0x11, 0])
        b += seg(0xC4, [0] + [UInt8](repeating: 0, count: 16))
        b += seg(0xDA, [1, 1, 0, 0, 63, 0])
        b += [0x12, 0x34, 0xFF, 0x00, 0x56, 0xFF, 0xD0, 0x78]      // entropy-coded data, a stuffed FF and an RST0
        b += [0xFF, 0xD9]
        return Data(b)
    }

    func makeGate(_ e: ScriptedEngine, online: Bool, fake: FakeTransport) throws -> (MultimodalGate, TelemetryLog, FakePhoneEffects) {
        let db = try SQLiteDB(path: ":memory:"); let tel = try TelemetryLog(db: db)
        let acts = MMActions()
        let effects = FakePhoneEffects()
        let a = Assistant(reflex: Reflex(engine: e, telemetry: tel, source: "test"), memory: try MemoryStore(db: db), actions: acts,
                          ledger: try EffectLedger(db: db), effects: effects, isOnline: { online })
        var t = MetaVoiceTranscriber(apiKey: "test-key"); t.transport = fake.transport
        var v = MetaVision(apiKey: "test-key"); v.transport = fake.transport
        return (MultimodalGate(assistant: a, transcriber: t, vision: v), tel, effects)
    }

    static func chatReply(_ content: String?) -> (Int, Data) {
        let c: Any = content ?? NSNull()
        let j: [String: Any] = ["choices": [["message": ["role": "assistant", "content": c]]],
                                "usage": ["prompt_tokens": 552, "completion_tokens": 359, "completion_tokens_details": ["reasoning_tokens": 331]]]
        return (200, try! JSONSerialization.data(withJSONObject: j))
    }
    static func samReply(_ text: String) -> (Int, Data) {
        let j: [String: Any] = ["object": "response", "status": "completed", "model": "sam-3.1",
                                "output": [["type": "message", "role": "assistant", "content": [["type": "output_text", "text": text]]]],
                                "usage": ["input_tokens": 0, "output_tokens": 0, "images_processed": 1]]
        return (200, try! JSONSerialization.data(withJSONObject: j))
    }
    static let sensitiveQ = "acceptable to send this request"

    // MARK: voice

    func testTranscribeMultipartCarriesAudioAndModel() async throws {
        let fake = FakeTransport()
        fake.replies["asr/transcribe"] = (200, Data(#"{"sessionId":"s1","transcript":"remind me to call mom at seven tonight.","audioDurationMs":2640,"turns":[]}"#.utf8))
        var t = MetaVoiceTranscriber(apiKey: "k"); t.transport = fake.transport
        let (tr, sum) = try await t.transcribe(audio: Self.wav)
        XCTAssertEqual(tr.text, "remind me to call mom at seven tonight."); XCTAssertEqual(tr.durationMs, 2640)
        XCTAssertEqual(tr.model, "muse-voice-transcribe-1.0")
        let req = try XCTUnwrap(fake.requests.first)
        XCTAssertEqual(req.url?.absoluteString, "https://api.meta.ai/v1/asr/transcribe")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertTrue(req.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data; boundary="))
        let body = try XCTUnwrap(req.httpBody)
        XCTAssertNotNil(body.range(of: Self.wav), "audio bytes are in the body verbatim")
        let s = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(s.contains(#"name="request""#) && s.contains(#"name="audio"; filename="clip.wav""#), s)
        XCTAssertTrue(s.contains(#""model":"muse-voice-transcribe-1.0""#) && s.contains(#""audioEncoding":"WAV""#) && s.contains(#""mode":"PUSH_TO_TALK""#), s)
        XCTAssertEqual(sum.bytesSent, body.count); XCTAssertEqual(sum.mediaBytes, Self.wav.count); XCTAssertEqual(sum.textSent, "")
    }

    func testWAVCanonicalizerDropsExtraChunksAndValidatesFormat() throws {
        // AVAudioRecorder-style file: fmt, FLLR padding, LIST, then data.
        let pcm = Data((0..<6400).map { UInt8($0 & 0xFF) })
        let canon = WAVFile.make(pcm: pcm)
        var messy = Data(canon.prefix(36))                                                 // RIFF..fmt chunk
        messy.append(Data("FLLR".utf8)); messy.append(contentsOf: [7, 0, 0, 0]); messy.append(Data(repeating: 0, count: 8))   // odd size + pad byte
        messy.append(Data("LIST".utf8)); messy.append(contentsOf: [4, 0, 0, 0]); messy.append(Data("INFO".utf8))
        messy.append(canon.suffix(from: 36))                                               // data chunk
        let (out, info) = try XCTUnwrap(WAVFile.canonical(messy))
        XCTAssertEqual(out, canon); XCTAssertEqual(out.count, 44 + pcm.count)
        XCTAssertEqual(info, WAVFile.Info(sampleRate: 16_000, channels: 1, bitsPerSample: 16, durationMs: 200))
        XCTAssertTrue(WAVFile.isAccepted(info))
        XCTAssertFalse(WAVFile.isAccepted(WAVFile.canonical(WAVFile.make(pcm: pcm, sampleRate: 44_100, channels: 2))!.info))
        XCTAssertNil(WAVFile.canonical(Data("ftypM4A ".utf8)))
    }

    func testTranscriberRejectsNonWAVAndContributorModels() throws {
        let t = MetaVoiceTranscriber(apiKey: "k")
        XCTAssertThrowsError(try t.makeRequest(audio: Data("not audio at all".utf8), mimeType: "audio/m4a"))
        XCTAssertThrowsError(try MetaVoiceTranscriber(apiKey: "k", model: "muse-spark-1.3-contributor").makeRequest(audio: Self.wav)) {
            XCTAssertEqual($0 as? MultimodalError, .contributorModeRefused("muse-spark-1.3-contributor"))
        }
        XCTAssertThrowsError(try MetaVision(apiKey: "k", visionModel: "muse-spark-1.3-contributor").makeDescribeRequest(imageJPEG: Self.jpeg, question: "q"))
    }

    func testVoiceTranscriptGoesThroughTheSameAssistantPath() async throws {
        let e = ScriptedEngine()
        e.script(whenPromptContains: "long-term memory", logits: ["A": -3, "B": -3, "C": 3])
        e.script(whenPromptContains: "How should", logits: ["A": -3, "B": 5, "C": -3, "D": -3])
        e.script(whenPromptContains: "Which tool", logits: ["A": 5, "B": 0, "C": 0, "D": 0, "E": 0, "F": 0, "G": 0])
        e.script(whenPromptContains: "explicit confirmation", logits: ["A": 4, "B": -2])
        let fake = FakeTransport()
        fake.replies["asr/transcribe"] = (200, Data(#"{"sessionId":"s","transcript":"Remind me to call Mom at 7pm","audioDurationMs":2000,"turns":[]}"#.utf8))
        let (gate, tel, effects) = try makeGate(e, online: true, fake: fake)
        let v = try await gate.voiceTurn(audio: Self.wav)
        guard case .acted(let effect)? = v?.turn.reply else { return XCTFail("\(String(describing: v?.turn.reply))") }
        XCTAssertTrue(effect.phase.isCommitted)
        XCTAssertEqual(text(effects.performed.first!.action, "title"), "call Mom")
        XCTAssertEqual(try tel.all().map(\.decisionType), [.rememberOrNot, .route, .toolChoice, .confirmBeforeAct])
        XCTAssertEqual(fake.requests.count, 1, "only the transcription left the phone")
    }

    func testVoiceOfflineSendsNothing() async throws {
        let fake = FakeTransport()
        let (gate, _, _) = try makeGate(ScriptedEngine(), online: false, fake: fake)
        let v = try await gate.voiceTurn(audio: Self.wav)
        XCTAssertNil(v); XCTAssertTrue(fake.requests.isEmpty)
    }

    // MARK: vision

    func testDescribeRequestHasDataURLAndQuestion() async throws {
        let fake = FakeTransport(); fake.replies["chat/completions"] = Self.chatReply("The tallest bar is Thu with 9 thousand steps.")
        var v = MetaVision(apiKey: "k"); v.transport = fake.transport
        let (a, s) = try await v.describe(imageJPEG: Self.jpeg, question: "What is the tallest bar?")
        XCTAssertEqual(a.text, "The tallest bar is Thu with 9 thousand steps.")
        XCTAssertEqual(a.usage.reasoningTokens, 331)
        let req = try XCTUnwrap(fake.requests.first)
        XCTAssertEqual(req.url?.absoluteString, "https://api.meta.ai/v1/chat/completions")
        let j = try XCTUnwrap(JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any])
        XCTAssertEqual(j["model"] as? String, "muse-spark-1.3"); XCTAssertEqual(j["reasoning_effort"] as? String, "low")
        let user = try XCTUnwrap((j["messages"] as? [[String: Any]])?.last)
        let parts = try XCTUnwrap(user["content"] as? [[String: Any]])
        XCTAssertEqual(parts.first?["text"] as? String, "What is the tallest bar?")
        let url = try XCTUnwrap((parts.last?["image_url"] as? [String: Any])?["url"] as? String)
        XCTAssertEqual(url, "data:image/jpeg;base64," + Self.jpeg.base64EncodedString())
        XCTAssertEqual(s.model, "muse-spark-1.3"); XCTAssertEqual(s.bytesSent, req.httpBody!.count)
    }

    func testDescribeAllReasoningNoContentIsAnError() async throws {
        let fake = FakeTransport(); fake.replies["chat/completions"] = Self.chatReply(nil)
        var v = MetaVision(apiKey: "k"); v.transport = fake.transport
        do { _ = try await v.describe(imageJPEG: Self.jpeg, question: "q"); XCTFail("expected emptyAnswer") }
        catch { XCTAssertEqual(error as? MultimodalError, .emptyAnswer) }
    }

    func testSegmentRequestAndParseLiveSAMOutput() async throws {
        let fake = FakeTransport(); fake.replies["/responses"] = Self.samReply(Self.samBars)
        var v = MetaVision(apiKey: "k"); v.transport = fake.transport
        let (seg, s) = try await v.segment(imageJPEG: Self.jpeg, prompt: "bar")
        let req = try XCTUnwrap(fake.requests.first)
        XCTAssertEqual(req.url?.absoluteString, "https://api.meta.ai/v1/responses")
        let j = try XCTUnwrap(JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any])
        XCTAssertEqual(j["model"] as? String, "sam-3.1")
        XCTAssertEqual(j["store"] as? Bool, false, "Responses default store:true; segmentation must opt out")
        XCTAssertEqual((j["metadata"] as? [String: String])?["mask_encoding"], "one_bit")
        let content = try XCTUnwrap(((j["input"] as? [[String: Any]])?.first?["content"]) as? [[String: Any]])
        XCTAssertEqual(content.first?["text"] as? String, "bar")
        XCTAssertEqual(content.last?["image_url"] as? String, "data:image/jpeg;base64," + Self.jpeg.base64EncodedString())
        XCTAssertEqual(seg.segments.map(\.id), [0, 1, 2, 3, 4]); XCTAssertEqual(seg.usage.imagesProcessed, 1)
        let tallest = try XCTUnwrap(seg.segments.min { $0.box.y1 < $1.box.y1 })
        XCTAssertEqual(tallest.box, SegmentBox(x1: 404, y1: 52, x2: 490, y2: 360, imageWidth: 640, imageHeight: 400))
        XCTAssertEqual(tallest.confidence ?? 0, 0.9101, accuracy: 1e-3)
        XCTAssertEqual(tallest.mask?.height, 309); XCTAssertEqual(tallest.mask?.width, 87); XCTAssertEqual(tallest.mask?.encoding, "one_bit")
        XCTAssertEqual(s.model, "sam-3.1")
        XCTAssertTrue(SAMOutputParser.parse("", label: "x").isEmpty, "zero matches is a valid empty result")
    }

    func testOneBitMaskDecodesToMetasReferenceRaster() throws {
        // Reference values from Meta's meta-sam-parser 0.1.0 decode_mask_to_raster on the same payload.
        let seg = SAMOutputParser.parse(Self.samBars, label: "bar")
        let r = try XCTUnwrap(seg[2].mask).raster()
        XCTAssertEqual(r.count, 103 * 86)
        XCTAssertEqual(r.reduce(0) { $0 + Int($1) }, 8849)
        XCTAssertEqual(r.indices.filter { r[$0] == 1 }.reduce(0, +) % 1_000_003, 183_255)
        XCTAssertEqual(Array(r.prefix(8)), [0, 1, 1, 1, 1, 1, 1, 1])
        let all = try seg.map { try $0.mask!.raster().reduce(0) { $0 + Int($1) } }
        XCTAssertEqual(all, [20611, 14945, 8849, 26750, 11885])
        XCTAssertThrowsError(try SAMMaskCodec.decodeOneBit("!!!!!0Na'T(.x`xFE`4xx", width: 86, height: 103), "truncated payload")
        XCTAssertThrowsError(try SAMMaskCodec.decodeOneBit("~!!!!0Na'T(.x`xFE`4xx!!", width: 86, height: 103), "lossless marker")
    }

    // MARK: EXIF

    func testStripperDropsExifAndICCKeepsImageSegments() throws {
        let r = try XCTUnwrap(JPEGMetadataStripper.strip(Self.jpeg))
        XCTAssertEqual(r.removed, ["APP1/Exif", "APP2/ICC"])
        let b = [UInt8](r.data)
        XCTAssertEqual(Array(b.prefix(2)), [0xFF, 0xD8]); XCTAssertEqual(Array(b.suffix(2)), [0xFF, 0xD9])
        XCTAssertNil(r.data.range(of: Data("Exif".utf8))); XCTAssertNil(r.data.range(of: Data("GPSLatitude".utf8)))
        XCTAssertNil(r.data.range(of: Data("ICC_PROFILE".utf8)))
        for m: UInt8 in [0xE0, 0xDB, 0xC0, 0xC4, 0xDA] { XCTAssertNotNil(r.data.range(of: Data([0xFF, m])), String(m, radix: 16)) }
        XCTAssertNotNil(r.data.range(of: Data([0x12, 0x34, 0xFF, 0x00, 0x56, 0xFF, 0xD0, 0x78])), "entropy data untouched")
        XCTAssertEqual(r.data, Self.makeJPEG(withMetadata: false), "byte-identical to the same JPEG built without metadata")
        XCTAssertEqual(JPEGMetadataStripper.strip(r.data)?.data, r.data, "idempotent")
        XCTAssertNil(JPEGMetadataStripper.strip(Data([0x89, 0x50, 0x4E, 0x47])), "not a JPEG")
        XCTAssertNil(JPEGMetadataStripper.strip(Self.jpeg.prefix(30)), "truncated fails closed")
    }

    // MARK: gate

    func testGateKeepsSensitivePhotoOnDevice() async throws {
        let e = ScriptedEngine(); e.script(whenPromptContains: Self.sensitiveQ, logits: ["A": -5, "B": 5])
        let fake = FakeTransport()
        let (gate, tel, _) = try makeGate(e, online: true, fake: fake)
        let r = try await gate.glimpse(imageJPEG: Self.jpeg, intent: "What do these numbers mean?", task: .describe(question: "What do these numbers mean?"))
        XCTAssertTrue(r.keptOnDevice); XCTAssertTrue(fake.requests.isEmpty); XCTAssertNil(r.cloudPayloadSummary)
        XCTAssertEqual(r.decisions.map(\.type), [.sensitivity])
        let rec = try XCTUnwrap(try tel.all().first)
        XCTAssertEqual(rec.decisionType, .sensitivity); XCTAssertTrue(rec.context?.contains("[photo attached]") ?? false, rec.context ?? "nil")
    }

    func testGateLexicalFloorAndUserToggleAndOffline() async throws {
        let e = ScriptedEngine(); e.script(whenPromptContains: Self.sensitiveQ, logits: ["A": 5, "B": -5])   // model says ok
        let fake = FakeTransport()
        let (gate, _, _) = try makeGate(e, online: true, fake: fake)
        var r = try await gate.glimpse(imageJPEG: Self.jpeg, intent: "split this receipt", task: .describe(question: "split this receipt"))
        XCTAssertTrue(r.keptOnDevice, "receipts never leave even when the model says ok")
        r = try await gate.glimpse(imageJPEG: Self.jpeg, intent: "what is this?", task: .describe(question: "what is this?"), photoText: "VISA **** 4421 TOTAL $42.10")
        XCTAssertTrue(r.keptOnDevice, "on-device OCR text with a card number keeps it local")
        gate.photosStayOnDevice = true
        r = try await gate.glimpse(imageJPEG: Self.jpeg, intent: "what plant is this?", task: .describe(question: "what plant is this?"))
        XCTAssertTrue(r.keptOnDevice)
        XCTAssertTrue(fake.requests.isEmpty)

        let (offline, _, _) = try makeGate(e, online: false, fake: fake)
        r = try await offline.glimpse(imageJPEG: Self.jpeg, intent: "what plant is this?", task: .describe(question: "what plant is this?"))
        XCTAssertEqual(r.outcome, .offline(MultimodalGate.offlineMessage)); XCTAssertEqual(r.decisions.count, 1)
        XCTAssertTrue(fake.requests.isEmpty)
    }

    func testGateWithholdsAmountOnlyReceiptsEvenWhenClassifierSaysOK() async throws {
        let e = ScriptedEngine(); e.script(whenPromptContains: Self.sensitiveQ, logits: ["A": 5, "B": -5])
        let fake = FakeTransport()
        fake.replies["chat/completions"] = Self.chatReply("A cash receipt.")
        let (gate, _, _) = try makeGate(e, online: true, fake: fake)
        for text in ["TOTAL 42.10", "Subtotal: 1,234.56", "Amount due\nEUR 42,10", "Balance £42.10", "$42.10"] {
            let result = try await gate.glimpse(imageJPEG: Self.jpeg, intent: "what is this?",
                                              task: .describe(question: "what is this?"), photoText: text)
            XCTAssertTrue(result.keptOnDevice, text)
        }
        XCTAssertTrue(fake.requests.isEmpty)
        XCTAssertFalse(PhotoSensitivityHint.matches("A total of 42 sticky notes"))
    }

    func testGateStripsExifMasksTextAndRecordsPayloads() async throws {
        let e = ScriptedEngine(); e.script(whenPromptContains: Self.sensitiveQ, logits: ["A": 5, "B": -5])
        let fake = FakeTransport()
        fake.replies["chat/completions"] = Self.chatReply("Five sticky notes; one says call [PERSON_1] at 7.\nCONCEPT: sticky note")
        fake.replies["/responses"] = Self.samReply(Self.samBars)
        let (gate, _, _) = try makeGate(e, online: true, fake: fake)
        gate.assistant.scrubber.knownNames = ["Priya"]
        let r = try await gate.glimpse(imageJPEG: Self.jpeg, intent: "Summarize Priya's whiteboard",
                                       task: .describeAndSegment(question: "Summarize Priya's whiteboard", concept: nil))
        guard case .segmented(let segs, let answer) = r.outcome else { return XCTFail("\(r.outcome)") }
        XCTAssertEqual(segs.count, 5); XCTAssertEqual(answer, "Five sticky notes; one says call Priya at 7.")
        XCTAssertEqual(fake.requests.count, 2)
        for req in fake.requests {
            let body = String(decoding: try XCTUnwrap(req.httpBody), as: UTF8.self).replacingOccurrences(of: "\\/", with: "/")
            XCTAssertFalse(body.contains("Priya"), "names are masked before leaving")
            XCTAssertFalse(body.contains(Self.jpeg.base64EncodedString()), "original JPEG (with EXIF) never sent")
            XCTAssertTrue(body.contains(Self.makeJPEG(withMetadata: false).base64EncodedString()), "the stripped JPEG is what was sent")
        }
        let samBody = String(decoding: fake.requests[1].httpBody!, as: UTF8.self)
        XCTAssertTrue(samBody.contains(#""text":"sticky note""#), "Spark picked the SAM concept")
        XCTAssertEqual(r.cloudPayloads.map(\.model), ["muse-spark-1.3", "sam-3.1"])
        let s = try XCTUnwrap(r.cloudPayloadSummary)
        XCTAssertEqual(s.endpoint, "https://api.meta.ai/v1/chat/completions"); XCTAssertEqual(s.strippedMetadata, ["APP1/Exif", "APP2/ICC"])
        XCTAssertEqual(s.bytesSent, fake.requests[0].httpBody!.count)
        XCTAssertTrue(s.textSent.contains("[PERSON_1]") && !s.textSent.contains("Priya"), s.textSent)
        XCTAssertTrue(s.line.contains("muse-spark-1.3") && s.line.contains("APP1/Exif"), s.line)
        XCTAssertEqual(r.usage.imagesProcessed, 1); XCTAssertGreaterThan(r.usage.estimatedUSD, 0)
    }

    func testSegmentConceptIsMaskedBeforeRequest() async throws {
        let e = ScriptedEngine(); e.script(whenPromptContains: Self.sensitiveQ, logits: ["A": 5, "B": -5])
        let fake = FakeTransport(); fake.replies["/responses"] = Self.samReply(Self.samBars)
        let (gate, _, _) = try makeGate(e, online: true, fake: fake)
        gate.assistant.scrubber.knownNames = ["Priya"]

        let r = try await gate.glimpse(imageJPEG: Self.jpeg, intent: "Outline Priya's badge",
                                       task: .segment(concept: "Priya's badge"))
        guard case .segmented(let segs, let answer) = r.outcome else { return XCTFail("\(r.outcome)") }
        XCTAssertNil(answer); XCTAssertEqual(segs.count, 5)
        XCTAssertEqual(segs.first?.label, "Priya's badge", "labels are restored on the phone after the masked request")
        let req = try XCTUnwrap(fake.requests.first)
        let body = String(decoding: try XCTUnwrap(req.httpBody), as: UTF8.self).replacingOccurrences(of: "\\/", with: "/")
        XCTAssertFalse(body.contains("Priya"), "the SAM concept is masked before transport")
        XCTAssertTrue(body.contains(#""text":"[PERSON_1]'s badge""#), body)
        XCTAssertEqual(r.cloudPayloadSummary?.textSent, "[PERSON_1]'s badge")
        // The JPEG pixels themselves are what left the phone: only EXIF/GPS and the text are stripped or masked.
        let stripped = try XCTUnwrap(JPEGMetadataStripper.strip(Self.jpeg))
        XCTAssertEqual(r.cloudPayloadSummary?.mediaBytes, stripped.data.count)
        XCTAssertEqual(r.cloudPayloadSummary?.strippedMetadata, ["APP1/Exif", "APP2/ICC"])
    }

    func testDescribeAndSegmentMasksExplicitAndPickedConcepts() async throws {
        let e = ScriptedEngine(); e.script(whenPromptContains: Self.sensitiveQ, logits: ["A": 5, "B": -5])

        let picked = FakeTransport()
        picked.replies["chat/completions"] = Self.chatReply("This is Priya's badge.\nCONCEPT: priya's badge")
        picked.replies["/responses"] = Self.samReply(Self.samBars)
        let (pickedGate, _, _) = try makeGate(e, online: true, fake: picked)
        pickedGate.assistant.scrubber.knownNames = ["Priya"]
        var r = try await pickedGate.glimpse(imageJPEG: Self.jpeg, intent: "What is this?",
                                             task: .describeAndSegment(question: "What is this?", concept: nil))
        guard case .segmented(let pickedSegs, _) = r.outcome else { return XCTFail("\(r.outcome)") }
        XCTAssertEqual(pickedSegs.first?.label, "priya's badge")
        let pickedSAM = String(decoding: try XCTUnwrap(picked.requests.last?.httpBody), as: UTF8.self)
        XCTAssertFalse(pickedSAM.contains("Priya"), "Spark's picked concept is masked too")
        XCTAssertTrue(pickedSAM.contains("[PERSON_1]"), pickedSAM)

        let explicit = FakeTransport()
        explicit.replies["chat/completions"] = Self.chatReply("This is Priya's badge.")
        explicit.replies["/responses"] = Self.samReply(Self.samBars)
        let (explicitGate, _, _) = try makeGate(e, online: true, fake: explicit)
        explicitGate.assistant.scrubber.knownNames = ["Priya"]
        r = try await explicitGate.glimpse(imageJPEG: Self.jpeg, intent: "What is this?",
                                           task: .describeAndSegment(question: "What is this?", concept: "Priya's badge"))
        guard case .segmented(let explicitSegs, _) = r.outcome else { return XCTFail("\(r.outcome)") }
        XCTAssertEqual(explicitSegs.first?.label, "Priya's badge")
        let explicitSAM = String(decoding: try XCTUnwrap(explicit.requests.last?.httpBody), as: UTF8.self)
        XCTAssertFalse(explicitSAM.contains("Priya"), "the supplied concept is masked before transport")
        XCTAssertTrue(explicitSAM.contains(#""text":"[PERSON_1]'s badge""#), explicitSAM)
        XCTAssertEqual(r.cloudPayloads.last?.textSent, "[PERSON_1]'s badge")
    }
    // MARK: live (opt-in: PG_LIVE_META=1 + META_API_KEY + PG_META_DIR; ~$0.006 per run)

    func testLiveMetaAPIThroughTheGate() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["PG_LIVE_META"] == "1", let key = env["META_API_KEY"], !key.isEmpty else { throw XCTSkip("live Meta API test is opt-in") }
        // PG_META_DIR = eval/meta_api (mount it in docker: -v "$PWD/eval/meta_api:/meta" -e PG_META_DIR=/meta).
        let metaDir = URL(fileURLWithPath: env["PG_META_DIR"] ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("eval/meta_api").path)
        let fix = metaDir.appendingPathComponent("fixtures")
        guard let wav = try? Data(contentsOf: fix.appendingPathComponent("remind.wav")),
              let board = try? Data(contentsOf: fix.appendingPathComponent("whiteboard.jpg")) else { throw XCTSkip("fixtures not mounted") }
        let e = ScriptedEngine(); e.script(whenPromptContains: Self.sensitiveQ, logits: ["A": 5, "B": -5])
        let db = try SQLiteDB(path: ":memory:")
        let a = Assistant(reflex: Reflex(engine: e, telemetry: try TelemetryLog(db: db), source: "live"), memory: try MemoryStore(db: db),
                          actions: MMActions(), isOnline: { true })
        let gate = MultimodalGate(assistant: a, metaAPIKey: key)
        var lines: [String] = []
        func log(_ test: String, _ model: String, _ endpoint: String, _ u: TokenUsage, _ extra: String) {
            lines.append(#"{"test":"\#(test)","run":"swift-live","model":"\#(model)","endpoint":"\#(endpoint)","status":200,"usage":{"prompt_tokens":\#(u.promptTokens),"completion_tokens":\#(u.completionTokens),"reasoning_tokens":\#(u.reasoningTokens),"images_processed":\#(u.imagesProcessed),"audioDurationMs":\#(u.audioMs)},"usd":\#(String(format: "%.6f", u.estimatedUSD)),\#(extra)}"#)
        }
        let t0 = Date()
        let voice = try await gate.transcribe(audio: wav)
        let (tr, vs) = try XCTUnwrap(voice)
        XCTAssertTrue(tr.text.lowercased().contains("call mom"), tr.text)
        var vu = TokenUsage(); vu.audioMs = tr.durationMs
        log("swift_voice", tr.model, "/v1/asr/transcribe", vu, #""bytes_sent":\#(vs.bytesSent),"ms":\#(Int(Date().timeIntervalSince(t0) * 1000))"#)

        let t1 = Date()
        let r = try await gate.glimpse(imageJPEG: board, intent: "What's on my whiteboard?",
                                       task: .describeAndSegment(question: "What's on my whiteboard? List the notes.", concept: nil))
        guard case .segmented(let segs, let answer) = r.outcome else { return XCTFail("\(r.outcome)") }
        XCTAssertTrue(answer?.lowercased().contains("oat milk") ?? false, answer ?? "nil")
        XCTAssertEqual(r.cloudPayloads.map(\.model), ["muse-spark-1.3", "sam-3.1"])
        XCTAssertGreaterThanOrEqual(segs.count, 3, "SAM 3.1 should outline the sticky notes; concept=\(r.cloudPayloads.last?.textSent ?? "")")
        for sgm in segs { XCTAssertEqual(try sgm.mask?.raster().count, (sgm.mask?.width ?? 0) * (sgm.mask?.height ?? 0)) }
        log("swift_glimpse", "muse-spark-1.3+sam-3.1", "/v1/chat/completions+/v1/responses", r.usage,
            #""bytes_sent":\#(r.cloudPayloads.map(\.bytesSent).reduce(0, +)),"segments":\#(segs.count),"concept":"\#(r.cloudPayloads.last?.textSent ?? "")","ms":\#(Int(Date().timeIntervalSince(t1) * 1000))"#)
        let out = metaDir.appendingPathComponent("spend.jsonl")
        if let h = try? FileHandle(forWritingTo: out) { h.seekToEndOfFile(); h.write(Data((lines.joined(separator: "\n") + "\n").utf8)); try? h.close() }
        let summary = "transcript: \(tr.text)\nspark: \(answer ?? "")\nsam concept: \(r.cloudPayloads.last?.textSent ?? "") -> \(segs.count) segments\n" + r.cloudPayloads.map(\.line).joined(separator: "\n") + "\n"
        try? summary.write(to: metaDir.appendingPathComponent("swift_live_gate.txt"), atomically: true, encoding: .utf8)
    }
}
