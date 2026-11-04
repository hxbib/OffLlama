import Foundation

/// Read-only lookups used by planning. Effects go through `PhoneEffects` and the ledger; there is deliberately no
/// `perform` on this protocol, so no old caller can execute an effect around the claim.
public protocol ActionExecutor: Sendable {
    func searchContacts(_ query: String) async throws -> [String]
    func searchEvents(_ query: String) async throws -> [String]
}

public struct PlannedAction: Sendable, Equatable, Codable {
    public var tool: String               // OptionSets.toolChoice ids
    public var args: [String: String]
    public init(tool: String, args: [String: String]) { self.tool = tool; self.args = args }
}

public enum Reply: Sendable, Equatable {
    case local(String)
    case cloud(String, provider: String)
    case acted(EffectResult)
    case needsConfirmation(DraftCard)
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
    /// True when cloud-bound text was kept on device (sensitive, uncertain, or the privacy check failed): the turn was
    /// answered locally and nothing was sent. Drives the "Kept on device · nothing sent" badge.
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

/// One per-turn snapshot: a settings change mid-request cannot swap the chain or placeholder mapping.
struct CloudConfiguration: Sendable {
    let chain: CloudBrainChain
    let scrubber: PrivacyScrubber
}

public final class Assistant: @unchecked Sendable {
    public let reflex: Reflex
    public let memory: MemoryStore
    public let actions: ActionExecutor
    /// One ledger, one effects adapter. Both paths (model act and confirm) use the same session.
    public let ledger: EffectLedger?
    public let effects: PhoneEffects?
    private let cloudSettingsLock = NSLock()
    private var configuredCloud: CloudBrainChain
    private var configuredScrubber = PrivacyScrubber()
    public var cloud: CloudBrainChain {
        get { cloudSettingsLock.withLock { configuredCloud } }
        set { cloudSettingsLock.withLock { configuredCloud = newValue } }
    }
    public var isOnline: () -> Bool
    public var scrubber: PrivacyScrubber {
        get { cloudSettingsLock.withLock { configuredScrubber } }
        set { cloudSettingsLock.withLock { configuredScrubber = newValue } }
    }
    /// Char budget of the always-injected memory profile in local prompts (0 = off). Small: the 1B context stays short.
    public var profileMaxChars = 600
    /// Char budget of the profile sent to the cloud on escalation, after scrubbing (0 = never send the profile).
    public var cloudProfileMaxChars = 400
    /// Open-world skill registry (Skills.swift, ActionPlanner.swift). nil = today's six-tool behaviour, unchanged.
    public var skills: SkillRegistry? = nil
    public var skillRunner: SkillRunner? = nil   // runs `skill:` actions on the device (iOS IOSSkillRunner)

    public init(reflex: Reflex, memory: MemoryStore, actions: ActionExecutor, ledger: EffectLedger? = nil,
                effects: PhoneEffects? = nil, cloud: CloudBrainChain = .init([]), isOnline: @escaping () -> Bool = { false }) {
        self.reflex = reflex; self.memory = memory; self.actions = actions; self.ledger = ledger
        self.effects = effects; self.configuredCloud = cloud; self.isOnline = isOnline
    }

    func memoryContext(_ q: String) async throws -> [MemoryFact] {
        try await memory.retrieve(q, k: 4).map(\.fact)
    }

    /// Memory block for local generation: profile one-pager (bounded) + retrieved facts. Reflex decision contexts are unchanged.
    func localMemory(_ mem: String) -> String {
        guard profileMaxChars > 0, let p = try? memory.profileOnePager(maxChars: profileMaxChars), !p.isEmpty else { return mem }
        return p + "\n" + mem
    }

    /// Captures the chain and scrubber under one lock, then adds remembered entity names. Call once per turn.
    func cloudConfiguration() -> CloudConfiguration {
        let (chain, base) = cloudSettingsLock.withLock { (configuredCloud, configuredScrubber) }
        var scrubber = base
        scrubber.knownNames = Array(Set(scrubber.knownNames + ((try? memory.entityNames()) ?? [])))
        return CloudConfiguration(chain: chain, scrubber: scrubber)
    }

    public func handle(_ utterance: String, now: Date = Date()) async throws -> AssistantTurn {
        var decisions: [ReflexDecision] = []
        let requestID = UserRequestID()
        var readResult: ReadResult?
        let facts = try await memoryContext(utterance)
        let mem = MemoryDisclosure.local.render(facts)
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
        var skillAction: PlannedAction?   // explicit app/feature request + confident skillPick; no registry = no-op
        if let r = try await skillOverride(utterance, ctx: ctx, route: route, requestID: requestID,
                                           decisions: &decisions, planned: &skillAction, read: &readResult) {
            return AssistantTurn(reply: r, decisions: decisions, remembered: remembered, action: skillAction,
                                 cloudPromptSent: readResult?.cloudPromptSent,
                                 corrections: corrections,
                                 cloudWithheldForSensitivity: readResult?.withheldForSensitivity ?? false)
        }

        switch route.chosen.id {
        case "tool":
            var planned: PlannedAction?
            let reply = try await toolPath(utterance, ctx: ctx, requestID: requestID, decisions: &decisions,
                                           planned: &planned, read: &readResult)
            return AssistantTurn(reply: reply, decisions: decisions, remembered: remembered, action: planned,
                                 cloudPromptSent: readResult?.cloudPromptSent, corrections: corrections,
                                 cloudWithheldForSensitivity: readResult?.withheldForSensitivity ?? false)
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
            let config = cloudConfiguration()
            guard online, !config.chain.brains.isEmpty else {
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
            let profile = cloudProfileMaxChars > 0
                ? ((try? memory.profileOnePager(maxChars: cloudProfileMaxChars, redactSensitive: true)) ?? "")
                : ""
            switch try await CloudTurnComposer.prepareReply(profile: profile, facts: facts, utterance: utterance,
                                                             scrubber: config.scrubber, reflex: reflex) {
            case .prepared(let turn):
                let ans = try await turn.send(on: config.chain)
                return AssistantTurn(reply: .cloud(turn.restore(ans.text), provider: "\(ans.provider) · \(ans.model)"), decisions: decisions,
                                     remembered: remembered, cloudPromptSent: turn.sentText, corrections: corrections)
            case .withheld:
                // The early sensitivity card may have said ok; nothing was sent and the badge stays truthful.
                let a = try await reflex.engine.generate(prompt: Self.localPrompt(utterance, mem: lmem), maxTokens: 200, temperature: 0.3)
                return AssistantTurn(reply: .local(a.trimmed), decisions: decisions, remembered: remembered, corrections: corrections,
                                     cloudWithheldForSensitivity: true)
            }
        }
    }

    func toolPath(_ utterance: String, ctx: String, requestID: UserRequestID, decisions: inout [ReflexDecision],
                  planned: inout PlannedAction?, read: inout ReadResult?) async throws -> Reply {
        let tool = try await reflex.decide(OptionSets.toolChoice, context: ctx)
        decisions.append(tool)

        // BF-1: an explicit email request stays a compiled Mail handoff. toolChoice has no send_email option.
        if tool.chosen.id == "send_message", ActionPlanner.isExplicitEmailRequest(utterance),
           let reg = skills, let compose = reg.skill(id: "email_compose") {
            return try await planSkillCore(utterance, ctx: ctx, registry: reg, requestID: requestID,
                                           decisions: &decisions, planned: &planned, read: &read,
                                           fallThrough: false, preselected: compose,
                                           explicitDraftOverride: tool.escalated)
                ?? .clarify("What would you like me to do?")
        }
        if let reg = skills, ActionPlanner.shouldUseSkills(tool: tool, utterance: utterance, registry: reg) {   // open-world skills
            return try await planSkill(utterance, ctx: ctx, registry: reg, requestID: requestID,
                                       decisions: &decisions, planned: &planned, read: &read)
        }
        guard tool.chosen.id != "none" else { return .clarify("What would you like me to do?") }
        var args = ArgumentExtractor.heuristic(tool: tool.chosen.id, utterance: utterance)

        if tool.chosen.id == "send_message" {
            guard let who = args["contact"], !who.isEmpty else { return .clarify("Who should I message?") }
            guard let body = args["body"], !body.isEmpty else { return .clarify("What should I say to \(who)?") }
        }
        if tool.chosen.id == "lookup_contact", (args["contact"] ?? "").isEmpty {
            return .clarify("Who should I look up?")
        }
        if tool.chosen.id == "lookup_contact", let who = args["contact"] {
            let cands = try await actions.searchContacts(who)
            guard !cands.isEmpty else { return .clarify("I couldn't find \(who) in your contacts.") }
            if cands.count > 1 {
                let d = try await reflex.decide(OptionSets.contactPick(candidates: cands), context: ctx)
                decisions.append(d)
                guard d.chosen.id != "ask" else { return .clarify("Which \(who)? " + cands.joined(separator: ", ")) }
                return .local(d.chosen.label)
            }
            return .local(cands[0])
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
            return .local("From memory: " + hits.map { $0.fact.text }.joined(separator: "; "))
        }
        if action.tool == "find_event" {
            if let ev = args["event"] { return .local(ev) }
            let hits = try await actions.searchEvents(args["query"] ?? utterance)
            return .local(hits.first ?? "Nothing matching on your calendar in the next 30 days.")
        }
        guard let capID = CapabilityCatalog.capabilityID(forTool: action.tool) else {
            return .clarify("I can't do that on this phone yet.")
        }
        let conf = try await reflex.decide(OptionSets.confirmBeforeAct, context: "\(ctx)\nPlanned action: \(action.tool) \(args.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")
        decisions.append(conf)
        guard let ledger, let effects else {
            return .clarify("Actions are unavailable on this build. Nothing was done.")
        }
        let capability = CapabilityCatalog.resolve(id: capID, skill: skills?.skill(id: capID))
        let result = try await EffectSession(ledger: ledger, effects: effects).evaluate(
            requestID: requestID, capability: capability, raw: action,
            modelAskedConfirm: conf.chosen.id == "confirm", explicitDraft: tool.escalated)
        return Self.reply(from: result, read: &read, decisions: &decisions)
    }

    // MARK: effect recovery and confirmation

    /// Read-only launch recovery. It never performs an effect and never replays a claimed row.
    public func recoverEffects() throws -> LaunchRecovery {
        guard let ledger else { throw EffectError.ledgerUnavailable }
        return try ledger.recover(now: Date())
    }

    public func confirmEffect(_ attemptID: AttemptID, edits: [DraftEdit] = [], expectedRevision: Int? = nil) async throws -> SessionResult {
        guard let ledger, let effects else { throw EffectError.ledgerUnavailable }
        guard let record = try ledger.load(attemptID) else {
            return .ignoredTerminal(EffectResult(attemptID: attemptID, phase: .ambiguous(.claimedWithoutReceipt),
                                                 summary: "This attempt no longer exists. Nothing was done."))
        }
        if CapabilityCatalog.isReplyOnly(record.capabilityID) {
            let session = EffectSession(ledger: ledger, effects: effects)
            return try await session.confirmRead(attemptID: attemptID, expectedRevision: expectedRevision) { action in
                let args = Self.stringArguments(action)
                return try await self.execute(PlannedAction(tool: ActionPlanner.toolPrefix + action.capabilityID, args: args))
            }
        }
        return try await EffectSession(ledger: ledger, effects: effects)
            .confirm(attemptID: attemptID, edits: edits, expectedRevision: expectedRevision)
    }

    public func editEffect(_ attemptID: AttemptID, edits: [DraftEdit], expectedRevision: Int) async throws -> DraftCard {
        guard let ledger, let effects else { throw EffectError.ledgerUnavailable }
        return try await EffectSession(ledger: ledger, effects: effects)
            .edit(attemptID: attemptID, edits: edits, expectedRevision: expectedRevision)
    }

    public func cancelEffect(_ attemptID: AttemptID) throws -> EffectResult {
        guard let ledger, let effects else { throw EffectError.ledgerUnavailable }
        return try EffectSession(ledger: ledger, effects: effects).cancel(attemptID: attemptID)
    }

    static func stringArguments(_ action: BoundAction) -> [String: String] {
        var out: [String: String] = [:]
        for (name, value) in action.arguments {
            switch value {
            case .text(let s), .place(let s), .shortcutName(let s): out[name] = s
            case .contact(let b): out[name] = b.displayName
            case .contactQuery(let q): out[name] = q
            case .instant(let d): out[name] = ISO8601DateFormatter().string(from: d)
            case .url(let u): out[name] = u.absoluteString
            }
        }
        return out
    }

    static func reply(from result: SessionResult, read: inout ReadResult?, decisions: inout [ReflexDecision]) -> Reply {
        switch result {
        case .staged(let card):
            return .needsConfirmation(card)
        case .finished(let effect), .ignoredTerminal(let effect):
            return .acted(effect)
        case .read(let result):
            read = result
            decisions.append(contentsOf: result.decisions)
            return result.provider.map { Reply.cloud(result.text, provider: $0) } ?? .local(result.text)
        }
    }


    static func localPrompt(_ q: String, mem: String) -> String {
        "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\nYou are a concise, warm personal assistant running fully offline on the user's phone. \(mem)<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n\(q)<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n"
    }
}

/// Cheap argument extraction; the on-device model refines it when needed (app side). Times stay as raw phrases
/// and are resolved by NSDataDetector on iOS.
public enum ArgumentExtractor {
    public static func heuristic(tool: String, utterance u: String) -> [String: String] {
        var a: [String: String] = [:]
        func first(_ p: String, in s: String, ci: Bool = true) -> String? {
            guard let re = try? NSRegularExpression(pattern: p, options: ci ? .caseInsensitive : []),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: s) else { return nil }
            return String(s[r]).trimmed
        }
        func first(_ p: String, ci: Bool = true) -> String? { first(p, in: u, ci: ci) }
        // Keep an explicit zone/city qualifier in the phrase. The binder then refuses to guess rather than
        // silently dropping "Berlin time" before the instant is frozen.
        let when = first(#"\b((?:tomorrow|today|tonight|next \w+|on \w+day|at \d{1,2}(?::\d{2})?\s?(?:am|pm)?|in \d+ (?:minutes?|hours?|days?))(?:\s(?:at|by) \d{1,2}(?::\d{2})?\s?(?:am|pm)?)?(?:\s+(?:UTC|GMT|EST|EDT|CST|CDT|MST|MDT|PST|PDT|CET|CEST|BST|IST|JST|KST|AEST|AEDT|[A-Z][a-z]+ time|in [A-Z][a-z]+))?)"#)
        switch tool {
        case "send_email":
            let contactPattern = #"(?i:email|e-mail|mail)\s+(?:to\s+)?([A-Z][a-z]+(?: [A-Z][a-z]+)?)"#
            var rest: String?
            if let re = try? NSRegularExpression(pattern: contactPattern),
               let m = re.firstMatch(in: u, range: NSRange(u.startIndex..., in: u)),
               let contact = Range(m.range(at: 1), in: u), let full = Range(m.range, in: u) {
                a["contact"] = String(u[contact]).trimmed
                rest = String(u[full.upperBound...]).trimmed
            }
            if let subject = first(#"(?i:\bsubject\s*:?\s*)[“"]?([^”"\n]+)[”"]?"#) {
                a["subject"] = subject
            }
            var body = rest ?? ""
            body = first(#"^(?:(?:that says|with the message|to say|saying|that)\b|:)\s*([\s\S]*)$"#, in: body) ?? body
            if (body.first == "\"" && body.last == "\"") || (body.first == "“" && body.last == "”"), body.count >= 2 {
                body = String(body.dropFirst().dropLast())
            }
            a["body"] = body.trimmed
        case "send_message":
            let contactPattern = #"(?i:text|message|tell|send)\s+(?i:a message to\s+)?([A-Z][a-z]+(?: [A-Z][a-z]+)?)"#
            var rest: String?
            if let re = try? NSRegularExpression(pattern: contactPattern),
               let m = re.firstMatch(in: u, range: NSRange(u.startIndex..., in: u)),
               let contact = Range(m.range(at: 1), in: u), let full = Range(m.range, in: u) {
                a["contact"] = String(u[contact]).trimmed
                rest = String(u[full.upperBound...]).trimmed
            }
            var body = rest ?? ""
            body = first(#"^(?:(?:on|via)\s+(?:Instagram|WhatsApp|Twitter|X|iMessage|SMS)\s+)?(?:(?:that says|with the message|to say|saying|that)\b|:)\s*([\s\S]*)$"#, in: body) ?? body
            if (body.first == "\"" && body.last == "\"") || (body.first == "“" && body.last == "”"), body.count >= 2 {
                body = String(body.dropFirst().dropLast())
            }
            a["body"] = body.trimmed
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
