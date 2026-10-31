import Foundation

/// Every System 1 ("Reflex") decision is a typed multiple-choice question answered by
/// ONE forward pass: we read the logits over the option-letter tokens, never sample text.
public enum DecisionType: String, Codable, CaseIterable, Sendable {
    case route              // answer_local / tool / escalate_cloud / clarify
    case toolChoice         // which on-device tool
    case contactPick        // disambiguate a contact among retrieved candidates
    case eventPick          // disambiguate a calendar event among retrieved candidates
    case rememberOrNot      // store this utterance as a memory?
    case memoryConflict     // new fact vs existing fact
    case notificationTriage // incoming notification urgency
    case confirmBeforeAct   // is explicit confirmation needed before acting?
    case nudgeNow           // should a proactive nudge fire now?
    case timing             // now / at a time / on arrival / recurring
    case sensitivity        // may this leave the device (after scrubbing)?
    case answerability      // can the small on-device model answer this itself?
}

public struct DecisionOption: Codable, Hashable, Sendable {
    public let id: String        // stable machine id, e.g. "answer_local"
    public let label: String     // text shown to the model
    public init(_ id: String, _ label: String) { self.id = id; self.label = label }
}

public struct OptionSet: Sendable {
    public let type: DecisionType
    public let question: String
    public let options: [DecisionOption]
    /// The option chosen when confidence is below tau (the safe fallback for this set).
    public let fallbackID: String
    public static let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]

    public init(type: DecisionType, question: String, options: [DecisionOption], fallbackID: String) {
        precondition(!options.isEmpty && options.count <= OptionSet.letters.count, "1...8 options")
        precondition(options.contains { $0.id == fallbackID }, "fallback must be an option")
        self.type = type; self.question = question; self.options = options; self.fallbackID = fallbackID
    }

    public var activeLetters: [String] { Array(OptionSet.letters.prefix(options.count)) }
    public func option(forLetter l: String) -> DecisionOption? {
        guard let i = OptionSet.letters.firstIndex(of: l), i < options.count else { return nil }
        return options[i]
    }
    public func letter(forID id: String) -> String? {
        options.firstIndex { $0.id == id }.map { OptionSet.letters[$0] }
    }
}

public enum OptionSets {
    public static let route = OptionSet(type: .route,
        question: "How should the assistant handle the user's request?",
        options: [.init("answer_local", "Answer directly on the phone (simple chat, facts the assistant remembers, short rewrite)"),
                  .init("tool", "Use a phone tool (reminder, calendar, contacts, message, memory lookup)"),
                  .init("escalate_cloud", "Needs hard reasoning, long writing, or world knowledge: ask the cloud brain"),
                  .init("clarify", "The request is ambiguous: ask the user a short question")],
        fallbackID: "escalate_cloud")

    public static let toolChoice = OptionSet(type: .toolChoice,
        question: "Which tool should be used?",
        options: [.init("create_reminder", "Create a reminder"),
                  .init("create_event", "Create a calendar event"),
                  .init("find_event", "Look up the calendar"),
                  .init("send_message", "Send a text message to a contact"),
                  .init("lookup_contact", "Look up a contact's details"),
                  .init("search_memory", "Search what the assistant remembers about the user"),
                  .init("none", "None of these tools fits")],
        fallbackID: "none")

    public static let rememberOrNot = OptionSet(type: .rememberOrNot,
        question: "Should the assistant save something from this message to long-term memory?",
        options: [.init("remember_fact", "Yes: a lasting fact or preference about the user or their people"),
                  .init("remember_temporary", "Yes, but it expires soon (plan, short-term state)"),
                  .init("no", "No: nothing worth remembering")],
        fallbackID: "no")

    public static let memoryConflict = OptionSet(type: .memoryConflict,
        question: "A new fact relates to an existing memory. What should happen?",
        options: [.init("update", "The new fact replaces the old one (it changed)"),
                  .init("keep_both", "Both are true; keep both"),
                  .init("ignore_new", "The new statement is not a real change; keep the old one")],
        fallbackID: "keep_both")

    public static let notificationTriage = OptionSet(type: .notificationTriage,
        question: "How urgent is this incoming notification for the user right now?",
        options: [.init("interrupt", "Urgent: tell the user now"),
                  .init("digest", "Useful but can wait for the next summary"),
                  .init("ignore", "Noise: ignore")],
        fallbackID: "digest")

    public static let confirmBeforeAct = OptionSet(type: .confirmBeforeAct,
        question: "Before performing this action, does the assistant need the user's explicit confirmation?",
        options: [.init("act", "No: low-risk and clearly requested, do it"),
                  .init("confirm", "Yes: it contacts someone, spends money, deletes, or is unclear")],
        fallbackID: "confirm")

    public static let nudgeNow = OptionSet(type: .nudgeNow,
        question: "Given the trigger and what the assistant remembers, should it nudge the user now?",
        options: [.init("nudge", "Yes: the memory is relevant to this moment"),
                  .init("later", "Relevant, but a later moment is better"),
                  .init("skip", "Not relevant")],
        fallbackID: "skip")

    public static let timing = OptionSet(type: .timing,
        question: "When should the requested action happen?",
        options: [.init("now", "Right now"),
                  .init("at_time", "At a specific date/time"),
                  .init("on_arrival", "When the user arrives at or leaves a place"),
                  .init("recurring", "Repeatedly on a schedule")],
        fallbackID: "now")

    public static let sensitivity = OptionSet(type: .sensitivity,
        question: "Is it acceptable to send this request (with names and numbers masked) to a cloud model?",
        options: [.init("ok", "Yes: nothing sensitive remains"),
                  .init("sensitive", "No: health, money, intimate or security details; keep on device")],
        fallbackID: "sensitive")

    public static let answerability = OptionSet(type: .answerability,
        question: "Can a small on-device model answer this correctly without the internet?",
        options: [.init("yes", "Yes, it is simple"),
                  .init("no", "No, it needs reasoning, fresh facts, or long output")],
        fallbackID: "no")

    /// Dynamic sets: candidates come from Contacts / EventKit retrieval at runtime.
    public static func contactPick(candidates: [String]) -> OptionSet {
        let c = Array(candidates.prefix(7))
        return OptionSet(type: .contactPick, question: "Which contact does the user mean?",
            options: c.enumerated().map { .init("c\($0.offset)", $0.element) } + [.init("ask", "Unclear: ask the user")],
            fallbackID: "ask")
    }
    public static func eventPick(candidates: [String]) -> OptionSet {
        let c = Array(candidates.prefix(7))
        return OptionSet(type: .eventPick, question: "Which calendar event does the user mean?",
            options: c.enumerated().map { .init("e\($0.offset)", $0.element) } + [.init("ask", "Unclear: ask the user")],
            fallbackID: "ask")
    }

    public static let staticSets: [OptionSet] = [route, toolChoice, rememberOrNot, memoryConflict, notificationTriage,
                                                 confirmBeforeAct, nudgeNow, timing, sensitivity, answerability]
}

/// Prompt builder shared by the app, the Linux e2e path, and (mirrored) training/. Keep in sync with
/// training/pg_train/prompts.py — tests check the exact format.
public enum DecisionPrompt {
    public static let system = "You are Reflex, the fast decision module of an offline personal assistant. Answer each multiple-choice question with a single letter."

    public static func body(set: OptionSet, context: String) -> String {
        var s = "Context:\n\(context.trimmingCharacters(in: .whitespacesAndNewlines))\n\nQuestion: \(set.question)\n"
        for (i, o) in set.options.enumerated() { s += "\(OptionSet.letters[i]). \(o.label)\n" }
        s += "Answer with one letter."
        return s
    }

    /// Llama 3.x chat template, ending right where the answer letter token is generated.
    public static func llama3(set: OptionSet, context: String) -> String {
        "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n\(system)<|eot_id|>" +
        "<|start_header_id|>user<|end_header_id|>\n\n\(body(set: set, context: context))<|eot_id|>" +
        "<|start_header_id|>assistant<|end_header_id|>\n\nAnswer:"
    }
}
