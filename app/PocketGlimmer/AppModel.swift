import Foundation
import Network
import Observation
import Contacts
import UserNotifications
import PocketCore
import CryptoKit

struct ChatItem: Identifiable, Equatable {
    enum Role { case user, assistant, system }
    let id = UUID()
    let role: Role
    var text: String
    var badge: String? = nil        // "on device · 42 ms" / "Meta Model API · Muse Spark 1.3 (Standard mode)"
    var card: DraftCard? = nil      // projection of a durable ledger row, never the source of truth
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
        for files in [bundled, inDocs] {
            if let selected = files.first(where: { $0.lastPathComponent.lowercased().contains("reflex") }) ?? files.first { return selected }
        }
        return nil
    }

    nonisolated static func verifyShippingModel(_ url: URL) throws {
        let expectedBytes = 807694080
        let expectedSHA = "a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2"
        let attrs = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard attrs.isRegularFile == true, attrs.isSymbolicLink != true, attrs.fileSize == expectedBytes else {
            throw NSError(domain: "PocketGlimmer.Model", code: 1, userInfo: [NSLocalizedDescriptionKey: "The model does not match the shipping calibration. Install the verified shipping model."])
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == expectedSHA else {
            throw NSError(domain: "PocketGlimmer.Model", code: 2, userInfo: [NSLocalizedDescriptionKey: "Model checksum mismatch. The model was not loaded with the shipping calibration."])
        }
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
            modelState = "Verifying model…"
            try await Task.detached(priority: .userInitiated) { try Self.verifyShippingModel(url) }.value
            // XcodeGen adds Resources/Models as a group, so calibration.json is copied flat to the bundle root; the
            // subdirectory lookup covers a folder-reference setup.
            guard let calURL = Bundle.main.url(forResource: "calibration", withExtension: "json")
                    ?? Bundle.main.url(forResource: "calibration", withExtension: "json", subdirectory: "Models") else {
                throw NSError(domain: "PocketGlimmer.Calibration", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "The bundled calibration file is missing. Reinstall the app with its model resources."])
            }
            let profile = try CalibrationProfile.load(from: calURL)
            var failures: [String] = []
            if profile.defaultTau != 0.90 { failures.append("defaultTau=\(String(format: "%.17g", profile.defaultTau)) bits=\(String(profile.defaultTau.bitPattern, radix: 16))") }
            if profile.promptStyle != .fewShot { failures.append("promptStyle=\(profile.promptStyle)") }
            for (key, value) in profile.tau where value != 0.90 { failures.append("tau[\(key)]=\(value)") }
            for (key, values) in profile.prior where !values.allSatisfy(\.isFinite) { failures.append("nonfinite prior[\(key)]") }
            for set in OptionSets.staticSets {
                let key = DecisionPrompt.priorKey(set)
                if profile.prior[key]?.count != set.activeLetters.count { failures.append("prior[\(key)] count=\(profile.prior[key]?.count.description ?? "missing") expected=\(set.activeLetters.count)") }
            }
            for n in 2...8 {
                for type in ["contactPick", "eventPick", "skillPick"] {
                    let key = "\(type)#\(n)"
                    if profile.prior[key]?.count != n { failures.append("prior[\(key)] count=\(profile.prior[key]?.count.description ?? "missing") expected=\(n)") }
                }
            }
            for (key, value) in profile.temperature where value != 1 { failures.append("temperature[\(key)]=\(value)") }
            if !failures.isEmpty {
                let digest = SHA256.hash(data: try Data(contentsOf: calURL)).map { String(format: "%02x", $0) }.joined()
                throw NSError(domain: "PocketGlimmer.Calibration", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Calibration mismatch (\(calURL.lastPathComponent), SHA256 \(digest)): \(failures.sorted().joined(separator: "; "))"])
            }
            let engine = try await Task.detached(priority: .userInitiated) { try LlamaCppEngine(modelURL: url) }.value
            let reflex = Reflex(engine: engine, profile: profile, telemetry: tel, source: "device")
            let ledger = try EffectLedger(db: db)
            let effects = PocketEffects(events: actions.events, contacts: actions.contacts, memory: mem)
            let a = Assistant(reflex: reflex, memory: mem, actions: actions, ledger: ledger, effects: effects,
                              cloud: CloudSettings.chain(), isOnline: { OnlineFlag.shared.value })
            SkillSetup.install(on: a, memory: mem)   // open-world phone actions (docs/SKILLS.md); idempotent
            assistant = a; telemetry = tel; memory = mem
            restoreEffectCards(a)
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
        let t = Task { () -> Void in
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
        chat.append(.init(role: .user, text: text))
        busy = true; defer { busy = false; refresh() }
        await loadScrubberNames()
        do {
            let turn = try await assistant.handle(text, sharedText: sharedText)
            let rows = turn.decisions.map { DecisionRow($0, toolCallJSON: [.toolChoice, .skillPick].contains($0.type) ? turn.action?.json : nil) }
            for r in rows { decisions.insert(r, at: 0) }
            let reflexMs = turn.decisions.map(\.latencyMs).reduce(0, +)
            let onDevice = String(format: "on device · %.0f ms", reflexMs)
            switch turn.reply {
            case .local(let t):
                chat.append(.init(role: .assistant, text: t,
                                  badge: turn.cloudPromptSent == nil ? onDevice : "local fallback · cloud request attempted",
                                  decisions: rows, cloudPromptSent: turn.cloudPromptSent,
                                  keptOnDevice: turn.cloudWithheldForSensitivity))
            case .acted(let effect): chat.append(.init(role: .assistant, text: effect.summary, badge: onDevice, decisions: rows))
            case .clarify(let t): chat.append(.init(role: .assistant, text: t, badge: onDevice, decisions: rows))
            case .cloud(let t, let p): chat.append(.init(role: .assistant, text: t, badge: prettyProvider(p), decisions: rows, cloudPromptSent: turn.cloudPromptSent))
            case .offlineFallback(let t): chat.append(.init(role: .assistant, text: t, badge: "local fallback · best effort", decisions: rows, cloudPromptSent: turn.cloudPromptSent))
            case .needsConfirmation(let card): chat.append(.init(role: .assistant, text: card.title, badge: onDevice, card: card, decisions: rows))
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

    func confirm(_ item: ChatItem, edits: [DraftEdit] = []) async {
        guard !busy, let assistant,
              let i = chat.firstIndex(where: { $0.id == item.id }),
              let card = chat[i].card else { return }
        busy = true; defer { busy = false; refresh() }
        do {
            let result = try await assistant.confirmEffect(card.attemptID, edits: edits, expectedRevision: card.revision)
            switch result {
            case .staged(let updated):
                chat[i].card = updated
                chat[i].text = updated.title
                if !updated.canConfirm && !updated.notice.isEmpty {
                    chat.append(.init(role: .system, text: updated.notice))
                }
            case .finished(let effect), .ignoredTerminal(let effect):
                chat[i].card = nil
                chat[i].text = effect.summary
            case .read(let read):
                chat[i].card = nil
                chat[i].text = read.text
                chat[i].badge = read.provider.map { prettyProvider($0) }
                    ?? (read.cloudPromptSent == nil ? "on device" : "local fallback · cloud request attempted")
                chat[i].decisions = read.decisions.map { DecisionRow($0) }
                chat[i].cloudPromptSent = read.cloudPromptSent
                chat[i].keptOnDevice = read.withheldForSensitivity
            }
        } catch {
            chat.append(.init(role: .system, text: "Couldn't verify completion: \(error). The request may already have been sent or acted on. Check the destination before starting a new request."))
        }
    }

    /// Persists an edit (contact, method or exact time) without claiming. Body text is passed at Confirm.
    func edit(_ item: ChatItem, edits: [DraftEdit]) async {
        guard !busy, let assistant,
              let i = chat.firstIndex(where: { $0.id == item.id }),
              let card = chat[i].card else { return }
        busy = true; defer { busy = false }
        do {
            let updated = try await assistant.editEffect(card.attemptID, edits: edits, expectedRevision: card.revision)
            chat[i].card = updated
            chat[i].text = updated.title
        } catch {
            chat.append(.init(role: .system, text: "Couldn't update that card: \(error). Nothing was changed."))
        }
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

    func cancel(_ item: ChatItem) async {
        guard !busy, let assistant, let i = chat.firstIndex(where: { $0.id == item.id }), let card = chat[i].card else { return }
        do {
            let effect = try assistant.cancelEffect(card.attemptID)
            chat[i].card = nil
            chat[i].text = effect.summary
        } catch {
            chat.append(.init(role: .system, text: "Couldn't cancel that card: \(error). The card was kept."))
        }
    }

    /// Read-only launch recovery: restore durable cards and warn about claimed rows that have no receipt.
    private func restoreEffectCards(_ assistant: Assistant) {
        do {
            let recovery = try assistant.recoverEffects()
            for card in recovery.showAgain {
                chat.append(.init(role: .assistant, text: card.title, card: card))
            }
            for open in recovery.unresolved {
                chat.append(.init(role: .system, text: open.summary))
            }
        } catch {
            chat.append(.init(role: .system, text: "Couldn't read saved actions: \(error)"))
        }
    }

    func forget(_ f: MemoryFact) { try? memory?.forget(id: f.id); refresh() }
    /// Writes escalated decisions (JSONL, schema fixed for training/round2/) into Documents, visible in Files / Finder.
    /// Returns (file, row count). The app does not upload the export; device backups may include it.
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
        let metaModel = (d.string(forKey: "meta_model") ?? "muse-spark-1.3").trimmingCharacters(in: .whitespacesAndNewlines)
        if let k = Keychain.get("meta_key"), !k.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !metaModel.isEmpty {
            b.append(CloudPresets.metaModelAPI(model: metaModel, apiKey: k))
        }
        if let k = Keychain.get("byok_key"), let u = d.string(forKey: "byok_url").flatMap(URL.init(string:)) {
            let model = (d.string(forKey: "byok_model") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if OpenAICompatibleBrain.validConfiguration(model: model, baseURL: u, apiKey: k) {
                b.append(CloudPresets.custom(name: "Custom", model: model, baseURL: u, apiKey: k))
            }
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
