import Foundation

/// Executes registry skills on the device (iOS: app/PocketGlimmer/Actions/SkillRunner.swift; a recorder in tests).
public protocol SkillRunner: Sendable {
    func run(_ skill: Skill, args: [String: String]) async throws -> String
}

/// Two-stage routing for open-world phone actions.
///
/// Stage 1 is the trained `route` decision; stage 2 the trained `toolChoice` (both unchanged). Only when toolChoice says
/// "none" (or is below tau, whose fallback is "none"), or the user explicitly names an app/feature the six tools do not
/// cover ("on Instagram", "alarm"), the planner retrieves top-k registry skills and asks the SAME 1B ONE dynamic
/// multiple-choice question (`skillPick`, built like `contactPick`): one forward pass, calibrated letter confidence,
/// tau gate. Below tau -> clarify with the top 3 skills, except an explicit message keeps its parsed draft.
/// Then args are extracted from the compiled catalog for compiled ids (never merged JSON), and the effect session
/// decides confirmation floor, binding, claim and receipt.
public enum ActionPlanner {
    public static let toolPrefix = "skill:"
    /// Native handlers that are ActionExecutor tools (SystemActions on iOS); everything else goes to the SkillRunner.
    public static let executorTools: Set<String> = ["send_message", "send_email", "create_reminder", "create_event",
                                                     "find_event", "lookup_contact", "search_memory"]

    /// Explicit app/feature words that a chosen trained tool cannot serve ("dm sam ON INSTAGRAM" -> toolChoice says
    /// send_message; "WAKE ME at 6" -> create_reminder). Only these tool/word pairs override; everything else keeps today's path.
    static let overridable: [String: [String]] = [
        "send_message": ["instagram", "insta", "ig", "twitter", "x dm", "on x", "whatsapp", "whats app", "facetime", "auto reply", "autoreply", "every reel", "email", "e-mail", "send email", "write an email"],
        "lookup_contact": ["facetime", "instagram", "twitter", "whatsapp"],
        "create_reminder": ["alarm", "wake me", "timer", "pomodoro", "auto reply", "autoreply", "every reel"],
        "create_event": ["alarm", "wake me", "timer"],
        "search_memory": ["recent emails", "last emails", "summarize emails", "chart", "graph", "visualize", "bar chart", "pdf", "battery", "storage", "weather"],
        "find_event": ["weather"],
    ]
    public static func explicitSkill(in utterance: String, registry: SkillRegistry, chosenTool: String) -> Skill? {
        guard let words = overridable[chosenTool] else { return nil }
        let u = SkillRegistry.norm(utterance)
        guard let w = words.first(where: { u.contains(SkillRegistry.norm($0)) }) else { return nil }
        let nw = SkillRegistry.norm(w)
        return registry.skills.first { s in s.aliases.contains { SkillRegistry.norm($0) == nw } }
    }

    /// Explicit app/feature requests that the trained `route` may send elsewhere ("chart these numbers" -> escalate_cloud,
    /// "how much battery" -> answer_local). Only then does the skill path get a chance BEFORE the routed branch; if
    /// skillPick is unsure, the routed branch runs unchanged (see `Assistant.skillOverride`).
    static let explicitRequest: [String] = ["instagram", "insta", "twitter", "whatsapp", "facetime", "uber", "spotify",
                                            "alarm", "wake me", "timer", "pomodoro", "flashlight", "do not disturb", "low power",
                                            "battery", "storage left", "chart", "graph", "visualize", "visualization",
                                            "my emails", "recent emails", "last emails", "these emails", "this document", "this pdf",
                                            "shortcut", "weather", "directions to", "auto reply", "every reel",
                                            "apple tv", "appletv", "tv app"]
    public static func isExplicitRequest(_ utterance: String) -> Bool {
        let u = SkillRegistry.norm(utterance)
        if isExplicitMessageRequest(utterance) { return true }
        if isExplicitEmailRequest(utterance) { return true }
        if u.range(of: #" (?:last|recent|latest) \d+ (?:e ?)?mails? "#, options: .regularExpression) != nil { return true }
        return explicitRequest.contains { u.contains(SkillRegistry.norm($0)) }
    }

    static func isExplicitMessageRequest(_ utterance: String) -> Bool {
        MessageCommand.isExplicitMessageRequest(utterance)
    }

    /// "Email Dana …" must not enter the trained `send_message` path. The frozen toolChoice set has no send_email.
    public static func isExplicitEmailRequest(_ utterance: String) -> Bool {
        SkillRegistry.norm(utterance).range(of: #"^ (?:please )?(?:email|e mail|mail|send (?:an? )?email|write (?:an? )?email) "#,
                                          options: .regularExpression) != nil
    }

    /// A clear reminder or calendar command, so a non-tool route or a wrong tool pick still reaches a reviewable
    /// card instead of generated chat. Questions, quoted text, negations and alarm/timer wording never match.
    public static func explicitToolCommand(_ utterance: String) -> String? {
        let raw = utterance.trimmed
        if raw.hasSuffix("?") || raw.contains("\"") || raw.contains("“") { return nil }
        let u = SkillRegistry.norm(utterance)
        if u.range(of: #" (?:don t|dont|do not|never|not|cancel|delete|remove|alarm|wake me|timer|pomodoro) "#,
                   options: .regularExpression) != nil { return nil }
        if u.range(of: #"^ (?:please )?(?:remind me|(?:set|add|create|make) (?:a |an )?(?:new )?reminder) "#,
                   options: .regularExpression) != nil { return "create_reminder" }
        if u.range(of: #"^ (?:please )?(?:schedule|book|add|create|put) "#, options: .regularExpression) != nil,
           u.range(of: #" (?:calendar|meeting|event|appointment) "#, options: .regularExpression) != nil {
            return "create_event"
        }
        return nil
    }

    /// Whether the skill path should run instead of today's toolChoice path.
    public static func shouldUseSkills(tool: ReflexDecision, utterance: String, registry: SkillRegistry) -> Bool {
        tool.chosen.id == "none" || explicitSkill(in: utterance, registry: registry, chosenTool: tool.chosen.id) != nil
            || (tool.chosen.id == "search_memory" && isExplicitRequest(utterance))   // "summarize my last 5 emails" is not recall
    }

    public static func candidates(_ utterance: String, registry: SkillRegistry, k: Int = 7) -> [Skill] {
        let hits = registry.retrieve(utterance, k: k)
        guard let top = hits.first?.score else { return [] }
        return hits.filter { $0.score >= 0.3 * top }.map(\.skill)
    }

    static func describe(_ args: [String: String]) -> String {
        args.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
    }
    static func list(_ names: [String]) -> String {
        names.count <= 1 ? (names.first ?? "") : names.dropLast().joined(separator: ", ") + " or " + names.last!
    }
}

extension Assistant {
    /// Open-world tool path. Appends its decisions (skillPick, confirmBeforeAct) and sets `planned`.
    public func planSkill(_ utterance: String, ctx: String, registry: SkillRegistry, requestID: UserRequestID, sharedText: String? = nil,
                          decisions: inout [ReflexDecision], planned: inout PlannedAction?,
                          read: inout ReadResult?, now: Date = Date(), draft: inout MessageDraft?) async throws -> Reply {
        try await planSkillCore(utterance, ctx: ctx, registry: registry, requestID: requestID, sharedText: sharedText, decisions: &decisions,
                                planned: &planned, read: &read, fallThrough: false, now: now, draft: &draft)
            ?? .clarify("What would you like me to do?")
    }

    /// Before the routed branch (route != tool): an explicit app/feature request gets ONE skillPick decision. Returns nil
    /// (caller continues with the trained route unchanged) unless the request is explicit AND skillPick clears tau.
    /// Explicit message commands always return a reply: a staged card or a retained typed
    /// draft, never a fall-through into chat generation.
    public func skillOverride(_ utterance: String, ctx: String, route: ReflexDecision, requestID: UserRequestID, sharedText: String? = nil,
                              decisions: inout [ReflexDecision], planned: inout PlannedAction?,
                              read: inout ReadResult?, now: Date = Date(), draft: inout MessageDraft?) async throws -> Reply? {
        guard let reg = skills, route.chosen.id != "tool", ActionPlanner.isExplicitRequest(utterance) else { return nil }
        return try await planSkillCore(utterance, ctx: ctx, registry: reg, requestID: requestID, sharedText: sharedText, decisions: &decisions,
                                       planned: &planned, read: &read, fallThrough: true, now: now, draft: &draft)
    }

    func planSkillCore(_ utterance: String, ctx: String, registry: SkillRegistry, requestID: UserRequestID, sharedText: String? = nil,
                       decisions: inout [ReflexDecision], planned: inout PlannedAction?,
                       read: inout ReadResult?, fallThrough: Bool, preselected: Skill? = nil,
                       explicitDraftOverride: Bool = false, now: Date = Date(),
                       draft: inout MessageDraft?) async throws -> Reply? {
        var skill: Skill
        var belowTau = explicitDraftOverride

        // BF-1: explicit "Email …" requests always use compiled email_compose, never the frozen message tool.
        let forced = preselected ?? (ActionPlanner.isExplicitEmailRequest(utterance) ? registry.skill(id: "email_compose") : nil)
        if let forced {
            skill = forced
        } else {
            let cands = ActionPlanner.candidates(utterance, registry: registry)
            guard !cands.isEmpty else {
                if ActionPlanner.isExplicitMessageRequest(utterance) {
                    let (retained, question) = MessageDraft.retain(utterance: utterance, requestID: requestID,
                                                                   lowConfidence: true, now: now)
                    if retained.isComplete {
                        return try await sendMessageToolPath(utterance, ctx: ctx, requestID: requestID,
                            sharedText: sharedText, decisions: &decisions, planned: &planned,
                            read: &read, draft: &draft, now: now, toolEscalated: true)
                    }
                    draft = retained
                    ActionDiagnostics.shared.record(requestID: requestID, capability: retained.channel?.capabilityID,
                                                    phase: .draft, code: .draftCreated)
                    return .clarify(question)
                }
                return fallThrough ? nil : .clarify("I can't do that on this phone yet. New abilities are a JSON skill away (docs/SKILLS.md).")
            }
            let pick = try await reflex.decide(OptionSets.skillPick(candidates: cands.map(\.optionLabel)), context: ctx)
            decisions.append(pick)
            if pick.chosen.id != "ask", let i = Int(pick.chosen.id.dropFirst()), i < cands.count {
                skill = cands[i]
                belowTau = pick.escalated
            } else if ActionPlanner.isExplicitMessageRequest(utterance) {
                // Below tau the old path clarified with choices and dropped the parse. A
                // complete explicit parse keeps its editable card through the normal flow;
                // anything else keeps a typed draft so the follow-up binds instead of
                // falling into chat.
                let (retained, question) = MessageDraft.retain(utterance: utterance, requestID: requestID,
                                                               lowConfidence: true, now: now)
                if retained.isComplete, let channel = retained.channel,
                   let channelSkill = registry.skill(id: channel.capabilityID) {
                    skill = channelSkill
                    belowTau = true
                } else if retained.isComplete {
                    return .clarify("This message needs the built-in message skill, which is missing. Nothing was done.")
                } else {
                    draft = retained
                    ActionDiagnostics.shared.record(requestID: requestID, capability: retained.channel?.capabilityID,
                                                    phase: .draft, code: .draftCreated)
                    return .clarify(question)
                }
            } else {
                if fallThrough { return nil }
                let choices = ActionPlanner.list(cands.prefix(3).map(\.title))
                return .clarify("Did you mean: \(choices)?")
            }
        }

        if ActionPlanner.isExplicitMessageRequest(utterance),
           MessageChannel.channel(forCapabilityID: skill.id) == nil
            || MessageChannel.channel(forCapabilityID: skill.id) != MessageChannel.parse(in: utterance) {
            return try await sendMessageToolPath(utterance, ctx: ctx, requestID: requestID, sharedText: sharedText,
                                                decisions: &decisions, planned: &planned, read: &read,
                                                draft: &draft, now: now, toolEscalated: true)
        }

        if let issue = ActionValidation.requestIssue(capabilityID: skill.id, utterance: utterance) { return .clarify(issue.question) }

        // Binding knowledge for a compiled id comes from the Swift catalog, never from a merged JSON file.
        let extractedFrom = CapabilityCatalog.current(id: skill.id).flatMap { _ in
            BuiltinSkills.all.first { $0.id == skill.id }
        } ?? skill
        let args = SkillArgs.extract(extractedFrom, utterance: utterance)
        let specs = CapabilityCatalog.current(id: skill.id)?.arguments ?? skill.argSchema
        if let missing = specs.first(where: { $0.required && (args[$0.name] ?? "").isEmpty }) {
            if let channel = MessageChannel.channel(forCapabilityID: skill.id) {
                var retained = MessageDraft(requestID: requestID,
                                            contact: MessageDraft.nonempty(args["contact"]),
                                            channel: channel,
                                            body: MessageDraft.nonempty(args["body"]),
                                            lowConfidence: belowTau, created: now)
                retained.lastAsked = retained.missingField
                draft = retained
                ActionDiagnostics.shared.record(requestID: requestID, capability: channel.capabilityID,
                                                phase: .draft, code: .draftCreated)
                return .clarify(retained.question())
            }
            return .clarify(SkillArgs.question(for: missing, skill: skill))
        }

        let action = PlannedAction(tool: ActionPlanner.toolPrefix + skill.id, args: args)
        planned = action
        let conf = try await reflex.decide(OptionSets.confirmBeforeAct, context: "\(ctx)\nPlanned action: \(action.tool) \(ActionPlanner.describe(args))")
        decisions.append(conf)

        let capability = CapabilityCatalog.resolve(id: skill.id, skill: skill)
        switch capability {
        case .replyOnly:
            guard let contract = CapabilityCatalog.current(id: skill.id) else {
                return .clarify("This read is not compiled into this build. Nothing was done.")
            }
            let needsConfirm = contract.confirmation == .always || conf.chosen.id == "confirm"
            if needsConfirm {
                guard let ledger, let effects else { return .clarify("Reads are unavailable on this build. Nothing was done.") }
                let card = try EffectSession(ledger: ledger, effects: effects).stageRead(
                    requestID: requestID, contract: contract, raw: action, sharedText: sharedText)
                return .needsConfirmation(card)
            }
            let result = try await execute(action, sharedText: sharedText)
            read = result
            decisions.append(contentsOf: result.decisions)
            return result.provider.map { Reply.cloud(result.text, provider: $0) } ?? .local(result.text)
        case .rejected(let rejected):
            return .clarify(EffectSession.rejectedSummary(rejected))
        case .compiled, .userHandoff:
            guard let ledger, let effects else {
                return .clarify("Actions are unavailable on this build. Nothing was done.")
            }
            let result = try await EffectSession(ledger: ledger, effects: effects).evaluate(
                requestID: requestID, capability: capability, raw: action,
                modelAskedConfirm: conf.chosen.id == "confirm", explicitDraft: belowTau)
            return Self.reply(from: result, read: &read, decisions: &decisions)
        }
    }

    private func argsFor(_ skill: Skill, _ utterance: String) -> [String: String] {
        SkillArgs.extract(skill, utterance: utterance)
    }

    /// Runs a reply-only read. Effect capabilities deliberately throw: callers must use confirmEffect/evaluate.
    public func execute(_ a: PlannedAction, sharedText: String? = nil) async throws -> ReadResult {
        if let sharedText, sharedText.count > ActionValidation.sharedTextLimit {
            throw EffectError.invalidEdit("Shared text exceeds 24,000 characters. Choose a smaller excerpt.")
        }
        if a.tool == "search_memory" {
            let hits = try await memory.retrieve(a.args["query"] ?? "", k: 3)
            return ReadResult(text: hits.isEmpty ? "You haven't told me that yet."
                                                 : "From memory: " + hits.map { $0.fact.text }.joined(separator: "; "))
        }
        if a.tool == "find_event" {
            if let ev = a.args["event"] { return ReadResult(text: ev) }
            let hits = try await actions.searchEvents(a.args["query"] ?? "")
            return ReadResult(text: hits.first ?? "Nothing matching on your calendar in the next 30 days.")
        }
        if a.tool == "lookup_contact" {
            let hits = try await actions.searchContacts(a.args["contact"] ?? "")
            return ReadResult(text: hits.first ?? "No contact found.")
        }
        guard a.tool.hasPrefix(ActionPlanner.toolPrefix) else {
            throw EffectError.effectRequiresConfirmation(a.tool)
        }
        let id = String(a.tool.dropFirst(ActionPlanner.toolPrefix.count))
        guard let skill = BuiltinSkills.all.first(where: { $0.id == id }) ?? (skills ?? SkillRegistry()).skill(id: id) else { return ReadResult(text: "Unknown skill \(id) · nothing done") }
        guard CapabilityCatalog.isReplyOnly(id) else { throw EffectError.effectRequiresConfirmation(id) }
        if let contract = CapabilityCatalog.current(id: id), let issue = ActionValidation.issues(contract: contract, args: a.args).first {
            return ReadResult(text: issue.question)
        }
        return try await readSkill(skill, action: a, sharedText: sharedText)
    }

    private func readSkill(_ skill: Skill, action: PlannedAction, sharedText: String?) async throws -> ReadResult {
        var args = action.args
        switch skill.id {
        case "email_digest":
            let shared = sharedText
            guard let shared else {
                return ReadResult(text: "OffLlama needs you to share the email text. Use a Share Sheet shortcut with the “OffLlama: handle text” action, then I can summarize it here.")
            }
            return try await reason("Summarize these emails in 3 short bullets: who wants what, and any deadline.", text: shared)
        case "analyze_document":
            var text = sharedText ?? ""
            if text.isEmpty {
                guard let runner = skillRunner else { return ReadResult(text: "Documents need the iPhone app · nothing done") }
                text = try await runner.run(skill, args: args)
            }
            guard !text.isEmpty else { return ReadResult(text: "No text found in that document (PDF, .txt and .md are supported).") }
            return try await reason("Summarize this document in 3 short bullets, then one line on what to do next.", text: text)
        case "html_viz":
            if (args["data"] ?? "").isEmpty || HTMLViz.pairs(from: args["data"] ?? "").isEmpty {
                if let sharedText { args["data"] = sharedText }
            }
            if args["title"] == nil {
                let t = try await reflex.engine.generate(prompt: Self.localPrompt("Give a 2-5 word chart title for: \(String((args["data"] ?? "").prefix(300)))", mem: ""), maxTokens: 12, temperature: 0.2)
                let clean = t.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'.“”"))
                args["title"] = clean.isEmpty || clean.count > 60 ? "Chart" : clean
            }
            if let runner = skillRunner {
                return ReadResult(text: try await runner.run(skill, args: args))
            }
            return ReadResult(text: HTMLViz.reply(text: args["data"] ?? "", title: args["title"] ?? "Chart") ?? "No numbers to chart.")
        case "device_status":
            guard let runner = skillRunner else { return ReadResult(text: "Battery & storage needs the iPhone app · nothing done") }
            return ReadResult(text: try await runner.run(skill, args: args))
        case "calendar_find":
            let hits = try await actions.searchEvents(args["query"] ?? "")
            return ReadResult(text: hits.first ?? "Nothing matching on your calendar in the next 30 days.")
        case "memory_recall":
            let hits = try await memory.retrieve(args["query"] ?? "", k: 3)
            return ReadResult(text: hits.isEmpty ? "You haven't told me that yet."
                                                 : "From memory: " + hits.map { $0.fact.text }.joined(separator: "; "))
        default:
            switch skill.invocation {
            case .cloudReason:
                let text = args["text"] ?? sharedText ?? ""
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return ReadResult(text: "Share or paste the text you want me to read.")
                }
                return try await reason(skill.id == "translate" ? "Translate into \(args["target_language"] ?? ""). Reply with the translation only." : "Summarize in 3 short bullets.", text: text)
            default:
                guard let runner = skillRunner else { return ReadResult(text: "\(skill.title) needs the iPhone app · nothing done") }
                return ReadResult(text: try await runner.run(skill, args: args))
            }
        }
    }

    /// Local 1B for short inputs; long inputs escalate to the cloud chain only when online, configured and the
    /// complete assembled text passes the sensitivity gate. Otherwise the 1B reads a truncated window and says so.
    /// The result keeps provider, scrubbed payload, withheld flag and sensitivity decisions so a skill read is
    /// never mislabelled as on-device (BF-3).
    func reason(_ instruction: String, text: String, localLimit: Int = 2_500) async throws -> ReadResult {
        let config = cloudConfiguration()
        if text.count > localLimit, isOnline(), !config.chain.brains.isEmpty {
            var decisions: [ReflexDecision] = []
            switch try await CloudTurnComposer.prepareDocument(instruction: instruction, text: text,
                                                               scrubber: config.scrubber, reflex: reflex,
                                                               onDecision: { decisions.append($0) }) {
            case .prepared(let turn):
                do {
                    let ans = try await turn.send(on: config.chain)
                    return ReadResult(text: turn.restore(ans.text), provider: "\(ans.provider) · \(ans.model)",
                                      cloudPromptSent: turn.sentText, decisions: decisions)
                } catch {
                    if CloudBrainChain.isCancellation(error) { throw error }
                    do {
                        var result = try await localReason(instruction, text: text, limit: localLimit,
                                                           note: "cloud unavailable", decisions: decisions)
                        result.cloudPromptSent = turn.sentText
                        result.withheldForSensitivity = false
                        return result
                    } catch {
                        throw CloudRequestFailure(sentText: turn.sentText, causedBy: error)
                    }
                }
            case .withheld(let reason):
                return try await localReason(instruction, text: text, limit: localLimit,
                                             note: reason.localNote, decisions: decisions)
            }
        }
        return try await localReason(instruction, text: text, limit: localLimit, note: nil, decisions: [])
    }

    private func localReason(_ instruction: String, text: String, limit: Int, note: String?,
                             decisions: [ReflexDecision]) async throws -> ReadResult {
        let window = String(text.prefix(limit))
        let out = try await reflex.engine.generate(prompt: Self.localPrompt(instruction + "\n\n" + window, mem: ""), maxTokens: 200, temperature: 0.3)
        guard text.count > limit else { return ReadResult(text: out.trimmed, decisions: decisions) }
        let why = note.map { "; \($0)" } ?? ""
        return ReadResult(text: out.trimmed + "\n(On device: read the first \(limit) characters\(why).)",
                          withheldForSensitivity: note != nil, decisions: decisions)
    }
}

extension Reflex {
    /// Content-free priors for skillPick sets of 2...8 options (merge into CalibrationProfile.prior; key skillPick#N).
    public func measureSkillPickPriors() async throws -> [String: [Double]] {
        var out: [String: [Double]] = [:]
        for n in 1...7 {
            let set = OptionSets.skillPick(candidates: (1...n).map { "Action \($0)" })
            let L = set.activeLetters
            var acc = [Double](repeating: 0, count: L.count)
            for cf in DecisionPrompt.contentFree {
                let raw = try await engine.nextTokenLogits(prompt: promptFormat(set, cf, profile.promptStyle), candidates: L)
                let floor = (raw.values.min() ?? 0) - 2
                let p = Calibration.softmax(L.map { raw[$0] ?? floor })
                for i in acc.indices { acc[i] += p[i] / Double(DecisionPrompt.contentFree.count) }
            }
            out[DecisionPrompt.priorKey(set)] = acc.map { log(max($0, 1e-9)) }
        }
        return out
    }
}

/// Regex argument filling per ArgSpec (name first, then kind). Times stay raw phrases (NSDataDetector / Shortcuts parse them).
public enum SkillArgs {
    static func first(_ p: String, in u: String, ci: Bool = true, literal: Bool = false) -> String? {
        guard let re = try? NSRegularExpression(pattern: p, options: ci ? [.caseInsensitive] : []),
              let m = re.firstMatch(in: u, range: NSRange(u.startIndex..., in: u)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: u) else { return nil }
        let value = String(u[r]).trimmed
        let v = literal ? value : value.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'.!?"))
        return v.isEmpty ? nil : v
    }
    static let notNames: Set<String> = ["on", "to", "my", "me", "a", "an", "the", "him", "her", "them", "back", "every", "someone", "everyone", "this", "that", "message", "dm", "text"]
    static let verbs = #"(?:dm|direct message|message|msg|text|sms|tell|ping|send|reply to|respond to|write to|call|phone|ring|facetime|email|e-mail|whatsapp)"#

    static func person(_ u: String) -> String? {
        if let h = first(#"@([A-Za-z0-9_][A-Za-z0-9_.]{0,29})"#, in: u) { return h }
        let p = #"\b"# + verbs + #"\s+(?:a\s+(?:dm|message|text)\s+to\s+|to\s+)?@?([A-Za-z][A-Za-z0-9_.']*(?-i:\s+[A-Z][a-z]+)?)"#
        guard var n = first(p, in: u) else { return first(#"\bto\s+@?([A-Z][a-z]+)\b"#, in: u, ci: false) }
        if n.lowercased().range(of: #"'(ll|m|ve|d|re|s|t)$"#, options: .regularExpression) != nil { return nil }
        if n.hasSuffix("'s") { n = String(n.dropLast(2)) }
        let w = n.split(separator: " ").map(String.init)
        if let f = w.first, notNames.contains(f.lowercased()) { return nil }
        // Keep a second capitalized word only if it isn't a skill/app word ("Sam Lee" yes, "Sam On" no).
        return w.count > 1 && !["On", "At", "In", "Saying", "That"].contains(w[1]) ? n : w.first
    }
    static func body(_ u: String) -> String? {
        first(#"[\"“]([^\"”]+)[\"”]"#, in: u, literal: true) ?? first(#"(?:\bsaying|\bthat says|\bto say|\bwith the message|:)\s+([\s\S]+)$"#, in: u, literal: true)
            ?? first(#"\b(?:that)\s+(.+)$"#, in: u, literal: true)
    }
    static func time(_ u: String) -> String? {
        // Keep the complete time expression, including a day qualifier, a second clock time/range, or a
        // zone/city word. `InstantParser` refuses what this app cannot honour; extraction never trims a
        // qualifier away and lets the remaining prefix look supported.
        guard var t = TimePhrase.capture(in: u) else { return nil }
        for prefix in ["at ", "by "] where t.lowercased().hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count))
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func extract(_ skill: Skill, utterance u: String) -> [String: String] {
        if MessageChannel.channel(forCapabilityID: skill.id) != nil {
            let parts = MessageDraft.messageArgs(u)
            let handle = skill.argSchema.contains { $0.name == "contact" && $0.kind == .handle }
            return ["contact": handle ? parts.contact?.lowercased() : parts.contact, "body": parts.body].compactMapValues { $0 }
        }
        var a: [String: String] = [:]
        if case .native(let h) = skill.invocation, ActionPlanner.executorTools.contains(h) {
            a = ArgumentExtractor.heuristic(tool: h, utterance: u)
        }
        for spec in skill.argSchema where (a[spec.name] ?? "").isEmpty {
            var v: String?
            switch (spec.name, spec.kind) {
            case ("target_language", _): v = first(#"\b(?:to|into)\s+([\p{L}][\p{L} -]{0,60})[.!?]?$"#, in: u)
            case ("text", _) where skill.id == "translate":
                v = first(#"\btranslate\s+(.+?)\s+(?:to|into)\s+[\p{L}][\p{L} -]{0,60}[.!?]?$"#, in: u, literal: true)
                    ?? first(#"\btranslate\s+(.+)$"#, in: u, literal: true)
            case ("reply", _): v = first(#"\b(?:with|saying|say)\s+[\"“]?(.+?)[\"”]?$"#, in: u) ?? body(u)
            case ("trigger", _): v = first(#"\b(?:every|each|whenever someone sends(?: me)?(?: an?)?)\s+([a-z]+)"#, in: u)
            case ("name", _): v = first(#"\bshortcut\s+(?:called\s+|named\s+)?(.+)$"#, in: u)
            case ("n", _): v = first(#"\b(?:last|past|recent|latest)\s+(\d+|few|couple)"#, in: u).map { $0 == "few" ? "3" : $0 == "couple" ? "2" : $0 }
            case ("subject", _): v = first(#"\bsubject\s+[\"“]?([^\"”]+)[\"”]?"#, in: u)
            case ("data", _): v = first(#":\s*(.+)$"#, in: u) ?? (HTMLViz.pairs(from: u).isEmpty ? nil : u)
            case (_, .handle): v = person(u)?.lowercased()
            case (_, .contact): v = person(u).map { $0.prefix(1).uppercased() + $0.dropFirst() }
            case ("body", _): v = body(u)
            case (_, .datetime): v = time(u)
            case (_, .duration): v = first(#"((?:[+-]?\d+(?:\.\d+)?\s*(?:seconds?|secs?|minutes?|mins?|hours?|hrs?)(?:\s+(?:and\s+)?)?)+)"#, in: u)
            case (_, .number): v = first(#"\b(\d+)\b"#, in: u)
            case (_, .url): v = first(#"(https?://\S+)"#, in: u)
            case (_, .place): v = first(#"\b(?:directions to|navigate to|uber to|ride to|take me to|get me to|weather in|forecast for|to|in|at)\s+(.+?)(?:\s+(?:tomorrow|today|tonight|now))?$"#, in: u)
            case (_, .app): v = first(#"\b(?:open|launch|start)\s+(?:the\s+)?(.+?)(?:\s+app)?$"#, in: u)
            case ("show", .query):
                v = first(#"\b(?:episode of|episodes of|season of|watch|play|put on|open)\s+(?:the\s+)?(?:latest|newest|new|next|last)?\s*(?:episode of\s+)?(.+?)\s+(?:on|in)\s+(?:the\s+)?(?:apple\s*tv|tv app|appletv)\b"#, in: u)
                    ?? first(#"\b(?:episode of|watch|play|put on|open)\s+(?:the\s+)?(?:latest|newest|new|next|last)?\s*(?:episode of\s+)?(.+)$"#, in: u)
            case (_, .query):
                v = first(#"\bplay\s+(.+?)\s+on spotify"#, in: u) ?? first(#"\b(?:search(?: the web)? for|google|look up|search)\s+(.+)$"#, in: u)
                    ?? (skill.id == "web_search" ? u : nil)
            case (_, .text):
                v = first(#"\b(?:note(?: that)?|jot down|write down)[:\s]+(.+)$"#, in: u) ?? first(#"\btranslate\s+(.+)$"#, in: u) ?? body(u)
            case (_, .document): v = nil
            }
            if let v, !v.isEmpty { a[spec.name] = v }
        }
        return a
    }

    public static func question(for spec: ArgSpec, skill: Skill) -> String {
        switch spec.kind {
        case .contact, .handle: return "Who should I \(skill.category == .phone ? "call" : "message") for \(skill.title)?"
        case .datetime: return "What time?"
        case .duration: return "How long?"
        case .place: return "Where to?"
        case .url: return "Which link?"
        case .app: return "Which app?"
        case .text where spec.name == "body": return "What should the message say?"
        default: return "What should \(skill.title) use for \(spec.name)?"
        }
    }

    public static func confirmPrompt(_ skill: Skill, args: [String: String]) -> String {
        var parts: [String] = []
        for spec in skill.argSchema {
            guard let v = args[spec.name], !v.isEmpty else { continue }
            parts.append(spec.kind == .handle ? "@" + v : spec.name == "body" || spec.name == "reply" ? "“\(v)”" : v)
        }
        let tail = skill.clipboard != nil ? " (message goes on your clipboard, you paste and send)" : ""
        return "\(skill.title): \(parts.joined(separator: " · "))?\(tail)"
    }
}
