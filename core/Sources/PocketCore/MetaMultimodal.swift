import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Meta Model API multimodal System 2: Muse Voice Transcribe (speech -> text), Muse Spark 1.3 vision (photo + question ->
// text) and SAM 3.1 (photo + noun phrase -> boxes + masks). All three sit behind `MultimodalGate`, which applies the same
// privacy contract as text escalation in `Assistant`: the trained sensitivity Reflex decision runs first, photos are
// stripped of EXIF/GPS, the accompanying text is masked by `PrivacyScrubber`, only Standard-mode model ids are used, and
// every request reports exactly what left the phone (`CloudPayloadSummary`).
//
// Endpoints verified live on 2026-11-04 (eval/meta_api/*.json) against dev.meta.ai/docs:
//   POST /v1/asr/transcribe      multipart {request: JSON, audio: WAV 16/24 kHz mono PCM}   muse-voice-transcribe-1.0
//   POST /v1/chat/completions    user content [text, image_url{url: data:image/jpeg;base64,...}] muse-spark-1.3
//   POST /v1/responses           input_text noun phrase + input_image data URL, metadata.mask_encoding=one_bit  sam-3.1
// Not supported (probed, 404): /v1/audio/transcriptions, and sam-3.1 on /v1/chat/completions ("Use /v1/responses").

public typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, Int)

public enum MetaAPI {
    public static let baseURL = URL(string: "https://api.meta.ai/v1/")!
    public static let voiceModel = "muse-voice-transcribe-1.0"
    public static let visionModel = "muse-spark-1.3"          // Standard mode: content is not used to train Meta models
    public static let segmentModel = "sam-3.1"
    public static let transcribePath = "asr/transcribe"
    public static let chatPath = "chat/completions"
    public static let responsesPath = "responses"
    /// Pay-as-you-go list prices (dev.meta.ai/docs/pricing-rate-limits, read 2026-11-04), for the on-phone cost line.
    public static let sparkInputPerToken = 1.25 / 1_000_000, sparkOutputPerToken = 4.25 / 1_000_000
    public static let voicePerHour = 0.18, samPerImage = 2.50 / 1000

    public static let defaultTransport: HTTPTransport = { req in
        let (d, r) = try await URLSession.shared.data(for: req)
        return (d, (r as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Contributor-mode ids (`*-contributor`) let Meta train on the content. Pocket Glimmer never sends user media there.
    public static func requireStandardMode(_ model: String) throws {
        if model.lowercased().contains("contributor") { throw MultimodalError.contributorModeRefused(model) }
    }
}

public enum MultimodalError: Error, Equatable {
    case notConfigured
    case unsupportedAudio(String)
    case contributorModeRefused(String)
    case malformedJPEG
    case emptyAnswer
    case http(Int, String)
    case decode(String)
    case badMask(String)
}

/// Exactly what one request sent off the phone. Rendered verbatim in the privacy sheet.
public struct CloudPayloadSummary: Sendable, Equatable, Codable {
    public var endpoint: String          // full URL
    public var model: String
    public var bytesSent: Int            // whole HTTP body
    public var mediaKind: String         // "audio/wav", "image/jpeg"
    public var mediaBytes: Int           // the audio/image part alone, after stripping
    public var textSent: String          // masked text that accompanied the media ("" for voice)
    public var strippedMetadata: [String] = []   // e.g. ["APP1/Exif", "APP2/ICC"]
    public var line: String {
        let kb = String(format: "%.1f KB", Double(bytesSent) / 1024)
        let stripped = strippedMetadata.isEmpty ? "" : " · removed " + strippedMetadata.joined(separator: ", ")
        return "\(kb) to \(model) (\(endpoint.replacingOccurrences(of: "https://", with: "")))\(stripped)"
    }
}

public struct TokenUsage: Sendable, Equatable {
    public var promptTokens = 0, completionTokens = 0, reasoningTokens = 0, imagesProcessed = 0, audioMs = 0
    public var estimatedUSD: Double {
        Double(promptTokens) * MetaAPI.sparkInputPerToken + Double(completionTokens) * MetaAPI.sparkOutputPerToken
            + Double(imagesProcessed) * MetaAPI.samPerImage + Double(audioMs / 1000) / 3600 * MetaAPI.voicePerHour
    }
}

// MARK: - Muse Voice Transcribe

public struct Transcript: Sendable, Equatable {
    public var text: String
    public var language: String?     // the language bias sent (the API does not echo a detected language)
    public var durationMs: Int
    public var model: String
    public var sessionId: String? = nil
}

/// Muse Voice Transcribe's file endpoint takes RIFF/WAVE mono 16-bit PCM at 16 or 24 kHz. AVAudioRecorder writes valid
/// WAVs with extra chunks (FLLR padding, LIST); this rewrites them as the canonical 44-byte-header form and validates
/// the format on device, so a bad recording fails here instead of as an HTTP 400 after the audio already left.
public enum WAVFile {
    public struct Info: Sendable, Equatable { public let sampleRate: Int, channels: Int, bitsPerSample: Int, durationMs: Int }

    static func le32(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24 }
    static func le16(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }

    public static func make(pcm: Data, sampleRate: Int = 16_000, channels: Int = 1, bitsPerSample: Int = 16) -> Data {
        func u32(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24 & 0xFF)] }
        func u16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
        let block = channels * bitsPerSample / 8
        var h = Array("RIFF".utf8) + u32(36 + pcm.count) + Array("WAVEfmt ".utf8) + u32(16) + u16(1) + u16(channels)
        h += u32(sampleRate) + u32(sampleRate * block) + u16(block) + u16(bitsPerSample) + Array("data".utf8) + u32(pcm.count)
        return Data(h) + pcm
    }

    public static func canonical(_ d: Data) -> (data: Data, info: Info)? {
        let b = [UInt8](d)
        guard b.count >= 12, b[0..<4].elementsEqual("RIFF".utf8), b[8..<12].elementsEqual("WAVE".utf8) else { return nil }
        var i = 12
        var fmt: (format: Int, ch: Int, rate: Int, bits: Int)?
        var pcm: ArraySlice<UInt8>?
        while i + 8 <= b.count {
            let id = String(decoding: b[i..<(i + 4)], as: UTF8.self), size = le32(b, i + 4), start = i + 8
            if id == "fmt ", size >= 16, start + 16 <= b.count {
                fmt = (le16(b, start), le16(b, start + 2), le32(b, start + 4), le16(b, start + 14))
            } else if id == "data" {
                pcm = b[start..<min(b.count, start + size)]     // streaming writers may leave size unset: clamp
                break
            }
            i = start + size + (size & 1)
        }
        guard let f = fmt, let pcm, f.format == 1 || f.format == 0xFFFE, f.ch > 0, f.rate > 0, f.bits > 0 else { return nil }
        let info = Info(sampleRate: f.rate, channels: f.ch, bitsPerSample: f.bits,
                        durationMs: pcm.count * 1000 / max(1, f.rate * f.ch * f.bits / 8))
        return (make(pcm: Data(pcm), sampleRate: f.rate, channels: f.ch, bitsPerSample: f.bits), info)
    }

    /// What `/v1/asr/transcribe` accepts (dev.meta.ai/docs/api-reference/voice/schemas, TranscribeRequest.audioEncoding).
    public static func isAccepted(_ i: Info) -> Bool { [16_000, 24_000].contains(i.sampleRate) && i.channels == 1 && i.bitsPerSample == 16 }
}

public struct MetaVoiceTranscriber: Sendable {
    public let model: String
    public let baseURL: URL
    let apiKey: String
    public var transport: HTTPTransport = MetaAPI.defaultTransport

    public init(apiKey: String, model: String = MetaAPI.voiceModel, baseURL: URL = MetaAPI.baseURL) {
        self.apiKey = apiKey; self.model = model; self.baseURL = baseURL
    }

    public var endpoint: URL { baseURL.appendingPathComponent(MetaAPI.transcribePath) }

    /// The file endpoint takes `audioEncoding: "WAV"` only: RIFF/WAVE, mono integer PCM, 16 or 24 kHz.
    public static func isWAV(_ d: Data) -> Bool {
        d.count > 12 && d.prefix(4).elementsEqual("RIFF".utf8) && d.dropFirst(8).prefix(4).elementsEqual("WAVE".utf8)
    }

    public func makeRequest(audio: Data, mimeType: String = "audio/wav", language: String? = "English",
                            keywords: [String] = [], boundary: String = "pg-" + UUID().uuidString) throws -> URLRequest {
        try MetaAPI.requireStandardMode(model)
        guard mimeType.lowercased().contains("wav"), Self.isWAV(audio) else { throw MultimodalError.unsupportedAudio(mimeType) }
        var settings: [String: Any] = ["model": model, "audioEncoding": "WAV", "mode": "PUSH_TO_TALK"]
        if let language { settings["languageBias"] = [language] }
        if !keywords.isEmpty { settings["keywords"] = keywords }
        let json = try JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys])
        var body = Data()
        func part(_ name: String, filename: String?, type: String, _ payload: Data) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"".utf8))
            if let filename { body.append(Data("; filename=\"\(filename)\"".utf8)) }
            body.append(Data("\r\nContent-Type: \(type)\r\n\r\n".utf8)); body.append(payload); body.append(Data("\r\n".utf8))
        }
        part("request", filename: nil, type: "application/json", json)
        part("audio", filename: "clip.wav", type: "audio/wav", audio)
        body.append(Data("--\(boundary)--\r\n".utf8))
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 60
        return req
    }

    public func transcribe(audio raw: Data, mimeType: String = "audio/wav", language: String? = "English",
                           keywords: [String] = []) async throws -> (Transcript, CloudPayloadSummary) {
        guard let (audio, info) = WAVFile.canonical(raw), WAVFile.isAccepted(info) else { throw MultimodalError.unsupportedAudio(mimeType) }
        let req = try makeRequest(audio: audio, mimeType: mimeType, language: language, keywords: keywords)
        let (data, status) = try await transport(req)
        guard (200..<300).contains(status) else { throw MultimodalError.http(status, String(decoding: data.prefix(300), as: UTF8.self)) }
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let text = j["transcript"] as? String else {
            throw MultimodalError.decode(String(decoding: data.prefix(300), as: UTF8.self))
        }
        let t = Transcript(text: text.trimmingCharacters(in: .whitespacesAndNewlines), language: language,
                           durationMs: (j["audioDurationMs"] as? NSNumber)?.intValue ?? 0, model: model, sessionId: j["sessionId"] as? String)
        let s = CloudPayloadSummary(endpoint: endpoint.absoluteString, model: model, bytesSent: req.httpBody?.count ?? 0,
                                    mediaKind: "audio/wav", mediaBytes: audio.count, textSent: "")
        return (t, s)
    }
}

// MARK: - Muse Spark vision + SAM 3.1

public struct VisionAnswer: Sendable, Equatable {
    public var text: String
    public var model: String
    public var usage: TokenUsage
}

public struct SegmentBox: Sendable, Equatable, Codable {
    public var x1: Int, y1: Int, x2: Int, y2: Int     // source pixels, inclusive corners
    public var imageWidth: Int, imageHeight: Int
    public var width: Int { x2 - x1 + 1 }
    public var height: Int { y2 - y1 + 1 }
    /// 0...1 fractions of the image, for drawing over any display size.
    public var normalized: (x: Double, y: Double, w: Double, h: Double) {
        guard imageWidth > 0, imageHeight > 0 else { return (0, 0, 0, 0) }
        return (Double(x1) / Double(imageWidth), Double(y1) / Double(imageHeight),
                Double(width) / Double(imageWidth), Double(height) / Double(imageHeight))
    }
}

/// SAM 3.1 mask: an H x W raster aligned to the box's top-left corner. `one_bit` ("!") decodes on device
/// (`raster()`); `lossless` ("~") is kept as the raw payload (we always request one_bit).
public struct SegmentMask: Sendable, Equatable, Codable {
    public var height: Int, width: Int
    public var encoding: String          // "one_bit" | "lossless"
    public var payload: String           // includes the leading marker character
    public func raster() throws -> [UInt8] {
        guard encoding == "one_bit" else { throw MultimodalError.badMask("only one_bit masks decode on device") }
        return try SAMMaskCodec.decodeOneBit(payload, width: width, height: height)
    }
}

public struct Segment: Sendable, Equatable, Codable, Identifiable {
    public var id: Int                   // SAM object id (stable within a response, not dense)
    public var label: String             // the concept prompt
    public var box: SegmentBox
    public var confidence: Double?
    public var mask: SegmentMask?
}

public struct Segmentation: Sendable, Equatable {
    public var segments: [Segment]
    public var raw: String
    public var usage: TokenUsage
}

public struct MetaVision: Sendable {
    let apiKey: String
    public let baseURL: URL
    public var visionModel: String
    public var segmentModel: String
    public var transport: HTTPTransport = MetaAPI.defaultTransport
    /// Spark is a reasoning model; reasoning tokens count against max_tokens. "low" keeps photo Q&A fast and cheap.
    public var reasoningEffort = "low"

    public init(apiKey: String, visionModel: String = MetaAPI.visionModel, segmentModel: String = MetaAPI.segmentModel,
                baseURL: URL = MetaAPI.baseURL) {
        self.apiKey = apiKey; self.visionModel = visionModel; self.segmentModel = segmentModel; self.baseURL = baseURL
    }

    static let systemPrompt = "You are the vision brain of a private phone assistant. Placeholders like [PERSON_1] stand for private data; keep them verbatim. Answer in at most three short sentences."

    func post(_ path: String, json: [String: Any]) throws -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // No "\/" escaping: base64 is ~1/64 slashes, and bytes are what the privacy line reports.
        req.httpBody = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes])
        req.timeoutInterval = 60
        return req
    }

    static func dataURL(_ jpeg: Data) -> String { "data:image/jpeg;base64," + jpeg.base64EncodedString() }

    public func makeDescribeRequest(imageJPEG: Data, question: String, maxTokens: Int = 700) throws -> URLRequest {
        try MetaAPI.requireStandardMode(visionModel)
        return try post(MetaAPI.chatPath, json: [
            "model": visionModel, "max_tokens": maxTokens, "reasoning_effort": reasoningEffort,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": [
                    ["type": "text", "text": question],
                    ["type": "image_url", "image_url": ["url": Self.dataURL(imageJPEG)]]]]]])
    }

    public func describe(imageJPEG: Data, question: String, maxTokens: Int = 700) async throws -> (VisionAnswer, CloudPayloadSummary) {
        let req = try makeDescribeRequest(imageJPEG: imageJPEG, question: question, maxTokens: maxTokens)
        let (data, status) = try await transport(req)
        guard (200..<300).contains(status) else { throw MultimodalError.http(status, String(decoding: data.prefix(300), as: UTF8.self)) }
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (j["choices"] as? [[String: Any]])?.first, let msg = choice["message"] as? [String: Any] else {
            throw MultimodalError.decode(String(decoding: data.prefix(300), as: UTF8.self))
        }
        let u = j["usage"] as? [String: Any] ?? [:]
        var usage = TokenUsage()
        usage.promptTokens = (u["prompt_tokens"] as? NSNumber)?.intValue ?? 0
        usage.completionTokens = (u["completion_tokens"] as? NSNumber)?.intValue ?? 0
        usage.reasoningTokens = ((u["completion_tokens_details"] as? [String: Any])?["reasoning_tokens"] as? NSNumber)?.intValue ?? 0
        // content is null when the whole budget went to reasoning (seen live at max_tokens=120).
        guard let text = (msg["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { throw MultimodalError.emptyAnswer }
        let s = CloudPayloadSummary(endpoint: req.url!.absoluteString, model: visionModel, bytesSent: req.httpBody?.count ?? 0,
                                    mediaKind: "image/jpeg", mediaBytes: imageJPEG.count, textSent: question)
        return (VisionAnswer(text: text, model: visionModel, usage: usage), s)
    }

    /// SAM 3.1 takes one short noun phrase per request ("sticky note", not "find the sticky notes").
    public func makeSegmentRequest(imageJPEG: Data, prompt: String) throws -> URLRequest {
        try MetaAPI.requireStandardMode(segmentModel)
        return try post(MetaAPI.responsesPath, json: [
            "model": segmentModel, "stream": false,
            "metadata": ["mask_encoding": "one_bit", "include_confidence": "true"],
            "input": [["type": "message", "role": "user", "content": [
                ["type": "input_text", "text": prompt],
                ["type": "input_image", "image_url": Self.dataURL(imageJPEG)]]]]])
    }

    public func segment(imageJPEG: Data, prompt: String) async throws -> (Segmentation, CloudPayloadSummary) {
        let req = try makeSegmentRequest(imageJPEG: imageJPEG, prompt: prompt)
        let (data, status) = try await transport(req)
        guard (200..<300).contains(status) else { throw MultimodalError.http(status, String(decoding: data.prefix(300), as: UTF8.self)) }
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MultimodalError.decode(String(decoding: data.prefix(300), as: UTF8.self))
        }
        var text = j["output_text"] as? String ?? ""
        if text.isEmpty {
            for item in j["output"] as? [[String: Any]] ?? [] {
                for c in item["content"] as? [[String: Any]] ?? [] where (c["type"] as? String) == "output_text" { text += c["text"] as? String ?? "" }
            }
        }
        var usage = TokenUsage()
        usage.imagesProcessed = ((j["usage"] as? [String: Any])?["images_processed"] as? NSNumber)?.intValue ?? 1
        let s = CloudPayloadSummary(endpoint: req.url!.absoluteString, model: segmentModel, bytesSent: req.httpBody?.count ?? 0,
                                    mediaKind: "image/jpeg", mediaBytes: imageJPEG.count, textSent: prompt)
        // Zero matches is a valid, empty result.
        return (Segmentation(segments: SAMOutputParser.parse(text, label: prompt), raw: text, usage: usage), s)
    }
}

/// Parses SAM 3.1's special-token text (dev.meta.ai/docs/sam/reading-segmentation):
/// `<0f>ID<|box;x1=..;y1=..;x2=..;y2=..;w=..;h=..[;c=..]|><|mask;x=0;y=0[;c=..];data=H,W,<enc>payload|>,ID...`
/// Fields are read by key, so the parser is indifferent to whether `c` is present. Images are frame 0 only.
public enum SAMOutputParser {
    static let record = try! NSRegularExpression(pattern: #"(\d+)<\|box;([^|]*)\|><\|mask;([^|]*)\|>"#)

    static func fields(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for kv in s.split(separator: ";") {
            guard let eq = kv.firstIndex(of: "=") else { continue }
            out[String(kv[..<eq])] = String(kv[kv.index(after: eq)...])
        }
        return out
    }

    public static func parse(_ text: String, label: String) -> [Segment] {
        // Keep only the first frame's line for still images.
        let line = text.split(separator: "\n").first.map(String.init) ?? ""
        var out: [Segment] = []
        for m in record.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
            guard let rId = Range(m.range(at: 1), in: line), let rBox = Range(m.range(at: 2), in: line),
                  let rMask = Range(m.range(at: 3), in: line), let id = Int(line[rId]) else { continue }
            let b = fields(String(line[rBox]))
            guard let x1 = b["x1"].flatMap(Int.init), let y1 = b["y1"].flatMap(Int.init), let x2 = b["x2"].flatMap(Int.init),
                  let y2 = b["y2"].flatMap(Int.init), let w = b["w"].flatMap(Int.init), let h = b["h"].flatMap(Int.init) else { continue }
            // The mask payload may itself contain ',' after the marker, so split data into at most 3 parts.
            let mk = fields(String(line[rMask]))
            var mask: SegmentMask?
            if let data = mk["data"] {
                let parts = data.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
                if parts.count == 3, let mh = Int(parts[0]), let mw = Int(parts[1]), let marker = parts[2].first {
                    mask = SegmentMask(height: mh, width: mw, encoding: marker == "!" ? "one_bit" : "lossless", payload: String(parts[2]))
                }
            }
            out.append(Segment(id: id, label: label, box: SegmentBox(x1: x1, y1: y1, x2: x2, y2: y2, imageWidth: w, imageHeight: h),
                               confidence: b["c"].flatMap(Double.init), mask: mask))
        }
        return out
    }
}

/// On-device decoder for SAM 3.1 `one_bit` masks: base85 (custom alphabet) -> 32-bit range coder with a 12-pixel
/// binary context model. Ported from Meta's MIT-licensed `meta-sam-parser` 0.1.0 (`_mask_codec.py`), so the overlay is
/// drawn from the real mask, not just the box.
public enum SAMMaskCodec {
    static let alphabet: [UInt8] = (0x21..<0x7F).map { UInt8($0) }.filter { !"\"\\,;<>|".utf8.contains($0) }
    static let values: [Int] = {
        var v = [Int](repeating: -1, count: 128)
        for (i, c) in alphabet.enumerated() { v[Int(c)] = i }
        return v
    }()
    static let radix = 85, prefixLength = 5
    static let m32: UInt64 = 0xFFFF_FFFF, top: UInt64 = 1 << 24, bottom: UInt64 = 1 << 16

    static func digit(_ c: UInt8) throws -> UInt64 {
        let v = c < 128 ? values[Int(c)] : -1
        guard v >= 0, v < radix else { throw MultimodalError.badMask("invalid character") }
        return UInt64(v)
    }

    static func unpack(_ s: [UInt8]) throws -> [UInt8] {
        guard s.count >= prefixLength else { throw MultimodalError.badMask("missing length prefix") }
        var length = 0
        for c in s[0..<prefixLength] { length = length * radix + Int(try digit(c)) }
        let rem = length % 4
        guard s.count == prefixLength + (length / 4) * 5 + (rem == 0 ? 0 : rem + 1) else { throw MultimodalError.badMask("length mismatch") }
        var out = [UInt8](repeating: 0, count: length)
        var src = prefixLength, dst = 0
        while dst < length - rem {
            var v: UInt64 = 0
            for i in 0..<5 { v = v * UInt64(radix) + (try digit(s[src + i])) }
            guard v <= m32 else { throw MultimodalError.badMask("group out of range") }
            out[dst] = UInt8((v >> 24) & 0xFF); out[dst + 1] = UInt8((v >> 16) & 0xFF)
            out[dst + 2] = UInt8((v >> 8) & 0xFF); out[dst + 3] = UInt8(v & 0xFF)
            src += 5; dst += 4
        }
        if rem > 0 {
            var v: UInt64 = 0
            for i in 0..<5 { v = v * UInt64(radix) + (i < rem + 1 ? try digit(s[src + i]) : UInt64(radix - 1)) }
            guard v <= m32 else { throw MultimodalError.badMask("tail out of range") }
            for i in 0..<rem { out[dst + i] = UInt8((v >> UInt64(24 - i * 8)) & 0xFF) }
        }
        return out
    }

    struct RangeDecoder {
        let input: [UInt8]; var pos = 0
        var low: UInt64 = 0, range: UInt64 = 0xFFFF_FFFF, code: UInt64 = 0, scaled: UInt64 = 0
        init(_ input: [UInt8]) throws {
            guard input.count >= 4 else { throw MultimodalError.badMask("missing finalization") }
            self.input = input
            for _ in 0..<4 { code = ((code << 8) | UInt64(try read())) & SAMMaskCodec.m32 }
        }
        mutating func read() throws -> UInt8 {
            guard pos < input.count else { throw MultimodalError.badMask("payload ended early") }
            defer { pos += 1 }
            return input[pos]
        }
        mutating func frequency(_ total: UInt64) throws -> UInt64 {
            scaled = range / total
            guard scaled > 0 else { throw MultimodalError.badMask("invalid coding state") }
            let v = ((code &- low) & SAMMaskCodec.m32) / scaled
            return v >= total ? total - 1 : v
        }
        mutating func decode(_ cum: UInt64, _ freq: UInt64) throws {
            low = (low + scaled * cum) & SAMMaskCodec.m32
            range = scaled * freq
            while true {
                if (low ^ ((low + range) & SAMMaskCodec.m32)) & SAMMaskCodec.m32 < SAMMaskCodec.top {
                } else if range < SAMMaskCodec.bottom {
                    range = ((SAMMaskCodec.m32 + 1 - low) & SAMMaskCodec.m32) & (SAMMaskCodec.bottom - 1)
                } else { break }
                code = ((code << 8) | UInt64(try read())) & SAMMaskCodec.m32
                low = (low << 8) & SAMMaskCodec.m32
                range = (range << 8) & SAMMaskCodec.m32
            }
        }
    }

    /// Row-major H*W raster of 0/1. `payload` includes the leading "!" marker.
    public static func decodeOneBit(_ payload: String, width: Int, height: Int) throws -> [UInt8] {
        guard payload.first == "!", width > 0, height > 0, width * height <= 16_000_000 else { throw MultimodalError.badMask("not a one_bit mask") }
        var dec = try RangeDecoder(try unpack(Array(payload.utf8.dropFirst())))
        var counts = [UInt16](repeating: 1, count: (1 << 12) * 2)
        let pad = 2, pw = width + 2 * pad
        var p = [UInt8](repeating: 0, count: pw * (height + pad))
        var out = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = (y + pad) * pw + pad
            for x in 0..<width {
                let pos = row + x, pr = pos - pw, er = pos - 2 * pw
                var ctx = Int(p[pos - 1]) | Int(p[pos - 2]) << 1 | Int(p[pr - 2]) << 2 | Int(p[pr - 1]) << 3
                ctx |= Int(p[pr]) << 4 | Int(p[pr + 1]) << 5 | Int(p[pr + 2]) << 6
                ctx |= Int(p[er - 2]) << 7 | Int(p[er - 1]) << 8 | Int(p[er]) << 9 | Int(p[er + 1]) << 10 | Int(p[er + 2]) << 11
                let off = ctx << 1
                let zero = UInt64(counts[off]), one = UInt64(counts[off + 1])
                let v = try dec.frequency(zero + one)
                let bit = v < zero ? 0 : 1
                if bit == 0 { try dec.decode(0, zero) } else { try dec.decode(zero, one) }
                p[pos] = UInt8(bit); out[y * width + x] = UInt8(bit)
                counts[off + bit] = counts[off + bit] &+ 14
                if Int(counts[off]) + Int(counts[off + 1]) >= 4096 {
                    counts[off] = max(counts[off] >> 1, 1); counts[off + 1] = max(counts[off + 1] >> 1, 1)
                }
            }
        }
        return out
    }
}

// MARK: - EXIF / GPS stripping

/// Pure-Swift JPEG marker walker. Drops APP1 (Exif incl. GPS, and XMP), APP2 (ICC / MPF), APP13 (IPTC) and COM
/// segments; keeps SOI, APP0/JFIF, DQT, SOF, DHT, DRI, SOS + entropy-coded data, EOI. Returns nil on anything it cannot
/// parse, and the gate then refuses to send (fail closed). Orientation lives in EXIF, so the app bakes rotation into
/// pixels (UIGraphicsImageRenderer) before stripping.
public enum JPEGMetadataStripper {
    public struct Result: Sendable, Equatable { public let data: Data; public let removed: [String] }

    static func name(_ marker: UInt8, _ seg: ArraySlice<UInt8>) -> String? {
        let body = seg.dropFirst(4)
        switch marker {
        case 0xE1:
            if body.starts(with: Array("Exif".utf8)) { return "APP1/Exif" }
            if body.starts(with: Array("http://ns.adobe.com/xap".utf8)) { return "APP1/XMP" }
            return "APP1"
        case 0xE2: return body.starts(with: Array("ICC_PROFILE".utf8)) ? "APP2/ICC" : "APP2"
        case 0xED: return "APP13/IPTC"
        case 0xFE: return "COM"
        default: return nil
        }
    }

    public static func strip(_ jpeg: Data) -> Result? {
        let b = [UInt8](jpeg)
        guard b.count >= 4, b[0] == 0xFF, b[1] == 0xD8 else { return nil }
        var out: [UInt8] = [0xFF, 0xD8]
        var removed: [String] = []
        var i = 2
        while i < b.count {
            guard b[i] == 0xFF else { return nil }
            var j = i
            while j < b.count && b[j] == 0xFF { j += 1 }            // fill bytes
            guard j < b.count else { return nil }
            let m = b[j]
            if m == 0xD9 { out += [0xFF, 0xD9]; return Result(data: Data(out), removed: removed) }
            if (0xD0...0xD7).contains(m) || m == 0x01 { out += [0xFF, m]; i = j + 1; continue }
            guard j + 2 < b.count else { return nil }
            let len = Int(b[j + 1]) << 8 | Int(b[j + 2])
            guard len >= 2, j + 1 + len <= b.count else { return nil }
            let seg = b[(j - 1)..<(j + 1 + len)]                   // FF m len payload
            if m == 0xDA {                                          // SOS: header + entropy-coded data to the end
                out += [0xFF]; out += b[j..<b.count]
                guard out.count >= 2, out[out.count - 2] == 0xFF, out[out.count - 1] == 0xD9 else { return nil }
                return Result(data: Data(out), removed: removed)
            }
            if let n = name(m, seg) { removed.append(n) } else { out += [0xFF]; out += b[j..<(j + 1 + len)] }
            i = j + 1 + len
        }
        return nil
    }
}

// MARK: - The gate

/// Photos carry more than the words that come with them, so a stricter lexical floor applies on top of the trained
/// sensitivity decision: documents with money, identity or health data never leave the phone.
public enum PhotoSensitivityHint {
    static let re = try! NSRegularExpression(pattern: #"\b(receipts?|invoices?|bills?|bank|statements?|cheques?|credit|debit|visa|mastercard|amex|card ?number|pay ?stubs?|payslips?|tax|w-?2|passports?|driver'?s licen[cs]e|id card|social security|ssn|prescriptions?|pill bottles?|lab report|medical|x-?rays?|insurance|password|pin|naked|nude)\b"#, options: [.caseInsensitive])
    static let card = try! NSRegularExpression(pattern: #"(?:\b(?:\d[ -]?){13,16}\b)|(?:\*{2,}\s?\d{4})|(?:\bx{4}\s?\d{4})"#, options: [.caseInsensitive])
    /// `text` is the user's request plus any words read off the photo by on-device OCR (never sent).
    public static func matches(_ text: String) -> Bool {
        let r = NSRange(text.startIndex..., in: text)
        return SensitivityHint.matches(text) || re.firstMatch(in: text, range: r) != nil || card.firstMatch(in: text, range: r) != nil
    }
}

public struct GlimpseResult: Sendable {
    public enum Outcome: Sendable, Equatable {
        case answered(String)
        case segmented([Segment], answer: String?)
        case keptOnDevice(reason: String)
        case offline(String)
    }
    public var outcome: Outcome
    /// The sensitivity decision (always present: it runs online and offline, like text escalation).
    public var decisions: [ReflexDecision] = []
    /// One entry per request that left the phone (empty when kept on device or offline).
    public var cloudPayloads: [CloudPayloadSummary] = []
    public var usage = TokenUsage()
    public var provider: String? = nil
    public var cloudPayloadSummary: CloudPayloadSummary? { cloudPayloads.first }
    public var keptOnDevice: Bool { if case .keptOnDevice = outcome { return true }; return false }
}

public struct VoiceTurn: Sendable {
    public var transcript: Transcript
    public var turn: AssistantTurn
    public var cloudPayloadSummary: CloudPayloadSummary
}

/// The ONLY multimodal entry point the app uses. Built from the live `Assistant`, so it shares its Reflex (and
/// telemetry), scrubber, memory names and online flag: one decision path for typed, spoken and photographed requests.
public final class MultimodalGate: @unchecked Sendable {
    public enum ImageTask: Sendable, Equatable {
        case describe(question: String)
        case segment(concept: String)
        /// Spark answers, then SAM 3.1 segments. With `concept == nil`, Spark names the concept itself.
        case describeAndSegment(question: String, concept: String?)
    }

    public let assistant: Assistant
    public var transcriber: MetaVoiceTranscriber?
    public var vision: MetaVision?
    /// User setting: never send photos, even when the sensitivity decision says "ok".
    public var photosStayOnDevice = false
    /// User setting: never send audio (voice input then needs typing).
    public var voiceStaysOnDevice = false
    public static let offlineMessage = "Voice and camera understanding need the cloud; nothing was sent."

    public init(assistant: Assistant, transcriber: MetaVoiceTranscriber? = nil, vision: MetaVision? = nil) {
        self.assistant = assistant; self.transcriber = transcriber; self.vision = vision
    }

    /// Convenience: both clients from one Meta Model API key (Standard-mode ids only).
    public convenience init(assistant: Assistant, metaAPIKey: String?) {
        self.init(assistant: assistant, transcriber: metaAPIKey.map { MetaVoiceTranscriber(apiKey: $0) },
                  vision: metaAPIKey.map { MetaVision(apiKey: $0) })
    }

    /// The text the sensitivity Reflex decision sees. `photoText` is on-device OCR of the photo (Vision framework on
    /// iOS); it is used only for this local decision and is never sent.
    public static func sensitivityContext(_ intent: String, photoText: String? = nil) -> String {
        let t = (photoText ?? "").split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "User: \(intent) [photo attached]" : "User: \(intent) [photo attached; text in photo: \(String(t.prefix(240)))]"
    }

    func scrubber() -> PrivacyScrubber {
        var sc = assistant.scrubber
        sc.knownNames = Array(Set(sc.knownNames + ((try? assistant.memory.entityNames()) ?? [])))
        return sc
    }

    /// SAM 3.1 matches concrete attributes: live, "sticky note" returned 0 matches on our whiteboard fixture while
    /// "yellow sticky note" returned all 5 (eval/meta_api/run1 vs sam_segment.json). So Spark names color + noun.
    static let conceptInstruction = "\nAfter your answer, on a new last line, write CONCEPT: followed by a 2-3 word noun phrase naming the main repeated object in the photo, starting with its color (for example: yellow sticky note)."

    static func splitConcept(_ text: String) -> (answer: String, concept: String?) {
        var lines = text.components(separatedBy: "\n")
        guard let idx = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("CONCEPT:") }) else { return (text, nil) }
        let raw = lines[idx].trimmingCharacters(in: .whitespaces).dropFirst("CONCEPT:".count)
        let concept = raw.trimmingCharacters(in: CharacterSet(charactersIn: " .\"'*")).lowercased()
        lines.remove(at: idx)
        return (lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), concept.isEmpty ? nil : String(concept.prefix(40)))
    }

    /// Photo path: sensitivity Reflex -> user toggle -> online check -> EXIF/GPS strip -> masked text -> Spark / SAM 3.1.
    public func glimpse(imageJPEG: Data, intent: String, task: ImageTask, photoText: String? = nil) async throws -> GlimpseResult {
        let sens = try await assistant.reflex.decide(OptionSets.sensitivity, context: Self.sensitivityContext(intent, photoText: photoText))
        var r = GlimpseResult(outcome: .offline(Self.offlineMessage), decisions: [sens])
        if photosStayOnDevice { r.outcome = .keptOnDevice(reason: "Photos stay on this iPhone (Settings). Nothing was sent."); return r }
        if sens.chosen.id == "sensitive" {
            r.outcome = .keptOnDevice(reason: "Looks sensitive (\(Int((sens.probabilities["sensitive"] ?? 0) * 100))% sure). The photo stayed on this iPhone."); return r
        }
        if PhotoSensitivityHint.matches(intent + "\n" + (photoText ?? "")) {
            r.outcome = .keptOnDevice(reason: "Photos of money, ID or health documents stay on this iPhone. Nothing was sent."); return r
        }
        guard assistant.isOnline(), let vision else { return r }
        guard let stripped = JPEGMetadataStripper.strip(imageJPEG) else {
            r.outcome = .keptOnDevice(reason: "Couldn't verify the photo's location data was removed, so it stayed on this iPhone."); return r
        }
        let sc = scrubber()
        func record(_ s: CloudPayloadSummary) { var s = s; s.strippedMetadata = stripped.removed; r.cloudPayloads.append(s) }

        switch task {
        case .describe(let question):
            let q = sc.scrub(question)
            let (a, s) = try await vision.describe(imageJPEG: stripped.data, question: q.text)
            record(s); r.usage = a.usage; r.provider = "Meta Model API · \(a.model)"
            r.outcome = .answered(sc.restore(a.text, mapping: q.mapping))
        case .segment(let concept):
            let (seg, s) = try await vision.segment(imageJPEG: stripped.data, prompt: concept)
            record(s); r.usage = seg.usage; r.provider = "Meta Model API · \(vision.segmentModel)"
            r.outcome = .segmented(seg.segments, answer: nil)
        case .describeAndSegment(let question, let concept):
            let q = sc.scrub(question + (concept == nil ? Self.conceptInstruction : ""))
            let (a, s1) = try await vision.describe(imageJPEG: stripped.data, question: q.text)
            record(s1)
            let (answer, picked) = Self.splitConcept(a.text)
            var usage = a.usage
            var segments: [Segment] = []
            if let c = concept ?? picked {
                let (seg, s2) = try await vision.segment(imageJPEG: stripped.data, prompt: c)
                record(s2); segments = seg.segments; usage.imagesProcessed += seg.usage.imagesProcessed
            }
            r.usage = usage; r.provider = "Meta Model API · \(a.model) + \(vision.segmentModel)"
            r.outcome = .segmented(segments, answer: sc.restore(answer, mapping: q.mapping))
        }
        return r
    }

    /// Voice path: hold-to-talk audio -> Muse Voice Transcribe -> the transcript enters `Assistant.handle` exactly like
    /// typed text (same Reflex decisions, telemetry, sensitivity gate before any Spark call). The caller deletes the
    /// temporary audio file right after this returns unless the user opted in to keeping recordings.
    public func transcribe(audio: Data, mimeType: String = "audio/wav", language: String? = "English") async throws -> (Transcript, CloudPayloadSummary)? {
        guard !voiceStaysOnDevice, assistant.isOnline(), let transcriber else { return nil }
        // No keyword biasing with contact/memory names: that would send names the user did not say.
        return try await transcriber.transcribe(audio: audio, mimeType: mimeType, language: language)
    }

    public func transcriptIntoAssistant(_ t: Transcript) async throws -> AssistantTurn {
        try await assistant.handle(t.text)
    }

    /// Both steps; nil when offline / not configured / voice kept on device (the UI shows `offlineMessage`).
    public func voiceTurn(audio: Data, mimeType: String = "audio/wav", language: String? = "English") async throws -> VoiceTurn? {
        guard let res = try await transcribe(audio: audio, mimeType: mimeType, language: language), !res.0.text.isEmpty else { return nil }
        return VoiceTurn(transcript: res.0, turn: try await transcriptIntoAssistant(res.0), cloudPayloadSummary: res.1)
    }
}
