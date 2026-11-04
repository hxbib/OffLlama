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
        if capabilityID == "calendar_create", has(#"\b(for\s+\d+\s*(?:hours?|minutes?)|until|ending|ends? at|invite|attendees?)\b|\bfrom\s+\d.*\bto\s+\d"#) {
            return ArgumentIssue("event_options", .unsupported, "This action creates a one-hour event without invitations. Set the duration or attendees in Calendar, or request a one-hour event.")
        }
        if ["imessage_send", "email_compose", "whatsapp_send", "instagram_dm", "x_dm"].contains(capabilityID) {
            // Only inspect the command prefix; quoted/saying message content is not an instruction.
            let prefix = utterance.components(separatedBy: CharacterSet(charactersIn: "\"“:")).first ?? utterance
            let command = prefix.components(separatedBy: " saying ").first ?? prefix
            if command.range(of: #"\b(?:attach|attachment|cc|bcc|schedule|scheduled)\b|\b(?:text|message|email|mail|dm)\s+\w+\s+(?:and|&)\s+\w+"#,
                             options: [.regularExpression, .caseInsensitive]) != nil {
                return ArgumentIssue("message_options", .unsupported, "This action supports one recipient and text only, sent from the compose screen. Add attachments, other recipients, or scheduling in the destination app.")
            }
        }
        return nil
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
                case .datetime: rule = "Exact time; ambiguous AM/PM, unhandled zones, invalid/past instants require correction. Local writes bind a Date and device timezone once; Shortcuts receive the reviewed phrase."
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
                evidence = "Matching EventKit read-back; save without read-back stays unverified. Calendar events last one hour."
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
