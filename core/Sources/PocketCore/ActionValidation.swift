import Foundation

public struct ArgumentIssue: Codable, Sendable, Equatable {
    public enum Code: String, Codable, Sendable { case missing, invalid, unsupported }
    public let field: String
    public let code: Code
    public let question: String
    public init(_ field: String, _ code: Code, _ question: String) {
        self.field = field; self.code = code; self.question = question
    }
}

/// Deterministic constraints, independent of the classifier's confidence. Used before binding,
/// after edits, and by the exported contract fixtures. These are app limits, not OS limits.
public enum ActionValidation {
    public static let textLimit = 2_000
    public static let sharedTextLimit = 24_000

    public static func issues(contract: CapabilityContract, args: [String: String]) -> [ArgumentIssue] {
        let allowed = Set(contract.arguments.map(\.name))
        var out = args.keys.sorted().filter { !allowed.contains($0) }.map {
            ArgumentIssue($0, .unsupported, "This action does not support \($0). Restate the request using the supported fields; nothing was done.")
        }
        if ["imessage_send", "email_compose", "whatsapp_send", "instagram_dm", "x_dm"].contains(contract.id),
           let body = args["body"],
           body.range(of: #"^\s*[,;+/&]\s*(?:@|[A-Za-z])"#, options: .regularExpression) != nil {
            out.append(ArgumentIssue("body", .unsupported,
                "This body starts like a second recipient. This action supports one recipient and text only; restate it with one recipient."))
        }
        if contract.id == "calendar_create", let title = args["title"],
           calendarOptionsIssue("Schedule \(title)") != nil {
            out.append(ArgumentIssue("event_options", .unsupported,
                "This action creates one fixed one-hour event with no invitations or location. Set the duration, attendees, or location in Calendar, or request a simple one-hour event."))
        }
        for spec in contract.arguments {
            if let issue = issue(spec: spec, value: args[spec.name], capabilityID: contract.id) { out.append(issue) }
        }
        return out
    }

    public static func issue(spec: ArgSpec, value: String?, capabilityID: String) -> ArgumentIssue? {
        let value = value ?? ""
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return spec.required ? ArgumentIssue(spec.name, .missing, "Fill in \(spec.name) before confirming.") : nil
        }
        func invalid(_ message: String) -> ArgumentIssue { ArgumentIssue(spec.name, .invalid, message) }
        if value.count > textLimit { return invalid("Shorten \(spec.name) to \(textLimit) characters. The original text has not been truncated.") }
        if value.unicodeScalars.contains(where: { $0.value < 32 && ![9, 10, 13].contains($0.value) || $0.value == 127 }) {
            return invalid("Remove control characters from \(spec.name).")
        }
        switch spec.kind {
        case .handle:
            let pattern = capabilityID == "x_dm" ? #"^[A-Za-z0-9_]{1,15}$"# : #"^[A-Za-z0-9_][A-Za-z0-9_.]{0,29}$"#
            if trimmed.range(of: pattern, options: .regularExpression) == nil {
                return invalid("Enter the exact account handle without @, spaces, or a link.")
            }
        case .url:
            if !isWebURL(trimmed) { return invalid("Enter a complete http or https link with a host and no embedded username or password.") }
        case .duration:
            guard let seconds = durationSeconds(trimmed), seconds > 0, seconds <= 86_400 else {
                return invalid("Give a positive duration with units, up to 24 hours, such as 1 hour 30 minutes.")
            }
        case .number:
            guard trimmed.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil,
                  let n = Int(trimmed), (1...100).contains(n) else {
                return invalid("Use a whole number from 1 to 100 for \(spec.name).")
            }
        case .datetime:
            if let rejection = InstantParser.rejection(trimmed) {
                return invalid(rejection.question)
            }
        default: break
        }
        if capabilityID == "alarm_create", value.contains("|") {
            return invalid("Remove | from \(spec.name); the alarm Shortcut uses it to separate fields.")
        }
        return nil
    }

    public static func isWebURL(_ text: String) -> Bool {
        guard !text.contains(where: { $0.isWhitespace }),
              let url = URLComponents(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, !host.contains("{"), !host.contains("}"),
              url.user == nil, url.password == nil else { return false }
        return url.url != nil
    }

    public static func durationSeconds(_ text: String) -> Double? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?)"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = re.matches(in: text, range: range)
        guard !matches.isEmpty else { return nil }
        let remainder = re.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .replacingOccurrences(of: "and", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard remainder.isEmpty else { return nil }
        let ns = text as NSString
        var seconds = 0.0
        for m in matches {
            guard let n = Double(ns.substring(with: m.range(at: 1))), n.isFinite else { return nil }
            let unit = ns.substring(with: m.range(at: 2)).lowercased()
            seconds += n * (unit.hasPrefix("h") ? 3600 : unit.hasPrefix("m") ? 60 : 1)
        }
        return seconds.isFinite ? seconds : nil
    }

    /// Narrow guards for constraints the current executor cannot honor. This is not a natural-language
    /// completeness proof; the review card remains the authority for the exact action being proposed.
    public static func requestIssue(capabilityID: String, utterance: String) -> ArgumentIssue? {
        func has(_ pattern: String) -> Bool { utterance.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
        if ["flashlight_toggle", "focus_toggle", "low_power_toggle"].contains(capabilityID),
           !has(#"\btoggle\b"#) {
            return ArgumentIssue("state", .unsupported, "This Shortcut only toggles the current state; it cannot ensure on or off. Ask to toggle, or set the state in Control Center.")
        }
        if ["reminder_create", "calendar_create", "alarm_create"].contains(capabilityID) {
            if has(#"\b(every|each|daily|weekly|monthly|yearly|recurring|repeat)\b"#) {
                return ArgumentIssue("recurrence", .unsupported, "Repeating schedules are not supported by this action. Create the repeating item in its app, or request one occurrence.")
            }
            if has(#"\b(all[ -]day|when I (?:arrive|leave|get)|when (?:arriving|leaving))\b"#) {
                return ArgumentIssue("trigger", .unsupported, "This action needs a single exact time. All-day and location triggers must be set in the destination app.")
            }
        }
        if ["reminder_create", "calendar_create", "alarm_create"].contains(capabilityID) {
            let field = capabilityID == "alarm_create" ? "time" : "when"
            let months = #"(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"#
            if has(months + #"\s+\d{1,2}(?:st|nd|rd|th)?(?:,?\s*\d{4})?\s+(?:at|by)\s+\d{1,2}"#)
                || has(#"\bon\s+"# + months + #"\s+\d{1,2}"#) {
                return ArgumentIssue(field, .unsupported,
                    "Explicit calendar dates are not supported by this action. Use tomorrow, today, a weekday, or set the date in the destination app.")
            }
        }
        if capabilityID == "calendar_create", let issue = calendarOptionsIssue(utterance) {
            return issue
        }
        // Validate the time expression from the source utterance, before extraction can keep only part of it.
        // A day-only phrase is left to the normal missing/invalid-time card; qualifiers, ranges, multiple
        // instants, named zones and explicit past times must correct before any card exists.
        if ["reminder_create", "calendar_create", "alarm_create"].contains(capabilityID),
           let phrase = TimePhrase.capture(in: utterance),
           let rejection = InstantParser.rejection(phrase),
           rejection.requiresPlanningCorrection {
            let field = capabilityID == "alarm_create" ? "time" : "when"
            return ArgumentIssue(field, .unsupported, rejection.question)
        }
        if ["imessage_send", "email_compose", "whatsapp_send", "instagram_dm", "x_dm"].contains(capabilityID) {
            if let issue = messageOptionsIssue(utterance) { return issue }
        }
        return nil
    }

    /// Calendar creation is a fixed one-hour event with no invitations or location. Every common way of
    /// asking for a different duration, an attendee, or a place must correct instead of becoming a title.
    private static func calendarOptionsIssue(_ utterance: String) -> ArgumentIssue? {
        let leadingDuration = [
            #"\b(?:a|an)\s+\d+(?:\.\d+)?\s*[-\s]\s*(?:hours?|hrs?|minutes?|mins?)(?:\s+\w+)?\s+(?:meeting|event|block|session|call|lunch|dinner|appointment|slot|workshop|class|interview|review)\b"#,
            #"\b\d+(?:\.\d+)?\s*[-\s]\s*(?:hours?|hrs?|minutes?|mins?)(?:\s+\w+)?\s+(?:meeting|event|block|session|call|lunch|dinner|appointment|slot|workshop|class|interview|review)\b"#,
        ]
        let wholeDuration = [
            #"\bfor\s+\d+(?:\.\d+)?\s*(?:hours?|hrs?|minutes?|mins?)\b"#,
            #"\bfor\s+(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|an?|half\s+an?)\s+(?:hours?|hrs?|minutes?|mins?)\b"#,
        ]
        let ranges = [
            #"\bfrom\s+\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?\s*(?:-|–|—|to|until|through|till)\s*(?:at\s+)?\d{1,2}"#,
            #"\bbetween\s+\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?\s+and\s+\d{1,2}"#,
            #"\b\d{1,2}:\d{2}\s*(?:a\.?m\.?|p\.?m\.?)?\s*(?:-|–|—|to|until|through|till)\s*(?:at\s+)?\d{1,2}"#,
            #"\b\d{1,2}\s*(?:a\.?m\.?|p\.?m\.?)\s*(?:-|–|—|to|until|through|till)\s*(?:at\s+)?\d{1,2}"#,
            #"\b\d{1,2}\s*(?:-|–|—|to|until|through|till)\s*(?:at\s+)?\d{1,2}\s*(?:a\.?m\.?|p\.?m\.?)"#,
        ]
        let options = [
            #"\bwith\b"#,
            #"\b(?:invite|invites|invited|inviting|attendees?|guests?)\b"#,
            #"\b(?:at|in)\s+the\s+(?!(?:morning|afternoon|evening|night)\b)[A-Za-z]"#,
            #"\b(?:at|in)\s+(?:my|our)\s+[A-Za-z]"#,
            #"\b(?:at|in)\s+(?:home|work)\b"#,
            #"\bat\s+\d+\s+(?!(?:\d|a\.?m|p\.?m|am|pm|noon|midnight|today|tomorrow|tonight|o'?clock|time|minutes?|hours?)\b)[A-Za-z]"#,
            #"(?-i:\b(?:at|in)\s+(?!(?:Noon|Midnight|Today|Tomorrow|Tonight|AM|PM)\b)[A-Z][a-z]+)"#,
        ]
        func matches(_ pattern: String, in text: String) -> Bool {
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        // A non-"for" duration belongs to the event description before the time. Words after the time
        // ("about the 90-minute review") are subject matter, not a request for a longer event.
        let head = TimePhrase.range(in: utterance).map { String(utterance[..<$0.lowerBound]) } ?? utterance
        let found = wholeDuration.contains { matches($0, in: utterance) }
            || leadingDuration.contains { matches($0, in: head) }
            || ranges.contains { matches($0, in: utterance) }
            || options.contains { matches($0, in: utterance) }
        guard found else { return nil }
        return ArgumentIssue("event_options", .unsupported,
            "This action creates one fixed one-hour event with no invitations or location. Set the duration, attendees, or location in Calendar, or request a simple one-hour event.")
    }

    /// Message sends take one recipient and text only. Inspect the command prefix, stopping at a quote,
    /// colon, or body phrase, so a quoted body that mentions an attachment is not treated as instruction.
    private static func messageOptionsIssue(_ utterance: String) -> ArgumentIssue? {
        let groupHead = utterance.components(separatedBy: .newlines).joined(separator: " ")
            .replacingOccurrences(of: #"(?:\bsaying\b|\bthat says\b|\bto say\b|\bwith the message\b|:)[\s\S]*$"#,
                                  with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"["“][^"”]*["”]"#, with: "", options: .regularExpression)
        if groupHead.range(of: #"\b(?:group(?:\s+(?:chats?|threads?|messages?))?|chat\s+group)\b"#,
                           options: [.regularExpression, .caseInsensitive]) != nil {
            return ArgumentIssue("group", .unsupported,
                "OffLlama can't address an existing group by its name. Open that group in Messages to compose there, or ask to text one person. No recipient was selected.")
        }
        let ns = utterance as NSString
        let bodyStart = try! NSRegularExpression(
            pattern: #"\b(?:saying|that says|to say|with the message|that)\b|["“”:]"#,
            options: [.caseInsensitive])
        let command: String
        if let m = bodyStart.firstMatch(in: utterance, range: NSRange(location: 0, length: ns.length)) {
            command = ns.substring(to: m.range.location)
        } else {
            command = utterance
        }
        let person = #"(?:@[A-Za-z0-9_.]+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|[A-Za-z][A-Za-z0-9_.'-]*(?:\s+[A-Za-z][A-Za-z0-9_.'-]*)?)"#
        let list = person + #"\s*(?:,|;|\+|/|&|\band\b)\s*(?!(?:about|subject|body|message|saying|that|re|fwd|attached|attachment|cc|bcc|copy|schedule|today|tomorrow|tonight|at|on|in)\b)"# + person
        let recipientList = #"\b(?:email|e-mail|mail|text|sms|message|dm|direct message|whatsapp)\s+(?:a\s+(?:dm|message|text)\s+to\s+)?(?:to\s+)?"# + list
        let sendList = #"\bsend\s+(?:an?\s+(?:text|message|email|e-mail|dm)\s+to\s+)?(?:to\s+)?"# + list
        let messageOptions = [
            recipientList,
            sendList,
            #"\battach(?:es|ed|ing|ment|ments)?\b"#,
            #"\b(?:cc|bcc)(?:'?d|'?ing)?\b"#,
            #"\bcopy(?:ing)?\b"#,
            #"\bschedul(?:e|ed|ing)\s+(?:this|the\s+(?:email|message|send)|it)\b"#,
        ]
        guard messageOptions.contains(where: { command.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil })
        else { return nil }
        return ArgumentIssue("message_options", .unsupported,
            "This action supports one recipient and text only, sent from the compose screen. Add attachments, other recipients, or scheduling in the destination app.")
    }
}

/// Captures one complete time expression, including the day qualifier, every clock time or range the user
/// spoke, and a named zone or city. Resolution stays with `InstantParser`; this only keeps the original
/// words together so validation can refuse an unsupported phrase instead of silently keeping a prefix.
enum TimePhrase {
    private static let day = #"(?:(?:the\s+)?day\s+after\s+tomorrow|(?:the\s+)?day\s+before\s+yesterday|tomorrow|today|tonight|yesterday|(?:next|this|last|on)\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|week|month|year|night)|(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|(?:earlier\s+(?:today|this\s+(?:morning|afternoon|evening))|\d+\s+(?:minutes?|mins?|hours?|hrs?|days?|weeks?|months?|years?)\s+ago))\b"#
    private static let qualifier = #"(?:(?:around|about|approximately|roughly|nearly|maybe|perhaps)\s+)?"#
    private static let clock = qualifier + #"(?:\d{1,2}:\d{2}\s*(?:a\.?m\.?|p\.?m\.?)?|\d{1,2}\s*(?:a\.?m\.?|p\.?m\.?)|(?:at|by)\s+\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?|(?:at|by)\s+(?:noon|midnight)|noon|midnight)"#
    private static let tail = #"(?:\s*(?:,|and|or|&|-|–|—|to|until|through|till)\s*"# + clock + #")*"#
    private static let zone = #"(?:\s+(?:UTC[+-]\d{1,2}(?::?\d{2})?|(?:UTC|GMT|EST|EDT|CST|CDT|MST|MDT|PST|PDT|AKST|AKDT|HST|CET|CEST|BST|IST|JST|KST|AEST|AEDT|NZST|NZDT|ET|PT|CT|MT)\b(?:\s+time)?|(?-i:[A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,2}\s+(?i:time))|(?i:in\s+(?:Berlin|London|Paris|Tokyo|Sydney|Toronto|Chicago|Denver|Boston|Seattle|New\s+York|Los\s+Angeles|San\s+Francisco|Hong\s+Kong|Singapore|Dubai|Moscow)\b(?:\s+time)?)|(?:Eastern|Central|Mountain|Pacific|Alaska|Hawaii|Berlin|London|Paris|Tokyo|Sydney|Toronto|Chicago|Denver|Boston|Seattle|New\s+York|Los\s+Angeles|San\s+Francisco|Hong\s+Kong|Singapore|Dubai|Moscow)\b(?:\s+time)?|(?-i:in\s+[A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)|(?-i:[A-Z][a-z]+)))?"#
    private static let pattern = #"\b("# + day + #"\s*,?\s*(?:(?:morning|afternoon|evening|night)\s*)?"# + clock + tail + zone
        + #"|"# + clock + tail + #"(?:,?\s+"# + day + #")?"# + zone
        + #"|\bin\s+\d+\s+(?:minutes?|mins?|hours?|hrs?|days?)\b"#
        + #"|"# + day + #")"#
    private static let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])

    static func range(in utterance: String) -> Range<String.Index>? {
        let ns = utterance as NSString
        guard let m = regex.firstMatch(in: utterance, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: utterance) else { return nil }
        return String(utterance[r]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : r
    }

    static func capture(in utterance: String) -> String? {
        guard let r = range(in: utterance) else { return nil }
        return String(utterance[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Serializable argument rules and capabilities from the compiled action catalog.
public struct ActionContractDescription: Codable, Sendable {
    public let capability: CapabilityContract
    public let argumentRules: [String: String]
    public let prerequisites: [String]
    public let successEvidence: String
    public let decisions: [String]

    public static var all: [ActionContractDescription] {
        CapabilityCatalog.all.map { c in
            var rules: [String: String] = [:]
            for arg in c.arguments {
                let rule: String
                switch arg.kind {
                case .contact: rule = "Unique accessible contact identifier and exact labelled destination; ambiguous/missing/stale contacts require selection."
                case .handle: rule = c.id == "x_dm" ? "Exact handle: 1–15 ASCII letters, digits, underscore." : "Exact handle: 1–30 ASCII letters, digits, underscore or dot; starts with letter/digit/underscore."
                case .datetime: rule = "Exact time; ambiguous AM/PM, named zones/cities, ranges, multiple times, and explicit past instants require correction. Local reminder/calendar writes bind a Date and device timezone once; Shortcut handoffs receive the reviewed phrase and decide the next occurrence."
                case .duration: rule = "Positive finite duration, explicit seconds/minutes/hours, total <=86400 seconds. Compound units allowed."
                case .number: rule = "Integer in 1...100. Email count describes the request, not verified access to an inbox."
                case .url: rule = "Absolute http(s) URL with host, no whitespace or credentials."
                default: rule = "Literal text; no inferred output bindings, no silent truncation."
                }
                rules[arg.name] = "\(arg.required ? "Required" : "Optional"). \(rule) Maximum \(ActionValidation.textLimit) characters."
            }
            var prerequisites: [String] = []
            if c.arguments.contains(where: { $0.kind == .contact }) { prerequisites.append("Contacts access and a usable selected method; revalidate at confirmation.") }
            let evidence: String
            switch c.executor {
            case .reminderCreate, .eventCreate:
                prerequisites.append("EventKit write access; read access required to verify the saved identifier/title/time/attempt token.")
                evidence = "Matching EventKit read-back; save without read-back stays unverified. Calendar events last one hour and have no invitations or location."
            case .messageSend: evidence = "Messages accepted, cancelled, or failed; accepted does not prove delivery."
                prerequisites.append("Messages compose available and no conflicting sheet.")
            case .mailSend: evidence = "Mail queued, draft saved, cancelled, or failed; queued does not prove delivery."
                prerequisites.append("Configured Mail compose available and no conflicting sheet.")
            case .urlTemplate, .shortcut:
                prerequisites.append("Confirmed handoff; destination app/Shortcut must be available. Opening does not prove network, installation, playback, or downstream completion.")
                evidence = "OS accepted or refused the URL only; never claim the external task completed."
            case .autoreplyMemory: evidence = "Semantic rule saved to local memory; no background Instagram automation or message sent."
            case .notWired: evidence = "Unavailable; no execution or substitution."
            default:
                prerequisites.append("Request-bound input or picker where required; privacy checks for any cloud request; preserve actual provider and truncation notice.")
                evidence = "Read result with provenance; no external effect. Calendar search is limited to the next 30 days."
            }
            return ActionContractDescription(capability: c, argumentRules: rules, prerequisites: prerequisites,
                successEvidence: evidence, decisions: ["unsupported", "clarify_missing", "clarify_invalid", "resolve_ambiguity",
                    "permission_unavailable", "await_confirmation", "cancel", "execute_once", "observed_result", "failed", "unknown_no_replay"])
        }
    }
}
