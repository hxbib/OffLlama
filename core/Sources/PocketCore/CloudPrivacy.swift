import Foundation

/// Why a cloud-bound text was not prepared. Every case is a fail-closed outcome: `Assistant` answers locally
/// and nothing is transmitted.
enum CloudWithholdReason: Sendable, Equatable {
    case emptyText
    case sensitive
    case uncertain
    case scanUnavailable
    case scanWindowTooLarge(byteCount: Int, limit: Int)
    case scanBudgetExceeded(windows: Int, limit: Int)
    case instructionTooLong(characters: Int, limit: Int)

    /// Short honest note for the local document fallback.
    var localNote: String {
        switch self {
        case .emptyText:
            return "there was no text to screen; nothing was sent"
        case .sensitive:
            return "a sensitive passage kept it on device; nothing was sent"
        case .uncertain:
            return "the privacy check was unsure; nothing was sent"
        case .scanUnavailable:
            return "the privacy check was unavailable; nothing was sent"
        case .scanWindowTooLarge, .scanBudgetExceeded:
            return "it was too large to screen completely; nothing was sent"
        case .instructionTooLong:
            return "the instruction was too long to screen; nothing was sent"
        }
    }
}

enum CloudTurnOutcome: Sendable {
    case prepared(PreparedCloudTurn)
    case withheld(CloudWithholdReason)
}

/// The only value `Assistant` can send to the cloud for text. The messages are private and there is no append
/// operation, so the scanned user text is exactly the transmitted user text.
struct PreparedCloudTurn: Sendable {
    let sentText: String
    private let messages: [ChatMessage]
    private let scrubber: PrivacyScrubber
    private let mapping: [String: String]

    fileprivate init(sentText: String, scrubber: PrivacyScrubber, mapping: [String: String]) {
        self.sentText = sentText
        self.scrubber = scrubber
        self.mapping = mapping
        self.messages = [
            ChatMessage(role: "system", content: CloudTurnComposer.systemPrompt),
            ChatMessage(role: "user", content: sentText)
        ]
    }

    func send(on chain: CloudBrainChain, maxTokens: Int = 800) async throws -> CloudAnswer {
        try Task.checkCancellation()
        return try await chain.complete(messages, maxTokens: maxTokens)
    }

    func restore(_ answer: String) -> String {
        scrubber.restore(answer, mapping: mapping)
    }
}

/// Assembles, masks and screens the complete cloud-bound user text before a turn may be sent.
///
/// Screening is a veto over the bytes that will leave the device, not a claim that the frozen sensitivity
/// decision detects every private fact. It calls the existing `OptionSets.sensitivity` decision unchanged.
enum CloudTurnComposer {
    static let systemPrompt = "You are the reasoning brain of a private phone assistant. Placeholders like [PERSON_1] stand for private data; keep them verbatim."
    static let maxUserTextCharacters = 24_000
    // Leave room for the frozen few-shot prompt and BOS within the 4,096-token context,
    // even when the tokenizer falls back to one token per UTF-8 byte.
    static let maxScanUTF8Bytes = 2_400
    static let scanOverlapCharacters = 300
    static let maxScanWindows = 48
    static let maxInstructionCharacters = 2_000

    static func prepareReply(
        profile: String,
        facts: [MemoryFact],
        utterance: String,
        scrubber: PrivacyScrubber,
        reflex: Reflex
    ) async throws -> CloudTurnOutcome {
        var raw = ""
        if !profile.isEmpty { raw += profile + "\n" }
        raw += MemoryDisclosure.cloud.render(facts)
        raw += utterance
        return try await prepare(raw: raw, scrubber: scrubber, reflex: reflex)
    }

    static func prepareDocument(
        instruction: String,
        text: String,
        scrubber: PrivacyScrubber,
        reflex: Reflex
    ) async throws -> CloudTurnOutcome {
        guard instruction.count <= maxInstructionCharacters else {
            return .withheld(.instructionTooLong(characters: instruction.count, limit: maxInstructionCharacters))
        }
        let raw: String
        if text.isEmpty {
            raw = instruction
        } else if instruction.isEmpty {
            raw = text
        } else {
            raw = instruction + "\n\n" + text
        }
        return try await prepare(raw: raw, scrubber: scrubber, reflex: reflex)
    }

    /// Throws only `CancellationError`. Policy/model failures are outcomes so a caller cannot fall through
    /// to an unscreened send.
    private static func prepare(raw: String, scrubber: PrivacyScrubber, reflex: Reflex) async throws -> CloudTurnOutcome {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .withheld(.emptyText)
        }

        // Mask first: the masked string is exactly what will be transmitted, and screening happens on that
        // string (including any truncation note, so nothing is added after a successful scan).
        let masked = scrubber.scrub(raw)
        var userText = masked.text
        if userText.count > maxUserTextCharacters {
            let cut = userText.index(userText.startIndex, offsetBy: maxUserTextCharacters)
            userText = String(userText[..<cut])
                + "\n\n[Truncated: only the first \(maxUserTextCharacters) characters are included.]"
        }

        let windows: [Range<String.Index>]
        switch TextWindows.cover(userText, maxUTF8Bytes: maxScanUTF8Bytes, overlap: scanOverlapCharacters) {
        case .failure(.characterTooLarge(let bytes)):
            return .withheld(.scanWindowTooLarge(byteCount: bytes, limit: maxScanUTF8Bytes))
        case .success(let planned):
            windows = planned
        }
        guard windows.count <= maxScanWindows else {
            return .withheld(.scanBudgetExceeded(windows: windows.count, limit: maxScanWindows))
        }
        guard !windows.isEmpty else { return .withheld(.emptyText) }

        for window in windows {
            try Task.checkCancellation()
            let decision: ReflexDecision
            do {
                decision = try await reflex.decide(
                    OptionSets.sensitivity,
                    context: "User: \(String(userText[window]))",
                    telemetryContext: nil
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return .withheld(.scanUnavailable)
            }
            if decision.chosen.id != "ok" || decision.escalated || !decision.confidence.isFinite
                || decision.confidence < decision.tau {
                return .withheld(decision.escalated ? .uncertain : .sensitive)
            }
        }
        try Task.checkCancellation()

        return .prepared(PreparedCloudTurn(sentText: userText, scrubber: scrubber, mapping: masked.mapping))
    }
}

/// Plans bounded, overlapping, grapheme-safe windows whose union covers every character at least once as a
/// contiguous span. The classifier still has to do detection; this type only guarantees coverage and context.
enum TextWindows {
    enum Failure: Error, Equatable {
        case characterTooLarge(byteCount: Int)
    }

    static func cover(_ text: String, maxUTF8Bytes: Int, overlap: Int)
        -> Result<[Range<String.Index>], Failure>
    {
        guard !text.isEmpty else { return .success([]) }
        var windows: [Range<String.Index>] = []
        var start = text.startIndex
        let end = text.endIndex

        while start < end {
            var cut = start
            var bytes = 0
            var characters = 0

            while cut < end {
                let next = text.index(after: cut)
                let charBytes = String(text[cut..<next]).utf8.count
                if characters > 0 && bytes + charBytes > maxUTF8Bytes { break }
                if characters == 0 && charBytes > maxUTF8Bytes {
                    return .failure(.characterTooLarge(byteCount: charBytes))
                }
                bytes += charBytes
                characters += 1
                cut = next
            }

            if cut < end, let boundary = naturalBoundary(text, from: start, before: cut, windowCharacters: characters) {
                cut = boundary
                characters = text.distance(from: start, to: cut)
            }

            windows.append(start..<cut)
            guard cut < end else { break }

            let back = min(max(overlap, 0), max(0, characters / 2))
            start = text.index(cut, offsetBy: -back)
        }
        return .success(windows)
    }

    /// Prefer a paragraph/sentence/whitespace break near the end of the byte-sized window, but keep at least
    /// 70% of it. If there is no break, the hard grapheme-boundary cut is used.
    private static func naturalBoundary(_ text: String, from start: String.Index,
                                        before cut: String.Index, windowCharacters: Int) -> String.Index? {
        let minKeep = max(1, windowCharacters * 7 / 10)
        var index = cut
        var removed = 0
        while index > start, removed < windowCharacters - minKeep {
            let previous = text.index(before: index)
            let character = text[previous]
            if character.isWhitespace || ".!?。！？;；".contains(character) {
                let after = text.index(after: previous)
                if after < cut { return after }
            }
            index = previous
            removed += 1
        }
        return nil
    }
}
