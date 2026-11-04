import Foundation

/// Side effects live behind this protocol: EventKit / Contacts / Shortcuts bridge on iOS; a recorder in tests.
public protocol ActionExecutor: Sendable {
    func searchContacts(_ query: String) async throws -> [String]
    func searchEvents(_ query: String) async throws -> [String]
    func perform(_ action: PlannedAction) async throws -> String
}

public struct PlannedAction: Sendable, Equatable, Codable {
    public var tool: String               // OptionSets.toolChoice ids
    public var args: [String: String]
    public init(tool: String, args: [String: String]) { self.tool = tool; self.args = args }
}

public enum Reply: Sendable, Equatable {
    case local(String)
    case cloud(String, provider: String)
    case acted(String)
    case needsConfirmation(PlannedAction, prompt: String)
    case clarify(String)
    case offlineFallback(String)
}

public struct AssistantTurn: Sendable {
    public var reply: Reply
    public var decisions: [ReflexDecision]
    public var remembered: [MemoryFact]
    /// The tool call Reflex planned (shown as JSON in the decision card), if any.
    public var action: PlannedAction? = nil
    /// Exactly what left the device on escalation (after scrubbing), for the privacy info view.
    public var cloudPromptSent: String? = nil
    public var corrections: [(old: MemoryFact, new: MemoryFact)] = []
    /// True when the sensitivity decision said "sensitive" (online or offline): the turn was answered on device and nothing
    /// was sent. Drives the "Kept on device · nothing sent" badge.
    public var cloudWithheldForSensitivity = false
}

/// Cheap lexical pre-check: health, money/credentials and intimate topics. Only decides whether the sensitivity Reflex
/// decision also runs on a locally-routed turn (to show its card); it never replaces that decision.
public enum SensitivityHint {
    static let re = try! NSRegularExpression(pattern: #"\b(cholesterol|ldl|hdl|blood (?:test|pressure|sugar|work)|a1c|glucose|diagnos\w*|hiv|std|sti|pregnan\w*|therap(?:y|ist)|medication|prescription|symptoms?|test results?|lab results?|biopsy|cancer|depress\w*|anxiety|bank account|account (?:number|balance)|bank balance|salary|debt|ssn|social security|credit card|pin code|password|passcode|routing number|tax return|intimate|sexual)\b"#, options: [.caseInsensitive])
    public static func matches(_ s: String) -> Bool { re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
}

extension PlannedAction {
    /// Stable, pretty JSON for display: {"tool": ..., "arguments": {...}} with sorted keys.
    public var json: String {
        let obj: [String: Any] = ["tool": tool, "arguments": args]
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else { return tool }
        return String(decoding: d, as: UTF8.self)
    }
}

public final class Assistant: @unchecked Sendable {
    public let reflex: Reflex
    public let memory: MemoryStore
    public let actions: ActionExecutor
    public var cloud: CloudBrainChain
    public var isOnline: () -> Bool
    public var scrubber = PrivacyScrubber()
    /// Char budget of the always-injected memory profile in local prompts (0 = off). Small: the 1B context stays short.
    public var profileMaxChars = 600
    /// Char budget of the profile sent to the cloud on escalation, after scrubbing (0 = never send the profile).
    public var cloudProfileMaxChars = 400

    public init(reflex: Reflex, memory: MemoryStore, actions: ActionExecutor, cloud: CloudBrainChain = .init([]), isOnline: @escaping () -> Bool = { false }) {
        self.reflex = reflex; self.memory = memory; self.actions = actions; self.cloud = cloud; self.isOnline = isOnline
    }

    func memoryContext(_ q: String) async throws -> (String, [MemoryFact]) {
        let hits = try await memory.retrieve(q, k: 4).map(\.fact)
        return (hits.isEmpty ? "" : "Known about the user:\n" + hits.map { "- " + $0.text }.joined(separator: "\n") + "\n", hits)
    }

    /// Memory block for local generation: profile one-pager (bounded) + retrieved facts. Reflex decision contexts are unchanged.
    func localMemory(_ mem: String) -> String {
        guard profileMaxChars > 0, let p = try? memory.profileOnePager(maxChars: profileMaxChars), !p.isEmpty else { return mem }
        return p + "\n" + mem
    }

    public func handle(_ utterance: String, now: Date = Date()) async throws -> AssistantTurn {
        var decisions: [ReflexDecision] = []
        let (mem, _) = try await memoryContext(utterance)
        let online = isOnline()
        let ctx = "\(mem)Network: \(online ? "online" : "offline")\nUser: \(utterance)"

        // Memory write path (cheap reflex; runs every turn).
        var remembered: [MemoryFact] = []
        var corrections: [(old: MemoryFact, new: MemoryFact)] = []
        let rem = try await reflex.decide(OptionSets.rememberOrNot, context: "User: \(utterance)")
        decisions.append(rem)
        if rem.chosen.id != "no" {
            for var f in RuleFactExtractor.extract(utterance) {
                if rem.chosen.id == "remember_temporary" && f.ttl == nil { f.ttl = 7 * 86_400 }
                let r = try await memory.upsert(f) { old, new in
                    let d = try await self.reflex.decide(OptionSets.memoryConflict, context: "Existing memory: \(old.text)\nNew statement: \(new.text)")
                    decisions.append(d)
                    return ConflictResolution(rawValue: d.chosen.id) ?? .keepBoth
                }
                if let fact = r.fact {
                    remembered.append(fact)
                    if r.resolution == .update { for old in try memory.history(subject: fact.subject, attribute: fact.attribute) where old.supersededBy == fact.id { corrections.append((old, fact)) } }
                }
            }
        }

        let route = try await reflex.decide(OptionSets.route, context: ctx)
        decisions.append(route)
        let lmem = localMemory(mem)

        switch route.chosen.id {
        case "tool":
            var planned: PlannedAction?
            let reply = try await toolPath(utterance, ctx: ctx, decisions: &decisions, planned: &planned)
            return AssistantTurn(reply: reply, decisions: decisions, remembered: remembered, action: planned, corrections: corrections)
        case "clarify":
            let q = try await reflex.engine.generate(prompt: Self.localPrompt("Ask ONE short clarifying question about: \(utterance)", mem: lmem), maxTokens: 40, temperature: 0.2)
            return AssistantTurn(reply: .clarify(q.trimmed), decisions: decisions, remembered: remembered, corrections: corrections)
        case "answer_local":
            // Lexically sensitive requests still get the sensitivity card, so the user sees it was kept on device.
            var withheld = false
            if SensitivityHint.matches(utterance) {
                let sens = try await reflex.decide(OptionSets.sensitivity, context: "User: \(utterance)")
                decisions.append(sens)
                withheld = sens.chosen.id == "sensitive"
            }
            let a = try await reflex.engine.generate(prompt: Self.localPrompt(utterance, mem: lmem), maxTokens: 200, temperature: 0.3)
            return AssistantTurn(reply: .local(a.trimmed), decisions: decisions, remembered: remembered, corrections: corrections,
                                 cloudWithheldForSensitivity: withheld)
        default: // escalate_cloud (chosen by the model, or fallback because confidence < tau)
            // Sensitivity runs online AND offline, so its card and the "Kept on device" badge show in airplane mode too.
            let sens = try await reflex.decide(OptionSets.sensitivity, context: "User: \(utterance)")
            decisions.append(sens)
            if sens.chosen.id == "sensitive" {
                let a = try await reflex.engine.generate(prompt: Self.localPrompt(utterance, mem: lmem), maxTokens: 200, temperature: 0.3)
                return AssistantTurn(reply: .local(a.trimmed), decisions: decisions, remembered: remembered, corrections: corrections,
                                     cloudWithheldForSensitivity: true)
            }
            guard online, !cloud.brains.isEmpty else {
                // Offline with a question the Reflex wanted to escalate: ask the trained `answerability` decision whether a
                // small on-device model can answer it at all; if not, say so instead of guessing (no made-up answer).
                let can = try await reflex.decide(OptionSets.answerability, context: "\(mem)User: \(utterance)")
                decisions.append(can)
                guard can.chosen.id == "yes" else {
                    return AssistantTurn(reply: .offlineFallback(mem.isEmpty ? "I can't answer that offline, and you haven't told me anything about it. Ask again when you're online."
                                                                              : "I'm not sure about that offline. Here's what I know: " + mem.replacingOccurrences(of: "Known about the user:\n", with: "").trimmed),
                                         decisions: decisions, remembered: remembered, corrections: corrections)
                }
                let a = try await reflex.engine.generate(prompt: Self.localPrompt(utterance, mem: lmem), maxTokens: 200, temperature: 0.3)
                return AssistantTurn(reply: .offlineFallback(a.trimmed), decisions: decisions, remembered: remembered, corrections: corrections)
            }
            var sc = scrubber
            sc.knownNames = Array(Set(scrubber.knownNames + ((try? memory.entityNames()) ?? [])))
            let prof = cloudProfileMaxChars > 0 ? ((try? memory.profileOnePager(maxChars: cloudProfileMaxChars, redactSensitive: true)) ?? "") : ""
            let s = sc.scrub((prof.isEmpty ? "" : prof + "\n") + mem + utterance)
            let ans = try await cloud.complete([ChatMessage(role: "system", content: "You are the reasoning brain of a private phone assistant. Placeholders like [PERSON_1] stand for private data; keep them verbatim."),
                                                ChatMessage(role: "user", content: s.text)])
            return AssistantTurn(reply: .cloud(sc.restore(ans.text, mapping: s.mapping), provider: "\(ans.provider) · \(ans.model)"), decisions: decisions,
                                 remembered: remembered, cloudPromptSent: s.text, corrections: corrections)
        }
    }

    func toolPath(_ utterance: String, ctx: String, decisions: inout [ReflexDecision], planned: inout PlannedAction?) async throws -> Reply {
        let tool = try await reflex.decide(OptionSets.toolChoice, context: ctx)
        decisions.append(tool)
        guard tool.chosen.id != "none" else { return .clarify("What would you like me to do?") }
        var args = ArgumentExtractor.heuristic(tool: tool.chosen.id, utterance: utterance)

        if ["send_message", "lookup_contact"].contains(tool.chosen.id), let who = args["contact"] {
            let cands = try await actions.searchContacts(who)
            if cands.count > 1 {
                let d = try await reflex.decide(OptionSets.contactPick(candidates: cands), context: ctx)
                decisions.append(d)
                guard d.chosen.id != "ask" else { return .clarify("Which \(who)? " + cands.joined(separator: ", ")) }
                args["contact"] = d.chosen.label
            } else if let only = cands.first { args["contact"] = only }
            else { return .clarify("I couldn't find \(who) in your contacts.") }
        }
        if tool.chosen.id == "find_event", let q = args["query"] {
            let cands = try await actions.searchEvents(q)
            if cands.count > 1 {
                let d = try await reflex.decide(OptionSets.eventPick(candidates: cands), context: ctx)
                decisions.append(d)
                guard d.chosen.id != "ask" else { return .clarify("Which one? " + cands.joined(separator: "; ")) }
                args["event"] = d.chosen.label
            }
        }
        let action = PlannedAction(tool: tool.chosen.id, args: args)
        planned = action
        if action.tool == "search_memory" {   // fully on device: answer from MemoryStore, or say so when nothing matches
            let hits = try await memory.retrieve(args["query"] ?? utterance, k: 3)
            guard !hits.isEmpty else { return .local("You haven't told me that yet.") }
            return .acted("From memory: " + hits.map { $0.fact.text }.joined(separator: "; "))
        }
        let conf = try await reflex.decide(OptionSets.confirmBeforeAct, context: "\(ctx)\nPlanned action: \(action.tool) \(args.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")
        decisions.append(conf)
        if conf.chosen.id == "confirm" || action.tool == "send_message" {   // messages always confirm: hard rule
            return .needsConfirmation(action, prompt: "\(action.tool.replacingOccurrences(of: "_", with: " ").capitalized): \(args.values.sorted().joined(separator: " · "))?")
        }
        return .acted(try await actions.perform(action))
    }

    public func confirm(_ a: PlannedAction) async throws -> Reply { .acted(try await actions.perform(a)) }

    static func localPrompt(_ q: String, mem: String) -> String {
        "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\nYou are a concise, warm personal assistant running fully offline on the user's phone. \(mem)<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n\(q)<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n"
    }
}

/// Cheap argument extraction; the on-device model refines it when needed (app side). Times stay as raw phrases
/// and are resolved by NSDataDetector on iOS.
public enum ArgumentExtractor {
    public static func heuristic(tool: String, utterance u: String) -> [String: String] {
        var a: [String: String] = [:]
        func first(_ p: String, ci: Bool = true) -> String? {
            guard let re = try? NSRegularExpression(pattern: p, options: ci ? .caseInsensitive : []),
                  let m = re.firstMatch(in: u, range: NSRange(u.startIndex..., in: u)), m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: u) else { return nil }
            return String(u[r]).trimmed
        }
        let when = first(#"\b((?:tomorrow|today|tonight|next \w+|on \w+day|at \d{1,2}(?::\d{2})?\s?(?:am|pm)?|in \d+ (?:minutes?|hours?|days?))(?:\s(?:at|by) \d{1,2}(?::\d{2})?\s?(?:am|pm)?)?)"#)
        switch tool {
        case "send_message":
            a["contact"] = first(#"(?i:text|message|tell|send)\s+(?i:a message to\s+)?([A-Z][a-z]+(?: [A-Z][a-z]+)?)"#, ci: false)
            a["body"] = first(#"(?:that|saying|:)\s+(.+)$"#) ?? ""
        case "lookup_contact":
            a["contact"] = first(#"([A-Z][a-z]+(?: [A-Z][a-z]+)?)'s"#, ci: false) ?? first(#"(?i:call|for|of)\s+([A-Z][a-z]+)"#, ci: false)
        case "create_reminder":
            a["title"] = first(#"remind me (?:to\s+)?(.+?)(?:\s+(?:tomorrow|today|tonight|at|in|on|next|when)\b|$)"#) ?? u
            if let w = when { a["when"] = w }
        case "create_event":
            a["title"] = first(#"(?:schedule|book|add|create)\s+(?:an? )?(.+?)(?:\s+(?:tomorrow|today|at|on|next|with)\b|$)"#) ?? u
            if let w = when { a["when"] = w }
        case "find_event":
            a["query"] = first(#"(?:when is|when's|what time is|find)\s+(?:my\s+)?(.+?)\??$"#) ?? u
        case "search_memory":
            a["query"] = u
        default: break
        }
        return a.compactMapValues { $0 }
    }
}

extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }
