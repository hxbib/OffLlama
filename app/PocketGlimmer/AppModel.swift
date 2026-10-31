import Foundation
import Network
import Observation
import UserNotifications
import PocketCore

struct ChatItem: Identifiable, Equatable {
    enum Role { case user, assistant, system }
    let id = UUID()
    let role: Role
    var text: String
    var badge: String? = nil        // "on device · 42 ms" / "Meta Model API · Muse Spark 1.3 (Standard mode)"
    var pending: PlannedAction? = nil
    var decisions: [DecisionRow] = []
    var cloudPromptSent: String? = nil   // masked text that actually left the phone
}

struct DecisionRow: Identifiable, Equatable {
    let id = UUID()
    let type: String, choice: String, confidence: Double, ms: Double, escalated: Bool, at: Date
    var tau: Double = 0.8
    var probabilities: [(id: String, p: Double)] = []
    var toolCallJSON: String? = nil
    static func == (a: DecisionRow, b: DecisionRow) -> Bool { a.id == b.id }

    init(_ d: ReflexDecision, toolCallJSON: String? = nil) {
        type = d.type.rawValue; choice = d.argmax.id; confidence = d.confidence; ms = d.latencyMs; escalated = d.escalated; at = Date()
        tau = d.tau
        probabilities = d.probabilities.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
        self.toolCallJSON = toolCallJSON
    }
}

/// "Meta Model API · muse-spark-1.3" -> "Meta Model API · Muse Spark 1.3 (Standard mode)"
func prettyProvider(_ raw: String) -> String {
    let parts = raw.components(separatedBy: " · ")
    guard parts.count == 2 else { return raw }
    let m = parts[1]
    let names = ["muse-spark-1.3": "Muse Spark 1.3 (Standard mode)", "muse-spark-1.3-contributor": "Muse Spark 1.3 (Contributor mode)",
                 "muse-wonder-1.0": "Muse Wonder", "accounts/fireworks/models/muse-spark-open": "Muse Spark Open",
                 "accounts/fireworks/models/muse-glimmer-30b": "Muse Glimmer 30B", "muse-glimmer": "Muse Glimmer 30B"]
    return "\(parts[0]) · \(names[m] ?? m)"
}

/// Single source of truth for the UI. All model work happens off the main actor inside PocketCore + the engine actor.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    var chat: [ChatItem] = []
    var decisions: [DecisionRow] = []
    var facts: [MemoryFact] = []
    var corrections: [(old: MemoryFact, new: MemoryFact)] = []
    var rounds: [(model: String, total: Int, handledLocally: Int)] = []
    var daily: [DailyReflexShare] = []
    var isOnline = false
    var modelState: String = "Loading model…"
    var busy = false
    var onboarded = UserDefaults.standard.bool(forKey: "onboarded") { didSet { UserDefaults.standard.set(onboarded, forKey: "onboarded") } }

    private(set) var assistant: Assistant?
    private(set) var proactive: ProactiveEngine?
    private(set) var telemetry: TelemetryLog?
    private(set) var memory: MemoryStore?
    let actions = SystemActions()
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let up = path.status == .satisfied
            OnlineFlag.shared.value = up
            Task { @MainActor in AppModel.shared.isOnline = up }
        }
        monitor.start(queue: .global(qos: .utility))
    }

    static var dataDir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PocketGlimmer")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// Model lookup: bundled Resources/Models/*.gguf, or a file the user put in the app's Documents via Finder.
    static func findModel() -> URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let inDocs = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "gguf" } ?? []
        let bundled = Bundle.main.urls(forResourcesWithExtension: "gguf", subdirectory: nil) ?? []
        let all = inDocs + bundled
        return all.first { $0.lastPathComponent.lowercased().contains("reflex") } ?? all.first
    }

    func boot() async {
        guard assistant == nil else { return }
        do {
            let db = try SQLiteDB(path: Self.dataDir.appendingPathComponent("pocket.sqlite").path)
            let tel = try TelemetryLog(db: db)
            let mem = try MemoryStore(db: db)
            guard let url = Self.findModel() else { modelState = "No model file. Add a .gguf (see README)."; return }
            let engine = try await Task.detached(priority: .userInitiated) { try LlamaCppEngine(modelURL: url) }.value
            var profile = CalibrationProfile.uncalibrated
            if let cal = Bundle.main.url(forResource: "calibration", withExtension: "json"), let p = try? CalibrationProfile.load(from: cal) { profile = p }
            let reflex = Reflex(engine: engine, profile: profile, telemetry: tel, source: "device")
            let a = Assistant(reflex: reflex, memory: mem, actions: actions, cloud: CloudSettings.chain(), isOnline: { OnlineFlag.shared.value })
            assistant = a; telemetry = tel; memory = mem
            proactive = ProactiveEngine(memory: mem, reflex: reflex)
            modelState = engine.modelName
            refresh()
        } catch { modelState = "Model failed to load: \(error)" }
    }


    func reloadCloud() { assistant?.cloud = CloudSettings.chain() }

    func refresh() {
        facts = (try? memory?.active()) ?? []
        corrections = (try? memory?.corrections()) ?? []
        daily = (try? telemetry?.dailyShare()) ?? []
        rounds = (try? telemetry?.shareByModel()) ?? []
    }

    func send(_ text: String) async {
        guard let assistant, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        chat.append(.init(role: .user, text: text))
        busy = true; defer { busy = false; refresh() }
        do {
            let turn = try await assistant.handle(text)
            let rows = turn.decisions.map { DecisionRow($0, toolCallJSON: $0.type == .toolChoice ? turn.action?.json : nil) }
            for r in rows { decisions.insert(r, at: 0) }
            let reflexMs = turn.decisions.map(\.latencyMs).reduce(0, +)
            let onDevice = String(format: "on device · %.0f ms", reflexMs)
            switch turn.reply {
            case .local(let t): chat.append(.init(role: .assistant, text: t, badge: onDevice, decisions: rows))
            case .acted(let t): chat.append(.init(role: .assistant, text: t, badge: onDevice, decisions: rows))
            case .clarify(let t): chat.append(.init(role: .assistant, text: t, badge: onDevice, decisions: rows))
            case .cloud(let t, let p): chat.append(.init(role: .assistant, text: t, badge: prettyProvider(p), decisions: rows, cloudPromptSent: turn.cloudPromptSent))
            case .offlineFallback(let t): chat.append(.init(role: .assistant, text: t, badge: "offline · best effort on device", decisions: rows))
            case .needsConfirmation(let a, let prompt): chat.append(.init(role: .assistant, text: prompt, badge: onDevice, pending: a, decisions: rows))
            }
            for c in turn.corrections { chat.append(.init(role: .system, text: "Corrected: \(c.old.value) → \(c.new.value)")) }
            if !turn.remembered.isEmpty {
                chat.append(.init(role: .system, text: "Remembered: " + turn.remembered.map(\.text).joined(separator: " · ")))
            }
        } catch { chat.append(.init(role: .system, text: "Error: \(error.localizedDescription)")) }
    }

    func confirm(_ item: ChatItem) async {
        guard let a = item.pending, let assistant else { return }
        if let i = chat.firstIndex(of: item) { chat[i].pending = nil }
        if case .acted(let t) = (try? await assistant.confirm(a)) ?? .acted("Failed") { chat.append(.init(role: .assistant, text: t)) }
    }

    /// Entry point for Shortcuts automations (App Intent). Returns the nudges it posted.
    func handleTrigger(_ t: Trigger) async -> [Nudge] {
        if assistant == nil { await boot() }
        guard let proactive else { return [] }
        let nudges = (try? await proactive.handle(t)) ?? []
        for n in nudges {
            let c = UNMutableNotificationContent(); c.title = n.title; c.body = n.body
            c.subtitle = String(format: "Reflex %.0f%% sure", n.confidence * 100)
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
        refresh()
        return nudges
    }

    func cancel(_ item: ChatItem) {
        if let i = chat.firstIndex(of: item) { chat[i].pending = nil }
        chat.append(.init(role: .system, text: "Cancelled."))
    }

    func forget(_ f: MemoryFact) { try? memory?.forget(id: f.id); refresh() }
    func exportCSV() -> URL? {
        guard let csv = try? telemetry?.csv() else { return nil }
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("reflex-telemetry.csv")
        try? csv.write(to: u, atomically: true, encoding: .utf8); return u
    }
}

/// Cloud brains: Meta first. Keys in Keychain; model ids editable in Settings.
enum CloudSettings {
    static func chain() -> CloudBrainChain {
        var b: [CloudBrain] = []
        let d = UserDefaults.standard
        if let k = Keychain.get("meta_key") { b.append(CloudPresets.metaModelAPI(model: d.string(forKey: "meta_model") ?? "muse-spark-1.3", apiKey: k)) }
        if let k = Keychain.get("fireworks_key") { b.append(CloudPresets.fireworks(model: d.string(forKey: "fireworks_model") ?? "accounts/fireworks/models/muse-glimmer-30b", apiKey: k)) }
        if let k = Keychain.get("byok_key"), let u = d.string(forKey: "byok_url").flatMap(URL.init(string:)) {
            b.append(CloudPresets.custom(name: "Custom", model: d.string(forKey: "byok_model") ?? "", baseURL: u, apiKey: k))
        }
        return CloudBrainChain(b)
    }
}

/// Thread-safe network flag readable from PocketCore's background work.
final class OnlineFlag: @unchecked Sendable {
    static let shared = OnlineFlag()
    private let lock = NSLock(); private var v = false
    var value: Bool { get { lock.lock(); defer { lock.unlock() }; return v } set { lock.lock(); v = newValue; lock.unlock() } }
}
