import Foundation

/// Replaces personal identifiers with placeholders before anything leaves the device, and restores them in the
/// cloud answer. Names come from Contacts + memory (passed in), patterns cover emails/phones/addresses/cards.
public struct PrivacyScrubber: Sendable {
    public var knownNames: [String]
    public init(knownNames: [String] = []) { self.knownNames = knownNames }

    public struct Result: Sendable { public let text: String; public let mapping: [String: String] } // placeholder -> original

    static let patterns: [(String, String)] = [
        ("EMAIL", #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#),
        ("CARD", #"\b(?:\d[ -]?){13,16}\b"#),
        ("PHONE", #"(?:\+?\d{1,2}[ .-]?)?\(?\d{3}\)?[ .-]?\d{3}[ .-]?\d{4}\b"#),
        ("ADDRESS", #"\b\d{1,5} [A-Z][a-z]+(?: [A-Z][a-z]+)* (?:St|Street|Ave|Avenue|Rd|Road|Blvd|Lane|Ln|Dr|Drive)\b\.?"#),
    ]

    public func scrub(_ input: String) -> Result {
        var text = input
        var map: [String: String] = [:]
        var counters: [String: Int] = [:]
        func replace(_ kind: String, _ re: NSRegularExpression) {
            while let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let r = Range(m.range, in: text) {
                let original = String(text[r])
                let existing = map.first { $0.value == original }?.key
                let ph: String
                if let existing { ph = existing } else {
                    counters[kind, default: 0] += 1
                    ph = "[\(kind)_\(counters[kind]!)]"
                    map[ph] = original
                }
                text.replaceSubrange(r, with: ph)
            }
        }
        for (k, p) in Self.patterns { replace(k, try! NSRegularExpression(pattern: p)) }
        for name in knownNames.sorted(by: { $0.count > $1.count }) where name.count > 1 && !Self.patterns.contains(where: { $0.0.caseInsensitiveCompare(name) == .orderedSame }) && name.caseInsensitiveCompare("PERSON") != .orderedSame {
            replace("PERSON", try! NSRegularExpression(pattern: "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b", options: .caseInsensitive))
        }
        return Result(text: text, mapping: map)
    }

    /// Placeholders are bracketed ("[PERSON_1]" is not a substring of "[PERSON_10]"), so replacement order cannot collide.
    public func restore(_ text: String, mapping: [String: String]) -> String {
        mapping.reduce(text) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
    }
}
