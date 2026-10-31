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
        options: [.init("answer_local", "Reply directly: greeting, thanks, small talk, quick arithmetic, short rewrite or translation"),
                  .init("tool", "Do a phone action: set a reminder, add/check calendar, text someone, look up a contact, recall a saved memory"),
                  .init("escalate_cloud", "Needs deep thinking or long writing: analysis, advice, planning, comparisons, essays, research"),
                  .init("clarify", "Too vague to act on: says 'it/that/the thing' with no clear object or person")],
        fallbackID: "escalate_cloud")

    public static let toolChoice = OptionSet(type: .toolChoice,
        question: "Which tool should be used?",
        options: [.init("create_reminder", "Create a reminder (remind me to...)"),
                  .init("create_event", "Create a calendar event (schedule/book/put on calendar)"),
                  .init("find_event", "Look up the calendar (what's on / when is my...)"),
                  .init("send_message", "Send a text message (text/tell/message someone)"),
                  .init("lookup_contact", "Look up a contact's phone, email or address"),
                  .init("search_memory", "Recall something the user told the assistant before"),
                  .init("none", "None of these tools fits")],
        fallbackID: "none")

    public static let rememberOrNot = OptionSet(type: .rememberOrNot,
        question: "Should the assistant save something from this message to long-term memory?",
        options: [.init("remember_fact", "Yes, a lasting fact: allergy, diet, home, job, family, birthday, preference"),
                  .init("remember_temporary", "Yes, but short-lived: where they parked, today's plan, something to buy soon"),
                  .init("no", "No: a question, command or chit-chat with no personal fact")],
        fallbackID: "no")

    public static let memoryConflict = OptionSet(type: .memoryConflict,
        question: "A new fact relates to an existing memory. What should happen?",
        options: [.init("update", "The fact changed (moved, new job, new diet): replace the old one"),
                  .init("keep_both", "Both can be true at once (another hobby, another friend)"),
                  .init("ignore_new", "Joke, hypothetical, or just repeating the old fact: keep the old one")],
        fallbackID: "keep_both")

    public static let notificationTriage = OptionSet(type: .notificationTriage,
        question: "How urgent is this incoming notification for the user right now?",
        options: [.init("interrupt", "Urgent or time-critical: family emergency, security alert, travel change"),
                  .init("digest", "Personal or work info that can wait an hour"),
                  .init("ignore", "Marketing, promotions, newsletters")],
        fallbackID: "digest")

    public static let confirmBeforeAct = OptionSet(type: .confirmBeforeAct,
        question: "Before performing this action, does the assistant need the user's explicit confirmation?",
        options: [.init("act", "Safe and reversible: a reminder or event the user clearly asked for"),
                  .init("confirm", "Risky: messages other people, deletes, spends money, or is irreversible")],
        fallbackID: "confirm")

    public static let nudgeNow = OptionSet(type: .nudgeNow,
        question: "Given the trigger and what the assistant remembers, should it nudge the user now?",
        options: [.init("nudge", "Yes: this place or moment matches the memory (store for shopping, person for a promise)"),
                  .init("later", "Related, but a better moment is coming"),
                  .init("skip", "The trigger has nothing to do with the memory")],
        fallbackID: "skip")

    public static let timing = OptionSet(type: .timing,
        question: "When should the requested action happen?",
        options: [.init("now", "Right now, no time given"),
                  .init("at_time", "At a stated date or clock time, once"),
                  .init("on_arrival", "When arriving at or leaving a place"),
                  .init("recurring", "Repeats: every day/week/Monday/month")],
        fallbackID: "now")

    public static let sensitivity = OptionSet(type: .sensitivity,
        question: "Is it acceptable to send this request (with names and numbers masked) to a cloud model?",
        options: [.init("ok", "Fine to send: general topics, plans, writing, public knowledge"),
                  .init("sensitive", "Keep on device: health results, money/accounts/PINs, passwords, intimate details")],
        fallbackID: "sensitive")

    public static let answerability = OptionSet(type: .answerability,
        question: "Can a small on-device model answer this correctly without the internet?",
        options: [.init("yes", "Yes: greeting, translation of a word, small arithmetic, spelling"),
                  .init("no", "No: needs reasoning, research, long or expert output")],
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

public struct FewShot: Sendable {
    public let type: DecisionType, context: String, answerID: String, candidates: [String]?
    public init(_ type: DecisionType, _ context: String, _ answerID: String, _ candidates: [String]?) {
        self.type = type; self.context = context; self.answerID = answerID; self.candidates = candidates
    }
}

public enum PromptStyle: String, Codable, Sendable {
    case fewShot   // untrained base model: exemplars before the question (eval: 0.50 -> 0.70 on gold100 with prior correction)
    case zeroShot  // distilled student: trained on zero-shot prompts, shorter prefill
}

/// Prompt builder shared by the app, the Linux e2e path, and (mirrored) training/. Keep in sync with
/// training/pg_train/prompts.py — tests check the exact format.
public enum DecisionPrompt {
    public static let system = "You are Reflex, the fast decision module of an offline personal assistant. Answer each multiple-choice question with a single letter."

    /// Hand-written exemplars (none overlap eval/gold_decisions_v2.jsonl). Source: eval/experiments/fewshot.py.
    public static let shots: [FewShot] = [
        .init(.route, "Network: online\nUser: Good night!", "answer_local", nil),
        .init(.route, "Network: offline\nUser: Add dinner with Leo to my calendar Friday 7pm", "tool", nil),
        .init(.route, "Network: online\nUser: Write a detailed business plan for a mobile coffee cart", "escalate_cloud", nil),
        .init(.route, "Network: online\nUser: Change that one", "clarify", nil),
        .init(.toolChoice, "User: Remind me to stretch in an hour", "create_reminder", nil),
        .init(.toolChoice, "User: Message Ana that the keys are under the mat", "send_message", nil),
        .init(.toolChoice, "User: When is my haircut?", "find_event", nil),
        .init(.toolChoice, "User: What did I say my locker code was?", "search_memory", nil),
        .init(.rememberOrNot, "User: I'm lactose intolerant, just so you know", "remember_fact", nil),
        .init(.rememberOrNot, "User: Can you say that again?", "no", nil),
        .init(.rememberOrNot, "User: I parked on the 4th floor today", "remember_temporary", nil),
        .init(.memoryConflict, "Existing memory: User works at Acme\nNew statement: I started a new job at Globex this week", "update", nil),
        .init(.memoryConflict, "Existing memory: User likes hiking\nNew statement: I also really like pottery", "keep_both", nil),
        .init(.memoryConflict, "Existing memory: User lives in Austin\nNew statement: if I were rich I'd live in Paris lol", "ignore_new", nil),
        .init(.notificationTriage, "Notification from Bank: 'Was this you? $900 card charge in another country'", "interrupt", nil),
        .init(.notificationTriage, "Notification from CoffeeCo: 'Double points Tuesday!'", "ignore", nil),
        .init(.notificationTriage, "Notification from Priya: 'notes from today's meeting attached'", "digest", nil),
        .init(.confirmBeforeAct, "Planned action: create_reminder title=buy stamps, when=tomorrow 10am", "act", nil),
        .init(.confirmBeforeAct, "Planned action: send_message to Boss: 'I resign'", "confirm", nil),
        .init(.nudgeNow, "Trigger: arrive, place: Walgreens pharmacy\nMemory: User needs to buy band-aids", "nudge", nil),
        .init(.nudgeNow, "Trigger: arrive, place: the gym\nMemory: User needs to buy band-aids", "skip", nil),
        .init(.timing, "User: Remind me at 3pm tomorrow to call the bank", "at_time", nil),
        .init(.timing, "User: Remind me every Sunday to plan the week", "recurring", nil),
        .init(.timing, "User: When I leave work remind me to buy bread", "on_arrival", nil),
        .init(.sensitivity, "User: Explain what my cholesterol numbers mean: LDL 210", "sensitive", nil),
        .init(.sensitivity, "User: Suggest names for a golden retriever puppy", "ok", nil),
        .init(.answerability, "User: What's 7 times 8?", "yes", nil),
        .init(.answerability, "User: Analyze the pros and cons of moving to Seattle for my career", "no", nil),
        .init(.contactPick, "User: Text my coach Ben I'm sick", "c2", ["Ben Wu (accountant)", "Ben Cole (neighbor)", "Ben Diaz (coach)"]),
        .init(.contactPick, "User: Call Ben", "ask", ["Ben Wu (accountant)", "Ben Cole (neighbor)"]),
        .init(.eventPick, "User: Cancel my yoga class", "e1", ["Team sync (Mon 9am)", "Yoga (Thu 6pm)", "Dinner with Leo (Fri 7pm)"]),
    ]

    public static func body(set: OptionSet, context: String) -> String {
        var s = "Context:\n\(context.trimmingCharacters(in: .whitespacesAndNewlines))\n\nQuestion: \(set.question)\n"
        for (i, o) in set.options.enumerated() { s += "\(OptionSet.letters[i]). \(o.label)\n" }
        s += "Answer with one letter."
        return s
    }

    static func setFor(_ shot: FewShot) -> OptionSet {
        switch shot.type {
        case .contactPick: return OptionSets.contactPick(candidates: shot.candidates ?? [])
        case .eventPick: return OptionSets.eventPick(candidates: shot.candidates ?? [])
        default: return OptionSets.staticSets.first { $0.type == shot.type }!
        }
    }

    /// Llama 3.x chat template, ending right where the answer letter token is generated.
    public static func llama3(set: OptionSet, context: String, style: PromptStyle = .fewShot) -> String {
        var p = "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n\(system)<|eot_id|>"
        if style == .fewShot {
            for sh in shots where sh.type == set.type {
                let ss = setFor(sh)
                p += "<|start_header_id|>user<|end_header_id|>\n\n\(body(set: ss, context: sh.context))<|eot_id|>"
                p += "<|start_header_id|>assistant<|end_header_id|>\n\nAnswer: \(ss.letter(forID: sh.answerID)!)<|eot_id|>"
            }
        }
        return p + "<|start_header_id|>user<|end_header_id|>\n\n\(body(set: set, context: context))<|eot_id|>" +
            "<|start_header_id|>assistant<|end_header_id|>\n\nAnswer:"
    }

    /// Content-free inputs for contextual calibration (Zhao et al., 2021).
    public static let contentFree = ["N/A", "", "[MASK]"]
    /// Key for per-set prior: dynamic sets depend only on option count (positional prior).
    public static func priorKey(_ set: OptionSet) -> String {
        set.type == .contactPick || set.type == .eventPick ? "\(set.type.rawValue)#\(set.options.count)" : set.type.rawValue
    }
}
