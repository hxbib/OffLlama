import Foundation

/// A message channel named by explicit words. Nil means the user has not named one;
/// the app asks rather than guessing.
public enum MessageChannel: String, Sendable, Equatable, Codable {
    case imessage, whatsapp, instagram, x

    public var capabilityID: String {
        switch self {
        case .imessage: return "imessage_send"
        case .whatsapp: return "whatsapp_send"
        case .instagram: return "instagram_dm"
        case .x: return "x_dm"
        }
    }

    public var displayName: String {
        switch self {
        case .imessage: return "Messages"
        case .whatsapp: return "WhatsApp"
        case .instagram: return "Instagram"
        case .x: return "X"
        }
    }

    public static func channel(forCapabilityID id: String) -> MessageChannel? {
        switch id {
        case "imessage_send": return .imessage
        case "whatsapp_send": return .whatsapp
        case "instagram_dm": return .instagram
        case "x_dm": return .x
        default: return nil
        }
    }

    /// Explicit channel words win; otherwise a Messages-app verb implies iMessage.
    /// Bare "dm" names no app and returns nil.
    public static func parse(in utterance: String) -> MessageChannel? {
        let n = MessageCommand.head(utterance)
        if n.contains(" whatsapp ") || n.contains(" whats app ") { return .whatsapp }
        if n.contains(" instagram ") || n.contains(" insta ") || n.contains(" ig ") { return .instagram }
        if n.contains(" twitter ") || n.contains(" on x ") || n.contains(" x dm ") { return .x }
        if n.contains(" imessage ") || n.contains(" sms ") || n.contains(" text message ")
            || n.contains(" messages app ") { return .imessage }
        if MessageCommand.isEmailHead(utterance) { return nil }
        switch MessageCommand.leadingVerb(in: utterance) {
        case .messagesApp: return .imessage
        case .dmBare, .none: return nil
        }
    }

    /// Channel words stated anywhere, for follow-up answers such as "on WhatsApp".
    /// Verb implication is deliberately excluded here.
    public static func explicitWords(in utterance: String) -> MessageChannel? {
        let n = SkillRegistry.norm(utterance)
        if n.contains(" whatsapp ") || n.contains(" whats app ") { return .whatsapp }
        if n.contains(" instagram ") || n.contains(" insta ") || n.contains(" ig ") { return .instagram }
        if n.contains(" twitter ") || n.contains(" on x ") || n.contains(" x dm ") { return .x }
        if n.contains(" imessage ") || n.contains(" sms ") || n.contains(" messages ")
            || n.contains(" text ") { return .imessage }
        return nil
    }
}

public enum DraftMissingField: String, Sendable, Equatable, Codable {
    case contact, channel, body
}

/// A typed, request-bound incomplete message. The ledger row exists only once the
/// draft is complete; until then this value is the whole pending state.
public struct MessageDraft: Sendable, Equatable, Codable {
    public var requestID: UserRequestID
    public var contact: String?
    public var channel: MessageChannel?
    public var body: String?
    public var lowConfidence: Bool
    public var lastAsked: DraftMissingField?
    public var created: Date

    public init(requestID: UserRequestID, contact: String? = nil, channel: MessageChannel? = nil,
                body: String? = nil, lowConfidence: Bool = false,
                lastAsked: DraftMissingField? = nil, created: Date = Date()) {
        self.requestID = requestID; self.contact = contact; self.channel = channel
        self.body = body; self.lowConfidence = lowConfidence
        self.lastAsked = lastAsked; self.created = created
    }

    public var isComplete: Bool { contact != nil && channel != nil && body != nil }

    public var missingField: DraftMissingField? {
        if contact == nil { return .contact }
        if channel == nil { return .channel }
        if body == nil { return .body }
        return nil
    }

    public static let staleAfter: TimeInterval = 1800

    public func isStale(now: Date) -> Bool { now.timeIntervalSince(created) > Self.staleAfter }

    public func agePhrase(now: Date) -> String {
        let m = Int(now.timeIntervalSince(created) / 60)
        if m < 90 { return "\(max(m, 1)) minutes ago" }
        return "\(m / 60) hours ago"
    }

    public func question() -> String {
        let base: String
        switch missingField {
        case .contact:
            if let channel, channel != .imessage {
                base = "Who should I message on \(channel.displayName)?"
            } else {
                base = body == nil ? "Who should I message?" : "Who should I send that to?"
            }
        case .channel:
            base = "Which app should I use to message \(contact ?? "them")? Messages, WhatsApp, Instagram, or X?"
        case .body:
            base = contact.map { "What should I say to \($0)?" } ?? "What should the message say?"
        case .none:
            base = "Review the message and tap Confirm to open the compose sheet."
        }
        return lowConfidence ? "I might have misunderstood — \(base.firstLowercased)" : base
    }

    /// Retain a partial explicit message instead of dropping it into a bare clarify.
    /// Returns nil unless the channel is explicit and at least a recipient or a body parsed.
    public static func partial(utterance: String, requestID: UserRequestID, lowConfidence: Bool,
                               now: Date) -> (MessageDraft, String)? {
        guard MessageCommand.isExplicitMessageRequest(utterance),
              MessageChannel.parse(in: utterance) != nil else { return nil }
        let (draft, question) = retain(utterance: utterance, requestID: requestID,
                                       lowConfidence: lowConfidence, now: now)
        guard draft.contact != nil || draft.body != nil else { return nil }
        return (draft, question)
    }

    /// Retain any explicit message command as a typed draft. The channel may be
    /// unresolved; the question asks for exactly what is missing.
    public static func retain(utterance: String, requestID: UserRequestID, lowConfidence: Bool,
                              now: Date) -> (MessageDraft, String) {
        let parts = messageArgs(utterance)
        var draft = MessageDraft(requestID: requestID, contact: parts.contact,
                                 channel: MessageChannel.parse(in: utterance),
                                 body: parts.body,
                                 lowConfidence: lowConfidence, created: now)
        draft.lastAsked = draft.missingField
        return (draft, draft.question())
    }

    /// Merged message extraction: the command-rest heuristic first, marker-based
    /// parsing for what it misses. Both planning paths share this so a draft kept
    /// on one path reads the same on the other.
    public static func messageArgs(_ utterance: String) -> (contact: String?, body: String?) {
        let base = ArgumentExtractor.heuristic(tool: "send_message", utterance: utterance)
        let contact = nonempty(base["contact"]) ?? SkillArgs.person(utterance)
        var body = SkillArgs.body(utterance) ?? nonempty(base["body"])
        if contact == nil, body == nil, var rest = MessageCommand.restAfterVerb(utterance) {
            if let r = rest.range(of: #"^(?:on|via)\s+[A-Za-z]+\s+"#, options: .regularExpression) {
                rest = String(rest[r.upperBound...]).trimmed
            }
            body = rest.isEmpty ? nil : rest
        }
        return (contact, body)
    }

    static func nonempty(_ value: String?) -> String? {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        return v
    }
}

/// Deterministic classification of one follow-up utterance against pending drafts.
/// No model call: anything ambiguous falls through to the normal path untouched.
public enum FollowUpResolution: Sendable, Equatable {
    case none
    case completed(MessageDraft)
    case updated(MessageDraft)
    case cancelled(UserRequestID)
    case clarifyKeep(String)
    case disambiguate(String)
}

public enum MessageFollowUp {
    static let cancelPhrases = ["never mind", "nevermind", "forget it", "forget about it",
                                "don't send", "dont send", "do not send"]
    static let cancelWhole = ["cancel", "cancelled", "canceled", "stop", "abort"]
    static let negativeWhole = ["no", "nope", "nah", "neither", "not that"]
    static let questionStarts = ["what", "when", "where", "who", "why", "how", "is", "are",
                                 "do", "does", "did", "can", "could", "would", "should", "will"]
    static let commandStarts = ["remind", "schedule", "book", "set", "create", "add", "open", "play",
                                "call", "search", "find", "show", "start", "run", "turn", "check"]

    public static func resolve(_ utterance: String, drafts: [MessageDraft],
                               now: Date = Date()) -> FollowUpResolution {
        guard !drafts.isEmpty else { return .none }
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }
        let n = SkillRegistry.norm(utterance)

        if let body = bodyAnswer(utterance, norm: n, draft: drafts[0]),
           !MessageCommand.isExplicitMessageRequest(utterance) {
            let fresh = drafts.filter { !$0.isStale(now: now) }
            if fresh.count == 1 {
                let head = MessageCommand.head(utterance)
                let contact = head.hasPrefix(" to ") ? contactAnswer(head, norm: head) : nil
                return fill(fresh[0], contact: contact, channel: nil, body: body, now: now)
            }
            if fresh.count > 1 { return resolveAgainstMany(utterance, norm: n, drafts: fresh, now: now) }
        }

        if isCancel(n) {
            if drafts.count == 1 { return .cancelled(drafts[0].requestID) }
            let named = drafts.filter { draft in
                guard let name = draft.contact else { return false }
                return n.contains(SkillRegistry.norm(name))
            }
            if named.count == 1 { return .cancelled(named[0].requestID) }
            return .disambiguate("Which message should I cancel? " + describe(drafts) + ".")
        }
        if isNegative(n) {
            if drafts.count == 1 {
                let q = drafts[0].missingField.map { _ in drafts[0].question() } ?? "Still want to send it?"
                return .clarifyKeep(q)
            }
            return .disambiguate("Which message do you mean? " + describe(drafts) + ".")
        }

        if let channel = bareChannel(utterance, norm: n) {
            let fresh = drafts.filter { !$0.isStale(now: now) }
            let needy = fresh.filter { $0.channel == nil }
            if needy.count == 1 {
                return fill(needy[0], contact: nil, channel: channel, body: nil, now: now)
            }
            if needy.count > 1 {
                return .disambiguate("Which message should use \(channel.displayName)? " + describe(needy) + ".")
            }
            // A lone answered channel switches the single pending draft; otherwise
            // the app name falls through to the normal path as a new request.
            if fresh.count == 1, fresh[0].channel != channel {
                return fill(fresh[0], contact: nil, channel: channel, body: nil, now: now)
            }
        }
        if MessageCommand.isExplicitMessageRequest(utterance) {
            return resolveExplicitCommand(utterance, drafts: drafts, now: now)
        }
        if ActionPlanner.isExplicitEmailRequest(utterance) || isCommandLike(n) { return .none }
        if n.range(of: #"^ (?:what time is it|what(?: is| s) the (?:weather|time)|how much (?:battery|storage))\b"#, options: .regularExpression) != nil { return .none }

        let fresh = drafts.filter { !$0.isStale(now: now) }
        if fresh.isEmpty {
            let answer = n.trimmingCharacters(in: .whitespaces)
            if drafts.count == 1, ["yes", "that one", "continue", "resume"].contains(answer) {
                var refreshed = drafts[0]
                refreshed.created = now
                refreshed.lastAsked = refreshed.missingField
                return .updated(refreshed)
            }
            if drafts.count == 1, answer == "start fresh" { return .cancelled(drafts[0].requestID) }
            return .disambiguate("I have an older unfinished message to \(describe(drafts)) from "
                + "\(drafts[0].agePhrase(now: now)). Say “continue” to finish it or “cancel” to discard it.")
        }
        if fresh.count > 1 { return resolveAgainstMany(utterance, norm: n, drafts: fresh, now: now) }
        return resolveAgainstOne(utterance, norm: n, draft: fresh[0], now: now)
    }

    // MARK: explicit restatement

    private static func resolveExplicitCommand(_ utterance: String, drafts: [MessageDraft],
                                               now: Date) -> FollowUpResolution {
        let parts = MessageDraft.messageArgs(utterance)
        let contact = parts.contact
        let channel = MessageChannel.parse(in: utterance)
        let body = parts.body
        let fresh = drafts.filter { !$0.isStale(now: now) }
        let pool = fresh.isEmpty ? drafts : fresh
        if let contact {
            let matches = pool.filter { $0.contact?.lowercased() == contact.lowercased() }
            if matches.count == 1 {
                if let body, let old = matches[0].body, body != old { return .none }
                return fill(matches[0], contact: contact, channel: channel, body: body, now: now)
            }
            if matches.isEmpty { return .none }
            return .disambiguate("Which message to \(matches[0].contact ?? contact)? " + describe(matches) + ".")
        }
        if pool.count == 1, channel == nil || channel == pool[0].channel {
            return fill(pool[0], contact: nil, channel: channel, body: body, now: now)
        }
        return .none
    }

    // MARK: completion

    private static func resolveAgainstOne(_ utterance: String, norm n: String, draft: MessageDraft,
                                          now: Date) -> FollowUpResolution {
        if draft.lastAsked == .body, let body = shortBody(utterance) {
            return fill(draft, contact: nil, channel: nil, body: body, now: now)
        }
        if draft.lastAsked == .contact {
            guard let contact = contactAnswer(utterance, norm: n) else { return .clarifyKeep(draft.question()) }
            return fill(draft, contact: contact, channel: nil, body: nil, now: now)
        }
        let channel = MessageChannel.explicitWords(in: MessageCommand.head(utterance))
        // A bare channel answer ("WhatsApp") must not be mistaken for a contact name.
        let contact = channel == nil ? contactAnswer(utterance, norm: n) : nil
        let body = bodyAnswer(utterance, norm: n, draft: draft)
        if contact == nil, channel == nil, body == nil {
            if draft.lastAsked == .body, let text = shortBody(utterance), !text.isEmpty {
                return fill(draft, contact: nil, channel: nil, body: text, now: now)
            }
            if draft.lastAsked == .contact, let name = shortName(utterance) {
                return fill(draft, contact: name, channel: nil, body: nil, now: now)
            }
            if draft.lastAsked == .channel {
                return .clarifyKeep(draft.question())
            }
            return .none
        }
        return fill(draft, contact: contact, channel: channel, body: body, now: now)
    }

    private static func resolveAgainstMany(_ utterance: String, norm n: String, drafts: [MessageDraft],
                                           now: Date) -> FollowUpResolution {
        let channel = MessageChannel.explicitWords(in: MessageCommand.head(utterance))
        let contact = channel == nil ? contactAnswer(utterance, norm: n) : nil
        let body = bodyAnswer(utterance, norm: n, draft: drafts[0])
        if let contact {
            let matches = drafts.filter { $0.contact?.lowercased() == contact.lowercased() }
            if matches.count == 1 {
                return fill(matches[0], contact: contact, channel: channel, body: body, now: now)
            }
            if !matches.isEmpty {
                return .disambiguate("Which message to \(matches[0].contact ?? contact)? " + describe(matches) + ".")
            }
        }
        if contact == nil, channel != nil {
            let matches = drafts.filter { $0.channel == nil }
            if matches.count == 1 {
                return fill(matches[0], contact: nil, channel: channel, body: body, now: now)
            }
        }
        if contact == nil, channel == nil, body == nil { return .disambiguate("Which message is this for? " + describe(drafts) + ".") }
        return .disambiguate("Which message do you mean? " + describe(drafts) + ".")
    }

    private static func fill(_ draft: MessageDraft, contact: String?, channel: MessageChannel?,
                             body: String?, now: Date) -> FollowUpResolution {
        var next = draft
        if next.isStale(now: now) { next.created = now }
        if let contact, next.contact == nil { next.contact = contact }
        else if let contact, next.contact?.lowercased() != contact.lowercased() {
            return .disambiguate("Is this message for \(next.contact ?? "them") or \(contact)?")
        }
        if let channel { next.channel = channel }
        if let body, next.body == nil { next.body = body }
        else if let body, next.body != body {
            return .clarifyKeep("I already have the message text saved. \(next.question())")
        }
        if next.contact == nil, next.channel == nil, next.body == nil { return .none }
        next.lastAsked = next.missingField
        if next.isComplete { return .completed(next) }
        if next == draft { return .none }
        return .updated(next)
    }

    // MARK: piece parsers

    /// A contact answer: "Dana", "@sam", "to Dana: ...". Never a sentence.
    private static func contactAnswer(_ utterance: String, norm n: String) -> String? {
        if let h = SkillArgs.first(#"@([A-Za-z0-9_][A-Za-z0-9_.]{0,29})"#, in: utterance) {
            return h
        }
        var nameText = utterance.trimmed
        if nameText.lowercased().hasPrefix("to ") { nameText = String(nameText.dropFirst(3)) }
        if let colon = nameText.firstIndex(of: ":") { nameText = String(nameText[..<colon]) }
        let words = nameText.split(whereSeparator: \.isWhitespace).map(String.init)
        guard (1...3).contains(words.count),
              words.allSatisfy({ w in w.first?.isLetter == true && w.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" || $0 == "-" || $0 == "." }) })
        else { return nil }
        let name = words.joined(separator: " ")
        if words.contains(where: { SkillArgs.notNames.contains($0.lowercased()) }) { return nil }
        return name
    }

    private static func bodyAnswer(_ utterance: String, norm n: String, draft: MessageDraft) -> String? {
        if let quoted = SkillArgs.first(#"[\"“]([^\"”]+)[\"”]"#, in: utterance, literal: true) { return quoted }
        if let marked = SkillArgs.first(#"(?:\bsaying|\bthat says|\bto say|\bwith the message|:)\s+([\s\S]+)$"#, in: utterance, literal: true) {
            let clean = marked.trimmed
            return clean.isEmpty ? nil : clean
        }
        if let to = SkillArgs.first(#"^to\s+[A-Z][a-z]+(?: [A-Z][a-z]+)?:\s*(.+)$"#, in: utterance, literal: true) {
            return to.trimmed
        }
        return nil
    }

    private static func shortBody(_ utterance: String) -> String? {
        let t = utterance.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'.!?"))
        guard !t.isEmpty, t.count <= ActionValidation.textLimit else { return nil }
        return utterance.trimmed
    }

    private static func shortName(_ utterance: String) -> String? {
        contactAnswer(utterance, norm: SkillRegistry.norm(utterance))
    }

    /// A follow-up that names only an app: "Instagram", "on WhatsApp", "X".
    private static func bareChannel(_ utterance: String, norm n: String) -> MessageChannel? {
        let drop: Set<String> = ["on", "via", "the", "a", "an", "app"]
        let words = n.split(separator: " ").map(String.init).filter { !drop.contains($0) }
        guard (1...2).contains(words.count) else { return nil }
        switch words.joined(separator: " ") {
        case "whatsapp", "whats app", "wa": return .whatsapp
        case "instagram", "insta", "ig": return .instagram
        case "twitter", "x": return .x
        case "imessage", "sms", "messages", "message", "text": return .imessage
        default: return nil
        }
    }

    // MARK: utterance shapes

    private static func isCancel(_ n: String) -> Bool {
        let t = n.trimmingCharacters(in: .whitespaces)
        if cancelWhole.contains(t) || t.hasPrefix("cancel ") { return true }
        return cancelPhrases.contains { t == $0 || t == $0 + " that" || t == $0 + " message" }
    }

    private static func isNegative(_ n: String) -> Bool {
        let t = n.trimmingCharacters(in: .whitespaces)
        return negativeWhole.contains(t)
    }

    private static func isQuestionLike(_ trimmed: String, norm n: String) -> Bool {
        if trimmed.hasSuffix("?") { return true }
        let first = n.split(separator: " ").first.map(String.init) ?? ""
        return questionStarts.contains(first)
    }

    private static func isCommandLike(_ n: String) -> Bool {
        if n.hasPrefix(" call me ") { return false }
        let first = n.split(separator: " ").first.map(String.init) ?? ""
        return commandStarts.contains(first)
    }

    /// Secret-safe for diagnostics only in aggregate; the reply text names recipients
    /// because it is shown to the user, never logged.
    private static func describe(_ drafts: [MessageDraft]) -> String {
        let parts = drafts.map { d -> String in
            var p = d.contact.map { "to \($0)" } ?? "with no recipient yet"
            if let c = d.channel { p += " on \(c.displayName)" }
            if d.body == nil { p += " (needs message text)" }
            return p
        }
        return ActionPlanner.describeDrafts(parts)
    }
}

/// Polite and recipient-first message-command shapes. Owns the explicit-message
/// detector so routing, channels and extraction share one definition.
public enum MessageCommand {
    public enum LeadingVerb: Sendable, Equatable { case messagesApp, dmBare }

    static let nounExclusions: Set<String> = ["of", "failed", "failure", "history", "histories",
                                              "notification", "notifications", "preview", "tone",
                                              "tones", "settings", "thread", "threads", "message", "messages"]

    /// Normed utterance with greeting and polite prefixes removed.
    public static func stripped(_ utterance: String) -> String {
        var s = SkillRegistry.norm(utterance)
        for pattern in [#"^ (?:hey|hi|hello|okay|ok) "#, #"^ (?:please )?"#,
                        #"^ (?:(?:can|could|would) you )?"#, #"^ (?:please )?"#] {
            if let r = s.range(of: pattern, options: .regularExpression) {
                s = " " + s[r.upperBound...]
            }
        }
        return s
    }

    public static func leadingVerb(in utterance: String) -> LeadingVerb? {
        let s = stripped(utterance)
        if s.range(of: #"^ (?:direct message|dm|dms) "#, options: .regularExpression) != nil { return .dmBare }
        if s.range(of: #"^ (?:reply to|respond to|write to) "#, options: .regularExpression) != nil { return .messagesApp }
        guard let r = s.range(of: #"^ (?:text|texts|sms|whatsapp|message|messages|msg|msgs|ping|tell|send) "#,
                              options: .regularExpression) else { return nil }
        let rest = String(s[r.upperBound...])
        if rest.isEmpty || rest == " " { return .messagesApp }
        let first = rest.split(separator: " ").first.map(String.init) ?? ""
        if nounExclusions.contains(first) { return nil }
        if s.hasPrefix(" tell ") && (first == "me" || first == "us") { return nil }
        return .messagesApp
    }

    /// The command head: everything before a body marker, quote or colon.
    public static func head(_ utterance: String) -> String {
        let raw = utterance
        if let r = raw.range(of: #"\b(?:saying|that says|to say|with the message)\b|["“”:]"#,
                             options: [.regularExpression, .caseInsensitive]) {
            return SkillRegistry.norm(String(raw[..<r.lowerBound]))
        }
        return SkillRegistry.norm(raw)
    }

    public static func isEmailHead(_ utterance: String) -> Bool {
        let h = head(stripped(utterance))
        return h.range(of: #" (?:e-?mail|mail)\b"#, options: .regularExpression) != nil
    }

    public static func isExplicitMessageRequest(_ utterance: String) -> Bool {
        if ActionPlanner.isExplicitEmailRequest(utterance) { return false }
        if isEmailHead(utterance) { return false }
        return leadingVerb(in: utterance) != nil
    }

    /// Raw text after the greeting, polite prefix and command verb. Used only when
    /// no recipient parsed, so the user's words survive as the message body.
    public static func restAfterVerb(_ utterance: String) -> String? {
        guard let re = try? NSRegularExpression(
            pattern: #"^\s*(?:(?:hey|hi|hello|okay|ok|please)\s+)?(?:(?:can|could|would)\s+you\s+)?(?:please\s+)?(?:direct message|reply to|respond to|write to|text|sms|whatsapp|message|msg|dms?|ping|tell|send)\s+([\s\S]*)$"#,
            options: [.caseInsensitive]),
            let m = re.firstMatch(in: utterance, range: NSRange(utterance.startIndex..., in: utterance)),
            m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: utterance) else { return nil }
        let rest = String(utterance[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }
}

extension ActionPlanner {
    static func describeDrafts(_ parts: [String]) -> String { list(parts) }
}

private extension String {
    var firstLowercased: String {
        guard let f = first else { return self }
        return String(f).lowercased() + dropFirst()
    }
}
