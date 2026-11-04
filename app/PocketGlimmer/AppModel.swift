import Foundation
import Network
import Observation
import Contacts
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
    var keptOnDevice = false             // cloud was available but withheld for sensitivity
}

struct DecisionRow: Identifiable, Equatable {
    let id = UUID()
    let type: String, choice: String, confidence: Double, ms: Double, escalated: Bool, at: Date
    var tau: Double = 0.9            // overwritten from ReflexDecision.tau in init
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
    var onePager = ""                    // the profile the on-device model always sees (MemoryStore.profileOnePager)
    var board = TaskBoard()
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
        let bundled = (Bundle.main.urls(forResourcesWithExtension: "gguf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "gguf", subdirectory: "Models") ?? [])
        let all = inDocs + bundled
        return all.first { $0.lastPathComponent.lowercased().contains("reflex") } ?? all.first
    }

    @ObservationIgnored private var bootTask: Task<Void, Never>?
    @ObservationIgnored private var scrubberNamesTask: Task<Void, Never>?

    /// Single-flight: the app's `.task` and an App Intent (Ask / Trigger) can both call boot() during launch; without this
    /// both pass the `assistant == nil` check across the model-load await and load two copies of the GGUF.
    func boot() async {
        if assistant != nil { return }
        if let t = bootTask { await t.value; return }
        let t = Task { await bootOnce() }
        bootTask = t
        await t.value
        if assistant == nil { bootTask = nil }      // failed (e.g. no model yet): allow a later retry
    }

    private func bootOnce() async {
        guard assistant == nil else { return }
        do {
            let db = try SQLiteDB(path: Self.dataDir.appendingPathComponent("pocket.sqlite").path)
            let tel = try TelemetryLog(db: db)
            let mem = try MemoryStore(db: db)
            _ = try? mem.consolidateIfDue()      // daily reconciliation: dedupe, supersede, purge, budget
            guard let url = Self.findModel() else { modelState = "No model file. Add a .gguf (see README)."; return }
            // XcodeGen adds Resources/Models as a group, so calibration.json is copied flat to the bundle root; the
            // subdirectory lookup covers a folder-reference setup.
            guard let calURL = Bundle.main.url(forResource: "calibration", withExtension: "json")
                    ?? Bundle.main.url(forResource: "calibration", withExtension: "json", subdirectory: "Models") else {
                throw NSError(domain: "PocketGlimmer.Calibration", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "The bundled calibration file is missing. Reinstall the app with its model resources."])
            }
            let profile = try CalibrationProfile.load(from: calURL)
            let dynamicPriorsPresent = (2...8).allSatisfy { n in
                ["contactPick", "eventPick", "skillPick"].allSatisfy { profile.prior["\($0)#\(n)"]?.count == n }
            }
            guard profile.defaultTau == 0.90,
                  profile.promptStyle == .fewShot,
                  profile.tau.values.allSatisfy({ $0 == 0.90 }),
                  profile.prior.values.allSatisfy({ $0.allSatisfy(\.isFinite) }),
                  OptionSets.staticSets.allSatisfy({ profile.prior[DecisionPrompt.priorKey($0)]?.count == $0.activeLetters.count }),
                  dynamicPriorsPresent,
                  profile.temperature.values.allSatisfy({ $0 == 1 }) else {
                throw NSError(domain: "PocketGlimmer.Calibration", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "The bundled calibration file does not match the shipping settings. Reinstall the app with its model resources."])
            }
            let engine = try await Task.detached(priority: .userInitiated) { try LlamaCppEngine(modelURL: url) }.value
            let reflex = Reflex(engine: engine, profile: profile, telemetry: tel, source: "device")
            let a = Assistant(reflex: reflex, memory: mem, actions: actions, cloud: CloudSettings.chain(), isOnline: { OnlineFlag.shared.value })
            SkillSetup.install(on: a, memory: mem)   // open-world phone actions (docs/SKILLS.md); idempotent
            assistant = a; telemetry = tel; memory = mem
            await loadScrubberNames()
            let pe = ProactiveEngine(memory: mem, reflex: reflex)
            let acts = actions
            pe.todayEvents = { day in acts.eventsOn(day) }
            proactive = pe
            modelState = engine.modelName
            refresh()
        } catch { modelState = "Model failed to load: \(error)" }
    }


    /// Contact full names + given names for PrivacyScrubber (read on device, never sent). Empty without Contacts access.
    /// Trade-off: a given name that is also a word ("Will", "May") is masked in that word's sense too; restore() puts it back.
    nonisolated static func contactNames() async -> [String] {
        await Task.detached(priority: .utility) { () -> [String] in
            let st = CNContactStore.authorizationStatus(for: .contacts)
            guard st == .authorized || st == .limited else { return [] }
            var names = Set<String>()
            let req = CNContactFetchRequest(keysToFetch: [CNContactGivenNameKey, CNContactFamilyNameKey] as [CNKeyDescriptor])
            try? CNContactStore().enumerateContacts(with: req) { c, _ in
                let full = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                for n in [full, c.givenName] where n.count > 2 { names.insert(n) }
            }
            return Array(names)
        }.value
    }

    func refreshScrubberNames() async { await loadScrubberNames() }

    // Read again before each request: limited-access selections and contact names can change without a new grant.
    private func loadScrubberNames() async {
        if let t = scrubberNamesTask { await t.value; return }
        guard assistant != nil else { return }
        let t = Task {
            self.assistant?.scrubber.knownNames = await Self.contactNames()
        }
        scrubberNamesTask = t
        await t.value
        scrubberNamesTask = nil
    }

    func reloadCloud() { assistant?.cloud = CloudSettings.chain() }

    func refresh() {
        facts = (try? memory?.active()) ?? []
        corrections = (try? memory?.corrections()) ?? []
        onePager = (try? memory?.profileOnePager(maxChars: 1200)) ?? ""
        board = (try? memory?.tasksBoard()) ?? TaskBoard()
        daily = (try? telemetry?.dailyShare()) ?? []
        rounds = (try? telemetry?.shareByModel()) ?? []
    }

    @discardableResult
    func send(_ text: String, sharedText: String? = nil, source: String = "share") async -> String {
        guard !busy else { return "I'm working on another request. Please try again shortly." }
        guard let assistant else { return modelState }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "No request was provided." }
        if let sharedText { SharedInbox.shared.put(sharedText, source: source) }
        chat.append(.init(role: .user, text: text))
        busy = true; defer { busy = false; refresh() }
        await loadScrubberNames()
        do {
            let turn = try await assistant.handle(text)
            let rows = turn.decisions.map { DecisionRow($0, toolCallJSON: [.toolChoice, .skillPick].contains($0.type) ? turn.action?.json : nil) }
            for r in rows { decisions.insert(r, at: 0) }
            let reflexMs = turn.decisions.map(\.latencyMs).reduce(0, +)
            let onDevice = String(format: "on device · %.0f ms", reflexMs)
            switch turn.reply {
            case .local(let t): chat.append(.init(role: .assistant, text: t, badge: onDevice, decisions: rows, keptOnDevice: turn.cloudWithheldForSensitivity))
            case .acted(let t): chat.append(.init(role: .assistant, text: t, badge: onDevice, decisions: rows))
            case .clarify(let t): chat.append(.init(role: .assistant, text: t, badge: onDevice, decisions: rows))
            case .cloud(let t, let p): chat.append(.init(role: .assistant, text: t, badge: prettyProvider(p), decisions: rows, cloudPromptSent: turn.cloudPromptSent))
            case .offlineFallback(let t): chat.append(.init(role: .assistant, text: t, badge: "offline · best effort on device", decisions: rows))
            case .needsConfirmation(let a, let prompt): chat.append(.init(role: .assistant, text: prompt, badge: onDevice, pending: a, decisions: rows))
            }
            let reply = chat.last?.text ?? ""
            for c in turn.corrections { chat.append(.init(role: .system, text: "Corrected: \(c.old.value) → \(c.new.value)")) }
            if !turn.remembered.isEmpty {
                chat.append(.init(role: .system, text: "Remembered: " + turn.remembered.map(\.text).joined(separator: " · ")))
            }
            return reply
        } catch {
            let message = "Error: \(error.localizedDescription)"
            chat.append(.init(role: .system, text: message))
            return message
        }
    }

    func confirm(_ item: ChatItem) async {
        guard !busy, let assistant,
              let i = chat.firstIndex(where: { $0.id == item.id }),
              let a = chat[i].pending else { return }
        chat[i].pending = nil
        busy = true; defer { busy = false; refresh() }
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
        guard let i = chat.firstIndex(where: { $0.id == item.id }), chat[i].pending != nil else { return }
        chat[i].pending = nil
        chat.append(.init(role: .system, text: "Cancelled."))
    }

    func forget(_ f: MemoryFact) { try? memory?.forget(id: f.id); refresh() }
    /// Writes escalated decisions (JSONL, schema fixed for training/round2/) into Documents, visible in Files / Finder.
    /// Stays on this phone until the user shares the file; nothing is uploaded. Returns (file, row count).
    func exportDistillation() -> (url: URL, rows: Int)? {
        guard let jsonl = try? telemetry?.exportDistillationQueue(sinceDays: 30) else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let u = docs.appendingPathComponent("distillation-queue.jsonl")
        guard (try? jsonl.write(to: u, atomically: true, encoding: .utf8)) != nil else { return nil }
        return (u, jsonl.split(separator: "\n").count)
    }

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
