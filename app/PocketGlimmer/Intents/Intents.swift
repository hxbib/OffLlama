import AppIntents
import PocketCore

/// Shortcuts personal automations (Time of Day, Arrive/Leave, Email, Message, Charger) call this intent.
/// It runs without opening the app; Reflex decides whether a memory is worth a nudge right now.
enum TriggerKindEntity: String, AppEnum {
    case time, arrive, leave, email, message, charger
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Trigger"
    static let caseDisplayRepresentations: [TriggerKindEntity: DisplayRepresentation] = [
        .time: "Time of day", .arrive: "Arrive", .leave: "Leave", .email: "Email", .message: "Message", .charger: "Charger"]
}

struct ProactiveTriggerIntent: AppIntent {
    static let title: LocalizedStringResource = "Pocket Glimmer Trigger"
    static let description = IntentDescription("Let Pocket Glimmer check its memory for something relevant to this moment.")
    static let openAppWhenRun = false

    @Parameter(title: "Trigger") var kind: TriggerKindEntity
    @Parameter(title: "Place") var place: String?
    @Parameter(title: "Sender") var sender: String?
    @Parameter(title: "Text") var text: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$kind) trigger") { \.$place; \.$sender; \.$text }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let t = Trigger(kind: TriggerKind(rawValue: kind.rawValue) ?? .time, date: Date(), place: place, sender: sender, text: text)
        let nudges = await AppModel.shared.handleTrigger(t)
        return .result(value: nudges.map(\.body).joined(separator: "\n"))
    }
}

struct AskPocketGlimmerIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Pocket Glimmer"
    static let openAppWhenRun = true
    @Parameter(title: "Request") var request: String

    @MainActor
    func perform() async throws -> some IntentResult {
        await AppModel.shared.boot()
        await AppModel.shared.send(request)
        return .result()
    }
}

struct PocketGlimmerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskPocketGlimmerIntent(), phrases: ["Ask \(.applicationName)"], shortTitle: "Ask", systemImageName: "sparkle")
        AppShortcut(intent: ProactiveTriggerIntent(), phrases: ["\(.applicationName) check in"], shortTitle: "Check in", systemImageName: "bolt")
    }
}
