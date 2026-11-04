import Foundation

/// Human wording for decision records. Raw ids and scores stay available in Details and exports; primary surfaces
/// use these labels. A decision's confidence is the model's calibrated certainty about ITS CHOICE among the listed
/// options. It is not the chance that an action succeeds or that a message was delivered.
public enum DecisionPresentation {
    public static func title(_ type: DecisionType) -> String {
        switch type {
        case .route: return "How to handle the request"
        case .toolChoice: return "Which phone action"
        case .contactPick: return "Which contact"
        case .eventPick: return "Which calendar event"
        case .rememberOrNot: return "Save to memory?"
        case .memoryConflict: return "Changed fact"
        case .notificationTriage: return "Notification urgency"
        case .confirmBeforeAct: return "Ask before acting?"
        case .nudgeNow: return "Remind now?"
        case .timing: return "When"
        case .sensitivity: return "Safe to send to the cloud?"
        case .answerability: return "Can this iPhone answer it?"
        case .skillPick: return "Which app or feature"
        }
    }

    public static func choice(_ type: DecisionType, id: String, skillTitle: (String) -> String? = { _ in nil }) -> String {
        let known: [DecisionType: [String: String]] = [
            .route: ["answer_local": "Answer on this iPhone", "tool": "Use a phone action",
                     "escalate_cloud": "Needs a cloud model", "clarify": "Ask a question first"],
            .toolChoice: ["create_reminder": "Create a reminder", "create_event": "Add a calendar event",
                          "find_event": "Look up the calendar", "send_message": "Send a text message",
                          "lookup_contact": "Look up a contact", "search_memory": "Recall a saved memory",
                          "none": "No phone action fits"],
            .rememberOrNot: ["remember_fact": "Save as a lasting fact", "remember_temporary": "Save for a week",
                             "no": "Do not save"],
            .memoryConflict: ["update": "Replace the old fact", "keep_both": "Keep both", "ignore_new": "Keep the old fact"],
            .confirmBeforeAct: ["act": "Safe to do directly", "confirm": "Ask you first"],
            .sensitivity: ["ok": "Fine to send", "sensitive": "Keep on this iPhone"],
            .answerability: ["yes": "Yes", "no": "No"],
            .timing: ["now": "Now", "at_time": "At a set time", "on_arrival": "On arrival", "recurring": "Repeats"],
            .notificationTriage: ["interrupt": "Interrupt", "digest": "Digest", "ignore": "Ignore"],
            .nudgeNow: ["nudge": "Nudge now", "later": "Later", "skip": "Skip"],
        ]
        if let label = known[type]?[id] { return label }
        if id == "ask" { return "Unclear, ask you" }
        if type == .skillPick, let t = skillTitle(id) { return t }
        if type == .contactPick || type == .eventPick, id.count >= 2, id.first.map({ $0 == "c" || $0 == "e" }) == true,
           Int(id.dropFirst()) != nil { return "Option \((Int(id.dropFirst()) ?? 0) + 1)" }
        return id.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// "97% sure, needs 90% to act without asking". Says what the number is.
    public static func certainty(confidence: Double, tau: Double) -> String {
        let c = Int((confidence * 100).rounded()), t = Int((tau * 100).rounded())
        return confidence >= tau ? "Model certainty \(c)% (needs \(t)%)" : "Model certainty \(c)%, below the \(t)% needed"
    }

    /// Separates the option the model ranked first from the option actually used.
    public static func chosenVersusTop(chosen: String, top: String, escalated: Bool) -> String? {
        guard chosen != top else { return nil }
        return escalated ? "Top option was below the certainty bar, so a safe fallback was used."
                         : "Top option differs from the one used."
    }

    public static func seconds(_ ms: Double) -> String {
        ms < 1_000 ? String(format: "%.0f ms", ms) : String(format: "%.1f s", ms / 1_000)
    }
}

/// Status wording for action cards and results. Only states the ledger or system actually reported.
public enum ActionStatusLabel {
    public static let awaitingReview = "Needs your review · nothing done yet"
    public static let unverified = "Outcome unverified"
    public static let cancelled = "Cancelled · nothing done"

    public static func label(for phase: AttemptPhase) -> String {
        switch phase {
        case .awaitingUser: return awaitingReview
        case .claimed, .ambiguous: return unverified
        case .settled(let d):
            switch d {
            case .committed: return "Saved on this iPhone"
            case .sheet(let s):
                switch s {
                case .messagesQueuedOrSent: return "Messages sheet completed · delivery not confirmed"
                case .mailQueuedInOutbox: return "Mail queued · delivery not confirmed"
                case .mailDraftSaved: return "Mail draft saved"
                }
            case .handedOff: return "Handed to iOS · result not confirmed"
            case .cancelled: return cancelled
            case .failed: return "Did not run"
            case .read: return "Answered"
            }
        }
    }
}
