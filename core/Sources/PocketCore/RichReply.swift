import Foundation

/// One piece of an assistant reply: text to show as selectable prose, or markup to render in an isolated web view.
public enum ReplySegment: Equatable, Sendable {
    case prose(String)
    case markup(EmbeddedMarkup)
}

public struct EmbeddedMarkup: Equatable, Sendable {
    public enum Kind: String, Sendable { case html, svg }
    public let kind: Kind
    public let source: String
    public init(kind: Kind, source: String) { self.kind = kind; self.source = source }
}

/// Decides, explicitly, which parts of a reply are a document. Angle brackets alone never make markup:
/// a fenced block tagged `html` or `svg`, or a reply that is entirely one `<!doctype html>`/`<html>`/`<svg>` document.
/// Everything else, including unterminated fences and over-size blocks, stays prose and is shown as text.
public enum RichReply {
    public static let maxDocumentBytes = 120_000
    public static let maxDocuments = 4

    public static func segments(_ text: String) -> [ReplySegment] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if let whole = wholeReplyDocument(normalized) { return [.markup(whole)] }
        guard normalized.contains("```") || normalized.contains("~~~") else { return [.prose(text)] }

        var out: [ReplySegment] = []
        var pending: [Substring] = []
        var documents = 0
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        var i = 0
        func flush() {
            let joined = pending.joined(separator: "\n")
            pending.removeAll()
            out.append(contentsOf: prose(joined))
        }
        while i < lines.count {
            guard let opener = Fence(opening: lines[i]), let close = closingIndex(for: opener, in: lines, after: i) else {
                pending.append(lines[i]); i += 1; continue
            }
            let body = lines[(i + 1)..<close].joined(separator: "\n")
            if documents < maxDocuments, let markup = markup(infoWord: opener.infoWord, body: body) {
                flush()
                out.append(.markup(markup))
                documents += 1
            } else {
                pending.append(contentsOf: lines[i...close])
            }
            i = close + 1
        }
        flush()
        return out
    }

    public static func containsMarkup(_ text: String) -> Bool {
        segments(text).contains { if case .markup = $0 { return true } else { return false } }
    }

    /// Wraps markup in a fence long enough that no line of the content can close it early.
    public static func fenced(_ source: String, kind: EmbeddedMarkup.Kind = .html) -> String {
        var longest = 0, run = 0
        for ch in source { if ch == "`" { run += 1; longest = max(longest, run) } else { run = 0 } }
        let fence = String(repeating: "`", count: max(3, longest + 1))
        return "\(fence)\(kind.rawValue)\n\(source)\n\(fence)"
    }

    /// The content-security policy every rendered page carries in addition to the web view's own blocking:
    /// no network, images, fonts, frames, forms or base URL; inline style only.
    public static let contentSecurityPolicy =
        "default-src 'none'; style-src 'unsafe-inline'; form-action 'none'; base-uri 'none'; frame-ancestors 'none'"

    public static func page(for markup: EmbeddedMarkup) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>:root{color-scheme:light dark}html,body{margin:0}body{font:-apple-system-body;padding:12px;overflow-wrap:anywhere}svg{max-width:100%;height:auto}table{max-width:100%}</style>
        </head><body>
        \(markup.source)
        </body></html>
        """
    }

    // MARK: Internals

    private struct Fence {
        let marker: Character
        let length: Int
        let infoWord: String

        init?(opening line: Substring) {
            let indent = line.prefix { $0 == " " }.count
            guard indent <= 3 else { return nil }
            let rest = line.dropFirst(indent)
            guard let marker = rest.first, marker == "`" || marker == "~" else { return nil }
            let run = rest.prefix { $0 == marker }.count
            guard run >= 3 else { return nil }
            let info = rest.dropFirst(run).trimmingCharacters(in: .whitespaces)
            if marker == "`" && info.contains("`") { return nil }
            self.marker = marker; self.length = run
            self.infoWord = info.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map { String($0).lowercased() } ?? ""
        }

        func closes(_ line: Substring) -> Bool {
            let indent = line.prefix { $0 == " " }.count
            guard indent <= 3 else { return false }
            let rest = line.dropFirst(indent)
            let run = rest.prefix { $0 == marker }.count
            return run >= length && rest.dropFirst(run).allSatisfy { $0 == " " || $0 == "\t" }
        }
    }

    private static func closingIndex(for fence: Fence, in lines: [Substring], after open: Int) -> Int? {
        var j = open + 1
        while j < lines.count { if fence.closes(lines[j]) { return j }; j += 1 }
        return nil
    }

    private static func markup(infoWord: String, body: String) -> EmbeddedMarkup? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= maxDocumentBytes else { return nil }
        switch infoWord {
        case "html": return trimmed.contains("<") ? EmbeddedMarkup(kind: .html, source: trimmed) : nil
        case "svg": return trimmed.lowercased().hasPrefix("<svg") ? EmbeddedMarkup(kind: .svg, source: trimmed) : nil
        default: return nil
        }
    }

    private static func wholeReplyDocument(_ text: String) -> EmbeddedMarkup? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= maxDocumentBytes else { return nil }
        let lower = trimmed.lowercased()
        if (lower.hasPrefix("<!doctype html") || lower.hasPrefix("<html")) && lower.hasSuffix("</html>") {
            return EmbeddedMarkup(kind: .html, source: trimmed)
        }
        if lower.hasPrefix("<svg") && lower.hasSuffix("</svg>") { return EmbeddedMarkup(kind: .svg, source: trimmed) }
        return nil
    }

    private static func prose(_ text: String) -> [ReplySegment] {
        let t = text.trimmingCharacters(in: .newlines)
        return t.trimmingCharacters(in: .whitespaces).isEmpty ? [] : [.prose(t)]
    }
}
