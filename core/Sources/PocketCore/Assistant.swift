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

/// How a follow-up utterance was treated against pending message drafts. Present only
/// when the deterministic draft path ran, which distinguishes it from classifier routing.
public enum FollowUpOutcome: String, Sendable, Equatable {
    case completed, updated, cancelled, kept, disambiguated
}

public struct AssistantTurn: Sendable {
    public var reply: Reply
    public var decisions: [ReflexDecision]
    public var remembered: [MemoryFact]
    /// A retained or updated incomplete message draft, if this turn ended in message clarification.
    public var pendingDraft: MessageDraft? = nil
    /// Drafts this turn resolved into a staged card or cancelled. The caller drops them.
    public var consumedDrafts: [UserRequestID] = []
    /// Set when the deterministic follow-up path handled the utterance.
    public var followUp: FollowUpOutcome? = nil
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

    public func handle(_ utterance: String, now: Date = Date(), sharedText: String? = nil,
                       pendingDrafts: [MessageDraft] = []) async throws -> AssistantTurn {
        if let sharedText, sharedText.count > ActionValidation.sharedTextLimit {
            throw EffectError.invalidEdit("Shared text exceeds 24,000 characters. Choose a smaller excerpt.")
        }
        if MessageCommand.isExplicitMessageRequest(utterance),
           let issue = ActionValidation.requestIssue(capabilityID: "imessage_send", utterance: utterance) {
            return AssistantTurn(reply: .clarify(issue.question), decisions: [], remembered: [])
        }
        var decisions: [ReflexDecision] = []
        let requestID = UserRequestID()
        var readResult: ReadResult?
        var pendingDraft: MessageDraft?
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

        if !pendingDrafts.isEmpty {
            switch MessageFollowUp.resolve(utterance, drafts: pendingDrafts, now: now) {
            case .none:
                ActionDiagnostics.shared.record(requestID: requestID, phase: .followUp, code: .followUpNewRequest)
            case .cancelled(let id):
                ActionDiagnostics.shared.record(requestID: requestID, phase: .followUp, code: .followUpCancelled)
                let result = EffectResult(attemptID: AttemptID(), phase: .settled(.cancelled(.userCard)),
                                          summary: "Cancelled. Nothing was sent or saved.")
                return AssistantTurn(reply: .acted(result), decisions: decisions, remembered: remembered,
                                     consumedDrafts: [id], followUp: .cancelled, corrections: corrections)
            case .clarifyKeep(let q):
                ActionDiagnostics.shared.record(requestID: requestID, phase: .followUp, code: .followUpKept)
                return AssistantTurn(reply: .clarify(q), decisions: decisions, remembered: remembered,
                                     followUp: .kept, corrections: corrections)
            case .disambiguate(let q):
                ActionDiagnostics.shared.record(requestID: requestID, phase: .followUp, code: .followUpDisambiguated)
                return AssistantTurn(reply: .clarify(q), decisions: decisions, remembered: remembered,
                                     followUp: .disambiguated, corrections: corrections)
            case .updated(let retained):
                ActionDiagnostics.shared.record(requestID: requestID, capability: retained.channel?.capabilityID,
                                                phase: .followUp, code: .followUpUpdated)
                return AssistantTurn(reply: .clarify(retained.question()), decisions: decisions, remembered: remembered,
                                     pendingDraft: retained, followUp: .updated, corrections: corrections)
            case .completed(let complete):
                return try await stageCompletedDraft(complete, decisions: decisions, remembered: remembered,
                                                     corrections: corrections, sharedText: sharedText)
            }
        }

        let route = try await reflex.decide(OptionSets.route, context: ctx)
        decisions.append(route)
        if let data = HTMLViz.requestData(in: utterance, sharedText: sharedText),
           let reply = HTMLViz.reply(text: data) {
            ActionDiagnostics.shared.record(requestID: requestID, capability: "html_viz", phase: .routing,
                                            code: .explicitChartRendered)
            return AssistantTurn(reply: .local(reply), decisions: decisions, remembered: remembered,
                                 action: PlannedAction(tool: ActionPlanner.toolPrefix + "html_viz", args: ["data": data]),
                                 corrections: corrections)
        }
        // No registry: an explicit message command on a non-tool route still bypasses
        // chat generation and stages or retains through the compiled message catalog.
        if skills == nil, route.chosen.id != "tool", ActionPlanner.isExplicitMessageRequest(utterance) {
            var planned: PlannedAction?
            let reply = try await sendMessageToolPath(utterance, ctx: ctx, requestID: requestID, sharedText: sharedText,
                                                      decisions: &decisions, planned: &planned, read: &readResult,
                                                      draft: &pendingDraft, now: now, toolEscalated: route.escalated)
            return AssistantTurn(reply: reply, decisions: decisions, remembered: remembered, pendingDraft: pendingDraft,
                                 action: planned, corrections: corrections)
        }
        let lmem = localMemory(mem)
        var skillAction: PlannedAction?   // explicit app/feature request + confident skillPick; no registry = no-op
        if let r = try await skillOverride(utterance, ctx: ctx, route: route, requestID: requestID, sharedText: sharedText,
                                           decisions: &decisions, planned: &skillAction, read: &readResult,
                                           now: now, draft: &pendingDraft) {
            return AssistantTurn(reply: r, decisions: decisions, remembered: remembered, pendingDraft: pendingDraft,
                                 action: skillAction,
                                 cloudPromptSent: readResult?.cloudPromptSent,
                                 corrections: corrections,
                                 cloudWithheldForSensitivity: readResult?.withheldForSensitivity ?? false)
        }

        if let sharedText, route.chosen.id != "tool" {
            let result = try await reason(utterance, text: sharedText)
            decisions.append(contentsOf: result.decisions)
            let reply: Reply = result.provider.map { .cloud(result.text, provider: $0) } ?? .local(result.text)
            return AssistantTurn(reply: reply, decisions: decisions, remembered: remembered,
                                 cloudPromptSent: result.cloudPromptSent, corrections: corrections,
                                 cloudWithheldForSensitivity: result.withheldForSensitivity)
        }

        switch route.chosen.id {
        case "tool":
            var planned: PlannedAction?
            let reply = try await toolPath(utterance, ctx: ctx, requestID: requestID, sharedText: sharedText, decisions: &decisions,
                                           planned: &planned, read: &readResult, now: now, draft: &pendingDraft)
            return AssistantTurn(reply: reply, decisions: decisions, remembered: remembered, pendingDraft: pendingDraft,
                                 action: planned,
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
                do {
                    let ans = try await turn.send(on: config.chain)
                    return AssistantTurn(reply: .cloud(turn.restore(ans.text), provider: "\(ans.provider) · \(ans.model)"), decisions: decisions,
                                         remembered: remembered, cloudPromptSent: turn.sentText, corrections: corrections)
                } catch {
                    if CloudBrainChain.isCancellation(error) { throw error }
                    do {
                        let can = try await reflex.decide(OptionSets.answerability, context: "\(mem)User: \(utterance)")
                        decisions.append(can)
                        let text: String
                        if can.chosen.id == "yes" {
                            text = "Cloud unavailable. On-device answer: " + (try await reflex.engine.generate(
                                prompt: Self.localPrompt(utterance, mem: lmem), maxTokens: 200, temperature: 0.3)).trimmed
                        } else {
                            text = "The cloud providers could not answer, and I'm not confident enough to answer on device. Please try again later."
                        }
                        return AssistantTurn(reply: .offlineFallback(text), decisions: decisions, remembered: remembered,
                                             cloudPromptSent: turn.sentText, corrections: corrections)
                    } catch {
                        throw CloudRequestFailure(sentText: turn.sentText, causedBy: error)
                    }
                }
            case .withheld:
                // The early sensitivity card may have said ok; nothing was sent and the badge stays truthful.
                let a = try await reflex.engine.generate(prompt: Self.localPrompt(utterance, mem: lmem), maxTokens: 200, temperature: 0.3)
                return AssistantTurn(reply: .local(a.trimmed), decisions: decisions, remembered: remembered, corrections: corrections,
                                     cloudWithheldForSensitivity: true)
            }
        }
    }

    func toolPath(_ utterance: String, ctx: String, requestID: UserRequestID, sharedText: String?, decisions: inout [ReflexDecision],
                  planned: inout PlannedAction?, read: inout ReadResult?, now: Date,
                  draft: inout MessageDraft?) async throws -> Reply {
        let tool = try await reflex.decide(OptionSets.toolChoice, context: ctx)
        decisions.append(tool)

        // BF-1: an explicit email request stays a compiled Mail handoff. toolChoice has no send_email option.
        if tool.chosen.id == "send_message", ActionPlanner.isExplicitEmailRequest(utterance),
           let reg = skills, let compose = reg.skill(id: "email_compose") {
            return try await planSkillCore(utterance, ctx: ctx, registry: reg, requestID: requestID, sharedText: sharedText,
                                           decisions: &decisions, planned: &planned, read: &read,
                                           fallThrough: false, preselected: compose,
                                           explicitDraftOverride: tool.escalated, now: now, draft: &draft)
                ?? .clarify("What would you like me to do?")
        }
        // An explicit message command never runs an unrelated trained tool: route it to
        // message planning even when toolChoice missed. The decisions stay on the turn
        // as evidence of the miss.
        if ActionPlanner.isExplicitMessageRequest(utterance),
           tool.chosen.id != "send_message", (tool.chosen.id != "none" || skills == nil) {
            ActionDiagnostics.shared.record(requestID: requestID, phase: .routing, code: .explicitMessageMatch)
            if let reg = skills, let channel = MessageChannel.parse(in: utterance),
               let channelSkill = reg.skill(id: channel.capabilityID) {
                ActionDiagnostics.shared.record(requestID: requestID, capability: channel.capabilityID,
                                                phase: .routing, code: .explicitMessageRoutedSkill)
                return try await planSkillCore(utterance, ctx: ctx, registry: reg, requestID: requestID, sharedText: sharedText,
                                               decisions: &decisions, planned: &planned, read: &read,
                                               fallThrough: false, preselected: channelSkill,
                                               explicitDraftOverride: true, now: now, draft: &draft)
                    ?? .clarify("What would you like me to do?")
            }
            if skills == nil, MessageChannel.parse(in: utterance) == nil {
                let (retained, question) = MessageDraft.retain(utterance: utterance, requestID: requestID,
                                                               lowConfidence: true, now: now)
                draft = retained
                return .clarify(question)
            }
            return try await sendMessageToolPath(utterance, ctx: ctx, requestID: requestID, sharedText: sharedText,
                                                 decisions: &decisions, planned: &planned, read: &read,
                                                 draft: &draft, now: now, toolEscalated: true)
        }
        if let reg = skills, ActionPlanner.shouldUseSkills(tool: tool, utterance: utterance, registry: reg) {   // open-world skills
            return try await planSkill(utterance, ctx: ctx, registry: reg, requestID: requestID, sharedText: sharedText,
                                       decisions: &decisions, planned: &planned, read: &read, now: now, draft: &draft)
        }
        guard tool.chosen.id != "none" else { return .clarify("What would you like me to do?") }
        if let id = CapabilityCatalog.capabilityID(forTool: tool.chosen.id),
           let issue = ActionValidation.requestIssue(capabilityID: id, utterance: utterance) { return .clarify(issue.question) }

        if tool.chosen.id == "send_message" {
            return try await sendMessageToolPath(utterance, ctx: ctx, requestID: requestID, sharedText: sharedText,
                                                 decisions: &decisions, planned: &planned, read: &read,
                                                 draft: &draft, now: now, toolEscalated: tool.escalated)
        }
        var args = ArgumentExtractor.heuristic(tool: tool.chosen.id, utterance: utterance)
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

    /// Trained-tool message planning. A complete parse stages a confirmable card;
    /// anything else retains a typed draft and asks exactly what is missing.
    func sendMessageToolPath(_ utterance: String, ctx: String, requestID: UserRequestID, sharedText: String?,
                             decisions: inout [ReflexDecision], planned: inout PlannedAction?,
                             read: inout ReadResult?, draft: inout MessageDraft?, now: Date,
                             toolEscalated: Bool) async throws -> Reply {
        if let issue = ActionValidation.requestIssue(capabilityID: "imessage_send", utterance: utterance) {
            return .clarify(issue.question)
        }
        let parts = MessageDraft.messageArgs(utterance)
        let who = parts.contact
        let body = parts.body
        let channel = MessageChannel.parse(in: utterance)
        guard let channel, who != nil, body != nil else {
            var retained = MessageDraft(requestID: requestID, contact: who, channel: channel, body: body,
                                        lowConfidence: toolEscalated, created: now)
            retained.lastAsked = retained.missingField
            draft = retained
            ActionDiagnostics.shared.record(requestID: requestID, capability: channel?.capabilityID,
                                            phase: .draft, code: .draftCreated)
            return .clarify(retained.question())
        }
        ActionDiagnostics.shared.record(requestID: requestID, capability: channel.capabilityID,
                                        phase: .routing, code: .explicitMessageRoutedTool)
        let toolID = channel == .imessage ? "send_message" : ActionPlanner.toolPrefix + channel.capabilityID
        let action = PlannedAction(tool: toolID, args: ["contact": who!, "body": body!])
        planned = action
        let conf = try await reflex.decide(OptionSets.confirmBeforeAct,
                                           context: "\(ctx)\nPlanned action: \(action.tool) body=\(body!), contact=\(who!)")
        decisions.append(conf)
        guard let ledger, let effects else {
            return .clarify("Actions are unavailable on this build. Nothing was done.")
        }
        let capability = CapabilityCatalog.resolve(id: channel.capabilityID, skill: skills?.skill(id: channel.capabilityID))
        let result = try await EffectSession(ledger: ledger, effects: effects).evaluate(
            requestID: requestID, capability: capability, raw: action,
            modelAskedConfirm: conf.chosen.id == "confirm", explicitDraft: toolEscalated)
        return Self.reply(from: result, read: &read, decisions: &decisions)
    }

    /// Stages a follow-up-completed draft through the same ledger session as any
    /// other action. The card still needs an explicit Confirm; nothing auto-sends.
    func stageCompletedDraft(_ draft: MessageDraft, decisions: [ReflexDecision], remembered: [MemoryFact],
                             corrections: [(old: MemoryFact, new: MemoryFact)],
                             sharedText: String?) async throws -> AssistantTurn {
        var decisions = decisions
        var read: ReadResult?
        guard let contact = draft.contact, let channel = draft.channel, let body = draft.body else {
            return AssistantTurn(reply: .clarify(draft.question()), decisions: decisions, remembered: remembered,
                                 pendingDraft: draft, followUp: .updated, corrections: corrections)
        }
        guard let ledger, let effects else {
            return AssistantTurn(reply: .clarify("Actions are unavailable on this build. Nothing was done."),
                                 decisions: decisions, remembered: remembered,
                                 pendingDraft: draft, followUp: .updated, corrections: corrections)
        }
        let capID = channel.capabilityID
        let action = PlannedAction(tool: ActionPlanner.toolPrefix + capID, args: ["contact": contact, "body": body])
        let capability = CapabilityCatalog.resolve(id: capID, skill: skills?.skill(id: capID))
        let result = try await EffectSession(ledger: ledger, effects: effects).evaluate(
            requestID: draft.requestID, capability: capability, raw: action,
            modelAskedConfirm: false, explicitDraft: draft.lowConfidence)
        let reply = Self.reply(from: result, read: &read, decisions: &decisions)
        ActionDiagnostics.shared.record(requestID: draft.requestID, capability: capID,
                                        phase: .draft, code: .draftStaged)
        return AssistantTurn(reply: reply, decisions: decisions, remembered: remembered,
                             consumedDrafts: [draft.requestID], followUp: .completed, action: action,
                             corrections: corrections)
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
                var publicArgs = args
                let sharedText = publicArgs.removeValue(forKey: "_sharedText")
                return try await self.execute(PlannedAction(tool: ActionPlanner.toolPrefix + action.capabilityID, args: publicArgs), sharedText: sharedText)
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
        // The full time expression is kept together; InstantParser refuses a range, a second instant, a named
        // zone or an explicit past time instead of letting extraction keep only a supported-looking prefix.
        let when = SkillArgs.time(u)
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
            let contactPattern = #"(?:(?i:text|sms|whatsapp|message|msg|dm|ping|tell|send)\s+(?i:(?:(?:an?\s+)?(?:message|text|sms|dm)\s+to\s+|to\s+)?)|(?i:reply to|respond to|write to)\s+)([\p{L}][\p{L}\p{N}_.’'-]*(?: (?!(?:He|She|They|We|You|It|Meet|Please|Thanks|Hello|Hi|Hey|On|At|In|Saying|That|Instagram|WhatsApp)\b)[A-Z][a-z]+)?)"#
            var rest: String?
            if let re = try? NSRegularExpression(pattern: contactPattern),
               let m = re.firstMatch(in: u, range: NSRange(u.startIndex..., in: u)),
               let contact = Range(m.range(at: 1), in: u), let full = Range(m.range, in: u) {
                let name = String(u[contact]).trimmed
                let firstWord = name.split(separator: " ").first.map(String.init) ?? ""
                if !SkillArgs.notNames.contains(firstWord.lowercased()),
                   firstWord.range(of: #"['’](?:ll|m|ve|d|re|s|t)$"#, options: [.regularExpression, .caseInsensitive]) == nil {
                    a["contact"] = name
                    rest = String(u[full.upperBound...]).trimmed
                }
            }
            var body = rest ?? ""
            // Recipient-first commands ("send Dana a message saying hi") carry the
            // message noun after the name; it is not body text.
            body = first(#"^(?:an?\s+(?:(?:WhatsApp|Instagram|Twitter|X|iMessage|SMS)\s+)?(?:dm|message|text)\b\s*(?=(?:saying|that says|to say|with the message|that\b|:|on\b|via\b|$)))?([\s\S]*)$"#, in: body) ?? body
            body = first(#"^(?:on|via|using)\s+(?:Instagram|WhatsApp|Twitter|X|iMessage|SMS)(?:\s+|$)([\s\S]*)$"#, in: body) ?? body
            body = first(#"^(?:(?:on|via)\s+(?:Instagram|WhatsApp|Twitter|X|iMessage|SMS)\s+)?(?:(?:that says|with the message|to say|saying|that)\b|:)\s*([\s\S]*)$"#, in: body) ?? body
            if (body.first == "\"" && body.last == "\"") || (body.first == "“" && body.last == "”"), body.count >= 2 {
                body = String(body.dropFirst().dropLast())
            }
            a["body"] = body.trimmed
        case "lookup_contact":
            a["contact"] = first(#"([A-Z][a-z]+(?: [A-Z][a-z]+)?)'s"#, ci: false) ?? first(#"(?i:call|for|of)\s+([A-Z][a-z]+)"#, ci: false)
        case "create_reminder":
            a["title"] = first(#"remind me (?:to\s+)?(.+?)(?:\s+(?:(?:the\s+)?day\s+after\s+tomorrow|tomorrow|today|tonight|at|in|on|next|when)\b|$)"#) ?? u
            if let w = when { a["when"] = w }
        case "create_event":
            a["title"] = first(#"(?:schedule|book|add|create)\s+(?:an? )?(.+?)(?:\s+(?:(?:the\s+)?day\s+after\s+tomorrow|tomorrow|today|at|on|next|with)\b|$)"#) ?? u
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
