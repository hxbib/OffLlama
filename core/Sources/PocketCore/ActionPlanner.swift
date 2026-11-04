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
/// tau gate. Below tau -> clarify with the top 3 skills. Then args (regex per ArgSpec kind + the trained contactPick),
/// the trained confirmBeforeAct, and the hard rule (skill.confirm) -> PlannedAction(tool: "skill:<id>").
public enum ActionPlanner {
    public static let toolPrefix = "skill:"
    /// Native handlers that are ActionExecutor tools (SystemActions on iOS); everything else goes to the SkillRunner.
    public static let executorTools: Set<String> = ["send_message", "send_email", "create_reminder", "create_event",
                                                     "find_event", "lookup_contact", "search_memory"]
    /// Native handlers whose runner returns raw text that PocketCore then summarizes (local 1B or escalation).
    public static let textSourceHandlers: Set<String> = ["analyze_document"]

    /// Explicit app/feature words that a chosen trained tool cannot serve ("dm sam ON INSTAGRAM" -> toolChoice says
    /// send_message; "WAKE ME at 6" -> create_reminder). Only these tool/word pairs override; everything else keeps today's path.
    static let overridable: [String: [String]] = [
        "send_message": ["instagram", "insta", "ig", "twitter", "x dm", "on x", "whatsapp", "whats app", "facetime", "auto reply", "autoreply", "every reel"],
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
        if u.range(of: #" (?:last|recent|latest) \d+ (?:e ?)?mails? "#, options: .regularExpression) != nil { return true }
        return explicitRequest.contains { u.contains(SkillRegistry.norm($0)) }
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
    /// Open-world tool path. Appends its decisions (skillPick, contactPick, confirmBeforeAct) and sets `planned`.
    public func planSkill(_ utterance: String, ctx: String, registry: SkillRegistry, decisions: inout [ReflexDecision],
                          planned: inout PlannedAction?) async throws -> Reply {
        try await planSkillCore(utterance, ctx: ctx, registry: registry, decisions: &decisions, planned: &planned, fallThrough: false)
            ?? .clarify("What would you like me to do?")
    }

    /// Before the routed branch (route != tool): an explicit app/feature request gets ONE skillPick decision. Returns nil
    /// (caller continues with the trained route unchanged) unless the request is explicit AND skillPick clears tau.
    public func skillOverride(_ utterance: String, ctx: String, route: ReflexDecision, decisions: inout [ReflexDecision],
                              planned: inout PlannedAction?) async throws -> Reply? {
        guard let reg = skills, route.chosen.id != "tool", ActionPlanner.isExplicitRequest(utterance) else { return nil }
        return try await planSkillCore(utterance, ctx: ctx, registry: reg, decisions: &decisions, planned: &planned, fallThrough: true)
    }

    func planSkillCore(_ utterance: String, ctx: String, registry: SkillRegistry, decisions: inout [ReflexDecision],
                       planned: inout PlannedAction?, fallThrough: Bool) async throws -> Reply? {
        let cands = ActionPlanner.candidates(utterance, registry: registry)
        guard !cands.isEmpty else {
            return fallThrough ? nil : .clarify("I can't do that on this phone yet. New abilities are a JSON skill away (docs/SKILLS.md).")
        }
        let pick = try await reflex.decide(OptionSets.skillPick(candidates: cands.map(\.optionLabel)), context: ctx)
        decisions.append(pick)
        guard pick.chosen.id != "ask", let i = Int(pick.chosen.id.dropFirst()), i < cands.count else {
            return fallThrough ? nil : .clarify("Did you mean: \(ActionPlanner.list(cands.prefix(3).map(\.title)))?")
        }
        let skill = cands[i]
        var args = SkillArgs.extract(skill, utterance: utterance)

        // Contacts: the trained contactPick decision disambiguates, exactly like send_message.
        if let spec = skill.argSchema.first(where: { $0.kind == .contact }), let who = args[spec.name] {
            let found = try await actions.searchContacts(who)
            if found.count > 1 {
                let d = try await reflex.decide(OptionSets.contactPick(candidates: found), context: ctx)
                decisions.append(d)
                guard d.chosen.id != "ask" else { return .clarify("Which \(who)? " + found.joined(separator: ", ")) }
                args[spec.name] = d.chosen.label
            } else if let only = found.first { args[spec.name] = only }
            else if spec.required { return .clarify("I couldn't find \(who) in your contacts.") }
        }
        if let missing = skill.argSchema.first(where: { $0.required && (args[$0.name] ?? "").isEmpty }) {
            return .clarify(SkillArgs.question(for: missing, skill: skill))
        }

        let action = PlannedAction(tool: ActionPlanner.toolPrefix + skill.id, args: args)
        planned = action
        let conf = try await reflex.decide(OptionSets.confirmBeforeAct, context: "\(ctx)\nPlanned action: \(action.tool) \(ActionPlanner.describe(args))")
        decisions.append(conf)
        if conf.chosen.id == "confirm" || skill.confirm {      // hard rule: anything that reaches another person confirms
            return .needsConfirmation(action, prompt: SkillArgs.confirmPrompt(skill, args: args))
        }
        return .acted(try await execute(action))
    }

    /// Runs a planned action: `skill:` tools via the registry (executor tools, PocketCore reasoning, or the SkillRunner);
    /// everything else unchanged through `actions.perform`.
    public func execute(_ a: PlannedAction) async throws -> String {
        guard a.tool.hasPrefix(ActionPlanner.toolPrefix) else { return try await actions.perform(a) }
        let id = String(a.tool.dropFirst(ActionPlanner.toolPrefix.count))
        guard let skill = (skills ?? SkillRegistry()).skill(id: id) else { return "Unknown skill \(id) · nothing done" }
        var args = a.args
        switch skill.invocation {
        case .native(let h) where ActionPlanner.executorTools.contains(h):
            return try await actions.perform(PlannedAction(tool: h, args: args))
        case .native("email_digest"):
            guard let shared = SharedInbox.shared.take() else {
                return "iOS lets no app read your Mail. Select the emails in Mail → Share → Pocket Glimmer (Shortcut “PG Share Emails”), and I'll summarize them here, on device."
            }
            return try await reason("Summarize these emails in 3 short bullets: who wants what, and any deadline.", text: shared.text)
        case .native(let h) where ActionPlanner.textSourceHandlers.contains(h):
            var text = SharedInbox.shared.take()?.text ?? ""             // shared from Files/Mail/Safari first
            if text.isEmpty {
                guard let runner = skillRunner else { return "Documents need the iPhone app · nothing done" }
                text = try await runner.run(skill, args: args)          // document picker -> extracted text
            }
            guard !text.isEmpty else { return "No text found in that document (PDF, .txt and .md are supported)." }
            return try await reason("Summarize this document in 3 short bullets, then one line on what to do next.", text: text)
        case .native("html_viz"):
            if (args["data"] ?? "").isEmpty || HTMLViz.pairs(from: args["data"] ?? "").isEmpty, let shared = SharedInbox.shared.peek() { args["data"] = shared.text }
            if args["title"] == nil {
                let t = try await reflex.engine.generate(prompt: Self.localPrompt("Give a 2-5 word chart title for: \(String((args["data"] ?? "").prefix(300)))", mem: ""), maxTokens: 12, temperature: 0.2)
                let clean = t.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'.“”"))
                args["title"] = clean.isEmpty || clean.count > 60 ? "Chart" : clean
            }
            guard let runner = skillRunner else { return HTMLViz.render(text: args["data"] ?? "", title: args["title"] ?? "Chart").map { "Chart ready (\($0.bars) bars)" } ?? "No numbers to chart." }
            return try await runner.run(skill, args: args)
        case .cloudReason:
            let text = args["text"] ?? SharedInbox.shared.peek()?.text ?? ""
            return try await reason(skill.id == "translate" ? "Translate as asked. Reply with the translation only." : "Summarize in 3 short bullets.",
                                    text: text.isEmpty ? args.values.joined(separator: " ") : text)
        default:
            guard let runner = skillRunner else { return "\(skill.title) needs the iPhone app · nothing done" }
            return try await runner.run(skill, args: args)
        }
    }

    /// Local 1B for short inputs; long inputs escalate to the cloud chain only when online, configured and the
    /// sensitivity decision allows (scrubbed). Otherwise the 1B reads a truncated window and says so.
    func reason(_ instruction: String, text: String, localLimit: Int = 2_500) async throws -> String {
        let cloud = self.cloud
        if text.count > localLimit, isOnline(), !cloud.brains.isEmpty {
            let sens = try await reflex.decide(OptionSets.sensitivity, context: "User: \(instruction)\n\(String(text.prefix(400)))")
            if sens.chosen.id == "ok" {
                let sc = cloudScrubber()
                let s = sc.scrub(String(text.prefix(24_000)))
                let ans = try await cloud.complete([ChatMessage(role: "system", content: "You are the reasoning brain of a private phone assistant. Placeholders like [PERSON_1] stand for private data; keep them verbatim."),
                                                    ChatMessage(role: "user", content: instruction + "\n\n" + s.text)])
                return sc.restore(ans.text, mapping: s.mapping)
            }
        }
        let window = String(text.prefix(localLimit))
        let out = try await reflex.engine.generate(prompt: Self.localPrompt(instruction + "\n\n" + window, mem: ""), maxTokens: 200, temperature: 0.3)
        return out.trimmed + (text.count > localLimit ? "\n(On device: read the first \(localLimit) characters.)" : "")
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
    static func first(_ p: String, in u: String, ci: Bool = true) -> String? {
        guard let re = try? NSRegularExpression(pattern: p, options: ci ? [.caseInsensitive] : []),
              let m = re.firstMatch(in: u, range: NSRange(u.startIndex..., in: u)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: u) else { return nil }
        let v = String(u[r]).trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'.!?"))
        return v.isEmpty ? nil : v
    }
    static let notNames: Set<String> = ["on", "to", "my", "me", "a", "an", "the", "him", "her", "them", "back", "every", "someone", "everyone", "this", "that", "message", "dm", "text"]
    static let verbs = #"(?:dm|direct message|message|msg|text|tell|ping|send|reply to|respond to|write to|call|phone|ring|facetime|email|e-mail|whatsapp)"#

    static func person(_ u: String) -> String? {
        if let h = first(#"@([A-Za-z0-9_][A-Za-z0-9_.]{0,29})"#, in: u) { return h }
        let p = #"\b"# + verbs + #"\s+(?:a\s+(?:dm|message|text)\s+to\s+|to\s+)?@?([A-Za-z][A-Za-z0-9_.']*(?-i:\s+[A-Z][a-z]+)?)"#
        guard var n = first(p, in: u) else { return first(#"\bto\s+@?([A-Z][a-z]+)\b"#, in: u, ci: false) }
        if n.hasSuffix("'s") { n = String(n.dropLast(2)) }
        let w = n.split(separator: " ").map(String.init)
        if let f = w.first, notNames.contains(f.lowercased()) { return nil }
        // Keep a second capitalized word only if it isn't a skill/app word ("Sam Lee" yes, "Sam On" no).
        return w.count > 1 && !["On", "At", "In", "Saying", "That"].contains(w[1]) ? n : w.first
    }
    static func body(_ u: String) -> String? {
        first(#"[\"“]([^\"”]+)[\"”]"#, in: u) ?? first(#"(?:\bsaying|\bthat says|\bto say|\bwith the message|:)\s+(.+)$"#, in: u)
            ?? first(#"\b(?:that)\s+(.+)$"#, in: u)
    }
    static func time(_ u: String) -> String? {
        guard var t = first(#"\b((?:tomorrow|today|tonight)?\s*(?:at\s+)?\d{1,2}(?::\d{2})?\s?(?:am|pm|a\.m\.|p\.m\.)?(?:\s+(?:tomorrow|today|tonight))?)\b"#, in: u)
            ?? first(#"\b(tomorrow|today|tonight|next \w+|on \w+day)\b"#, in: u) else { return nil }
        if t.lowercased().hasPrefix("at ") { t = String(t.dropFirst(3)) }
        if t.range(of: #"^\d{1,2}$"#, options: .regularExpression) != nil { t += ":00" }
        return t
    }

    public static func extract(_ skill: Skill, utterance u: String) -> [String: String] {
        var a: [String: String] = [:]
        if case .native(let h) = skill.invocation, ActionPlanner.executorTools.contains(h) {
            a = ArgumentExtractor.heuristic(tool: h, utterance: u)
        }
        for spec in skill.argSchema where (a[spec.name] ?? "").isEmpty {
            var v: String?
            switch (spec.name, spec.kind) {
            case ("reply", _): v = first(#"\b(?:with|saying|say)\s+[\"“]?(.+?)[\"”]?$"#, in: u) ?? body(u)
            case ("trigger", _): v = first(#"\b(?:every|each|whenever someone sends(?: me)?(?: an?)?)\s+([a-z]+)"#, in: u)
            case ("name", _): v = first(#"\bshortcut\s+(?:called\s+|named\s+)?(.+)$"#, in: u)
            case ("n", _): v = first(#"\b(?:last|past|recent|latest)\s+(\d+|few|couple)"#, in: u).map { $0 == "few" ? "3" : $0 == "couple" ? "2" : $0 }
            case ("subject", _): v = first(#"\bsubject\s+[\"“]?([^\"”]+)[\"”]?"#, in: u)
            case ("data", _): v = first(#":\s*(.+)$"#, in: u) ?? (HTMLViz.pairs(from: u).isEmpty ? nil : u)
            case (_, .handle): v = person(u).map { $0.lowercased().replacingOccurrences(of: " ", with: "") }
            case (_, .contact): v = person(u).map { $0.prefix(1).uppercased() + $0.dropFirst() }
            case ("body", _): v = body(u)
            case (_, .datetime): v = time(u)
            case (_, .duration): v = first(#"\b(\d+\s*(?:-\s*)?(?:seconds?|secs?|minutes?|mins?|hours?|hrs?))\b"#, in: u)
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
