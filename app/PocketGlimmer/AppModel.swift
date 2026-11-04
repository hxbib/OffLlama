import Foundation
import Network
import Observation
import Contacts
import UserNotifications
import PocketCore
import CryptoKit

struct ChatItem: Identifiable, Equatable {
    enum Role { case user, assistant, system }
    var id = UUID()
    let role: Role
    var text: String
    var badge: String? = nil        // plain status or provider, e.g. "On device · answered in 1.8 s"
    var card: DraftCard? = nil      // projection of a durable ledger row, never the source of truth
    var decisions: [DecisionRow] = []
    var cloudPromptSent: String? = nil   // screened text from a cloud request attempt
    var keptOnDevice = false             // cloud was available but withheld for sensitivity
    var attemptID: AttemptID? = nil      // ledger attempt this message projects, if any
    var detail: String? = nil            // timing and rule notes, shown under Details
    var ephemeral = false                // rebuilt from the ledger each launch, not written to disk
    /// A waiting card or an unverified outcome. Clear keeps these and Delete refuses while one exists.
    var isPendingAction: Bool { card != nil || (attemptID != nil && badge == ActionStatusLabel.unverified) }
}

/// Display-only extras of a stored message. Never persisted: cards come from the ledger, decisions are diagnostics.
struct ChatExtras {
    var card: DraftCard?
    var decisions: [DecisionRow]
    var cloudPromptSent: String?
    var detail: String?
}

struct DecisionRow: Identifiable, Equatable {
    let id = UUID()
    let type: String, choice: String, confidence: Double, ms: Double, escalated: Bool, at: Date
    var tau: Double = 0.9            // overwritten from ReflexDecision.tau in init
    var probabilities: [(id: String, p: Double)] = []
    var toolCallJSON: String? = nil
    // Plain wording for primary surfaces. `type`, `choice` and `probabilities` stay raw for Details and exports.
    var titleText = ""
    var choiceText = ""
    var topChoiceNote: String? = nil
    var certaintyText = ""
    static func == (a: DecisionRow, b: DecisionRow) -> Bool { a.id == b.id }

    init(_ d: ReflexDecision, toolCallJSON: String? = nil, skillTitle: (String) -> String? = { _ in nil }) {
        type = d.type.rawValue; choice = d.argmax.id; confidence = d.confidence; ms = d.latencyMs; escalated = d.escalated; at = Date()
        tau = d.tau
        probabilities = d.probabilities.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
        self.toolCallJSON = toolCallJSON
        titleText = DecisionPresentation.title(d.type)
        choiceText = DecisionPresentation.choice(d.type, id: d.chosen.id, skillTitle: skillTitle)
        topChoiceNote = DecisionPresentation.chosenVersusTop(chosen: d.chosen.id, top: d.argmax.id, escalated: d.escalated)
            .map { "Top option: \(DecisionPresentation.choice(d.type, id: d.argmax.id, skillTitle: skillTitle)). \($0)" }
        certaintyText = DecisionPresentation.certainty(confidence: d.confidence, tau: d.tau)
    }
}

/// "Meta Model API · muse-spark-1.3" -> "Meta Model API · Muse Spark 1.3 (Standard mode)"
func prettyProvider(_ raw: String) -> String {
    let parts = raw.components(separatedBy: " · ")
    guard parts.count == 2 else { return raw }
    let m = parts[1]
    let names = ["muse-spark-1.3": "Muse Spark 1.3 (Standard mode)", "muse-spark-1.2": "Muse Spark 1.2 (Standard mode)", "muse-spark-1.1": "Muse Spark 1.1 (Standard mode)", "muse-spark-1.3-contributor": "Muse Spark 1.3 (Contributor mode)",
                 "muse-wonder-1.0": "Muse Wonder", "accounts/fireworks/models/muse-spark-open": "Muse Spark Open",
                 "accounts/fireworks/models/muse-glimmer-30b": "Muse Glimmer 30B", "muse-glimmer": "Muse Glimmer 30B"]
    return "\(parts[0]) · \(names[m] ?? m)"
}

/// Single source of truth for the UI. All model work happens off the main actor inside PocketCore + the engine actor.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    /// All chats. Each message, unfinished message draft and in-flight result belongs to exactly one conversation.
    private(set) var book: ConversationBook
    private(set) var extras: [UUID: ChatExtras] = [:]
    /// Honest history status shown above the composer (save failed, chat full, history set aside).
    var historyNotice: String?
    private(set) var busyConversationID: ConversationID?
    /// The route decision of the latest answered turn in the ACTIVE chat, for the strip above the composer.
    var lastRoute: DecisionRow? {
        for item in chat.reversed() where item.role == .assistant {
            if let r = item.decisions.first(where: { $0.type == DecisionType.route.rawValue }) { return r }
        }
        return nil
    }
    @ObservationIgnored private let historyStore: ConversationStore
    @ObservationIgnored private var savingEnabled = true
    var chat: [ChatItem] { items(for: book.activeID) }
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
        let store = ConversationStore(directory: AppModel.dataDir.appendingPathComponent("Conversations"))
        historyStore = store
        var loaded = ConversationBook()
        var notice: String?
        var canSave = true
        switch Result(catching: { try store.load() }) {
        case .success(.loaded(let b)): loaded = b
        case .success(.empty): break
        case .success(.unreadable):
            notice = "Saved chat history could not be read. It was kept aside on this iPhone and a new history started."
        case .failure(let e):
            notice = "\(e) This session's chats will not be saved."
            canSave = false
        }
        book = loaded; historyNotice = notice; savingEnabled = canSave
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
            let dropped = try LedgerRequestIndex.reconcile(&book, db: db)
            if dropped > 0 { noteHistory("\(dropped) unfinished message draft\(dropped == 1 ? " was" : "s were") discarded because \(dropped == 1 ? "its" : "their") action was already prepared.") }
            let effects = PocketEffects(events: actions.events, contacts: actions.contacts, memory: mem)
            let a = Assistant(reflex: reflex, memory: mem, actions: actions, ledger: ledger, effects: effects,
                              cloud: CloudSettings.chain(), isOnline: { OnlineFlag.shared.value })
            SkillSetup.install(on: a, memory: mem)   // open-world phone actions (docs/SKILLS.md); idempotent
            assistant = a; telemetry = tel; memory = mem
            restoreHistory(a)
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

    // MARK: conversations

    func items(for cid: ConversationID) -> [ChatItem] {
        (book.conversation(cid)?.messages ?? []).map(item(from:))
    }

    private func item(from m: StoredMessage) -> ChatItem {
        let x = extras[m.id]
        let role: ChatItem.Role = m.role == .user ? .user : (m.role == .assistant ? .assistant : .system)
        return ChatItem(id: m.id, role: role, text: m.text, badge: m.badge, card: x?.card, decisions: x?.decisions ?? [],
                        cloudPromptSent: x?.cloudPromptSent, keptOnDevice: m.keptOnDevice,
                        attemptID: m.attemptID.map { AttemptID(raw: $0) }, detail: x?.detail, ephemeral: m.ephemeral)
    }

    private func storedRole(_ r: ChatItem.Role) -> StoredRole { r == .user ? .user : (r == .assistant ? .assistant : .system) }

    var activeConversationID: ConversationID { book.activeID }

    /// Append to the conversation that owns the work, never to whichever chat happens to be on screen.
    func post(_ item: ChatItem, in cid: ConversationID? = nil) {
        append(item, to: cid ?? book.activeID)
        persist()
    }

    private func append(_ original: ChatItem, to cid: ConversationID) {
        var item = original
        let limit = ConversationLimits.standard.maxMessageCharacters
        if item.text.count > limit {
            item.text = String(item.text.prefix(limit - 60)) + "\n… (shortened to fit chat history)"
            noteHistory("A long message was shortened to fit chat history.")
        }
        let stored = StoredMessage(id: item.id, role: storedRole(item.role), text: item.text, badge: item.badge,
                                   attemptID: item.attemptID?.raw, pendingAction: item.isPendingAction,
                                   keptOnDevice: item.keptOnDevice, ephemeral: item.ephemeral)
        do { try book.append(stored, to: cid) } catch { noteHistory("\(error)"); return }
        setExtras(item)
    }

    private func setExtras(_ item: ChatItem) {
        if item.card != nil || !item.decisions.isEmpty || item.cloudPromptSent != nil || item.detail != nil {
            extras[item.id] = ChatExtras(card: item.card, decisions: item.decisions, cloudPromptSent: item.cloudPromptSent, detail: item.detail)
        } else {
            extras[item.id] = nil
        }
    }

    private func mutate(_ id: UUID, _ change: (inout ChatItem) -> Void) {
        guard let owner = book.owner(ofMessage: id), let stored = book.conversation(owner.conversation)?.messages[owner.index] else { return }
        var it = item(from: stored)
        change(&it)
        book.update(messageID: id, in: owner.conversation) { m in
            m.text = it.text; m.badge = it.badge; m.attemptID = it.attemptID?.raw
            m.pendingAction = it.isPendingAction; m.keptOnDevice = it.keptOnDevice
        }
        setExtras(it)
    }

    private func chatItem(_ id: UUID) -> (item: ChatItem, conversation: ConversationID)? {
        guard let o = book.owner(ofMessage: id), let m = book.conversation(o.conversation)?.messages[o.index] else { return nil }
        return (item(from: m), o.conversation)
    }

    @ObservationIgnored private var noticeIsSaveFailure = false

    private func noteHistory(_ text: String, saveFailure: Bool = false) {
        historyNotice = text; noticeIsSaveFailure = saveFailure
    }

    private func persist() {
        guard savingEnabled else { return }
        do {
            try historyStore.save(book)
            if noticeIsSaveFailure { historyNotice = nil; noticeIsSaveFailure = false }
        } catch {
            noteHistory("\(error) Recent chat may be lost if the app closes.", saveFailure: true)
        }
    }

    private func pruneExtras() {
        let live = Set(book.conversations.flatMap { $0.messages.map(\.id) })
        extras = extras.filter { live.contains($0.key) }
    }

    /// What the file system reports for the saved history right now, for a visible phone-side check.
    var historyStorageStatus: String {
        guard FileManager.default.fileExists(atPath: historyStore.fileURL.path) else { return "Nothing is saved to disk yet." }
        let r = historyStore.attributeReadback()
        let protection = r.protection == FileProtectionType.complete.rawValue ? "complete (unreadable while the iPhone is locked)" : (r.protection ?? "not reported")
        return "Storage check: protection \(protection); backups \(r.excludedFromBackup == true ? "excluded" : "not excluded")."
    }

    func newChat() -> String? {
        do { try book.newConversation(); persist(); return nil } catch { return "\(error)" }
    }

    func selectChat(_ id: ConversationID) {
        try? book.select(id); persist()
    }

    /// Clearing removes only ordinary messages and unfinished message drafts in this chat. It never cancels, replays
    /// or erases a waiting or unverified action (the effect ledger owns those), and it does not touch saved memory.
    func clearChat(_ id: ConversationID) -> String {
        if busyConversationID == id { return "This chat is working on a request. Try again when it finishes." }
        do {
            let r = try book.clear(id)
            pruneExtras(); persist()
            var text = "Cleared \(r.removed) message\(r.removed == 1 ? "" : "s")."
            if r.keptPending > 0 { text += " \(r.keptPending) waiting or unverified action\(r.keptPending == 1 ? "" : "s") stayed here." }
            return text
        } catch { return "\(error)" }
    }

    func deleteChat(_ id: ConversationID) -> String? {
        if busyConversationID == id { return "This chat is working on a request. Try again when it finishes." }
        do { try book.delete(id); pruneExtras(); persist(); return nil } catch { return "\(error)" }
    }

    private func skillTitle(_ id: String) -> String? { assistant?.skills?.skill(id: id)?.title }
    private func row(_ d: ReflexDecision, json: String? = nil) -> DecisionRow {
        DecisionRow(d, toolCallJSON: json, skillTitle: { [weak self] in self?.skillTitle($0) })
    }

    private func ruleNote(_ turn: AssistantTurn, text: String) -> String? {
        if turn.followUp != nil { return "Continued your unfinished message by rule, not by a model choice." }
        guard let route = turn.decisions.first(where: { $0.type == .route }), route.chosen.id != "tool",
              let tool = turn.action?.tool else { return nil }
        let chart = tool == ActionPlanner.toolPrefix + "html_viz"
        guard chart || MessageCommand.isExplicitMessageRequest(text) else { return nil }
        return "A built-in rule handled this as \(chart ? "a chart request" : "a message request"); the model's route choice was “\(DecisionPresentation.choice(.route, id: route.chosen.id))”."
    }

    /// Why a message would be refused before any work starts, so the caller can keep the typed text.
    func sendRefusal(for text: String) -> String? {
        let limits = ConversationLimits.standard
        if text.count > limits.maxMessageCharacters { return "That message is longer than \(limits.maxMessageCharacters) characters." }
        if !book.hasRoomForTurn(in: book.activeID) { return ConversationError.chatFull(limit: limits.maxMessagesPerConversation).description }
        return nil
    }

    func showNotice(_ text: String) { noteHistory(text) }

    @discardableResult
    func send(_ text: String, sharedText: String? = nil, source: String = "share") async -> String {
        guard !busy else { return "I'm working on another request. Please try again shortly." }
        guard let assistant else { return modelState }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "No request was provided." }
        let cid = book.activeID                       // in-flight work is bound to this chat
        if let why = sendRefusal(for: text) { noteHistory(why); return why }
        let context = ConversationContext.render(book.conversation(cid)?.messages ?? [])
        let drafts = book.conversation(cid)?.drafts ?? []
        append(.init(role: .user, text: text), to: cid)
        busy = true; busyConversationID = cid
        defer { busy = false; busyConversationID = nil; refresh(); persist() }
        persist()
        await loadScrubberNames()
        let clock = ContinuousClock()
        let started = clock.now
        do {
            var turn = try await assistant.handle(text, sharedText: sharedText, pendingDrafts: drafts, conversationContext: context)
            var kept = drafts
            if !turn.consumedDrafts.isEmpty { kept.removeAll { turn.consumedDrafts.contains($0.requestID) } }
            if let d = turn.pendingDraft {
                if kept.count >= ConversationLimits.standard.maxDraftsPerConversation && !kept.contains(where: { $0.requestID == d.requestID }) {
                    turn.reply = .clarify("Five unfinished messages are waiting in this chat. Finish or cancel one before starting another. This new message was not saved as a draft.")
                } else {
                    kept.removeAll { $0.requestID == d.requestID }
                    kept.append(d)
                }
            }
            book.setDrafts(kept, for: cid)
            let rows = turn.decisions.map { row($0, json: [.toolChoice, .skillPick].contains($0.type) ? turn.action?.json : nil) }
            for r in rows { decisions.insert(r, at: 0) }
            let elapsed = clock.now - started
            let elapsedMs = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            let classifierMs = turn.decisions.map(\.latencyMs).reduce(0, +)
            var detail = "Answered in \(DecisionPresentation.seconds(elapsedMs)). The \(turn.decisions.count) model decision\(turn.decisions.count == 1 ? "" : "s") took \(DecisionPresentation.seconds(classifierMs)) in total; that is only the deciding part, not the whole answer time."
            if let note = ruleNote(turn, text: text) { detail += "\n" + note }
            let onDevice = "On device · answered in \(DecisionPresentation.seconds(elapsedMs))"
            let id = UUID()
            func reply(_ t: String, badge: String?, card: DraftCard? = nil, sent: String? = nil, kept: Bool = false, attempt: AttemptID? = nil) {
                append(.init(id: id, role: .assistant, text: t, badge: badge, card: card, decisions: rows, cloudPromptSent: sent,
                             keptOnDevice: kept, attemptID: attempt, detail: detail), to: cid)
            }
            switch turn.reply {
            case .local(let t):
                reply(t, badge: turn.cloudPromptSent == nil ? onDevice : "On device · answered after a cloud attempt",
                      sent: turn.cloudPromptSent, kept: turn.cloudWithheldForSensitivity)
            case .acted(let effect): reply(effect.summary, badge: ActionStatusLabel.label(for: effect.phase), attempt: effect.attemptID)
            case .clarify(let t): reply(t, badge: onDevice)
            case .cloud(let t, let p): reply(t, badge: prettyProvider(p), sent: turn.cloudPromptSent)
            case .offlineFallback(let t): reply(t, badge: "On device · best effort", sent: turn.cloudPromptSent)
            case .needsConfirmation(let card):
                ActionDiagnostics.shared.record(attemptID: card.attemptID, capability: card.capabilityID,
                                                phase: .projection, code: .cardProjected)
                reply(card.title, badge: ActionStatusLabel.awaitingReview, card: card, attempt: card.attemptID)
            }
            let answer = book.conversation(cid)?.messages.last { $0.id == id }?.text ?? ""
            for c in turn.corrections { append(.init(role: .system, text: "Corrected: \(c.old.value) → \(c.new.value)"), to: cid) }
            if !turn.remembered.isEmpty {
                append(.init(role: .system, text: "Remembered: " + turn.remembered.map(\.text).joined(separator: " · ")), to: cid)
            }
            return answer
        } catch {
            if let failure = error as? CloudRequestFailure {
                let message = "The request has no verified result. A cloud request may already have been sent."
                append(.init(role: .system, text: message, badge: ActionStatusLabel.unverified,
                             cloudPromptSent: failure.cloudPromptSent), to: cid)
                return message
            }
            let message = "Error: \(error.localizedDescription)"
            append(.init(role: .system, text: message, ephemeral: true), to: cid)
            return message
        }
    }

    func confirm(_ item: ChatItem, edits: [DraftEdit] = []) async {
        guard !busy, let assistant, let found = chatItem(item.id), let card = found.item.card else { return }
        let cid = found.conversation, id = item.id
        busy = true; defer { busy = false; refresh(); persist() }
        do {
            let result = try await assistant.confirmEffect(card.attemptID, edits: edits, expectedRevision: card.revision)
            switch result {
            case .staged(let updated):
                mutate(id) { $0.card = updated; $0.text = updated.title }
                if !updated.canConfirm && !updated.notice.isEmpty {
                    append(.init(role: .system, text: updated.notice), to: cid)
                }
            case .finished(let effect), .ignoredTerminal(let effect):
                mutate(id) {
                    $0.card = nil
                    $0.text = effect.summary
                    $0.attemptID = effect.attemptID
                    $0.cloudPromptSent = effect.cloudPromptSent
                    $0.badge = ActionStatusLabel.label(for: effect.phase)
                    if effect.cloudPromptSent != nil { $0.badge = "Cloud request attempted"; $0.keptOnDevice = false }
                    if case .ambiguous = effect.phase { $0.badge = ActionStatusLabel.unverified; $0.keptOnDevice = false }
                    if case .claimed = effect.phase { $0.badge = ActionStatusLabel.unverified; $0.keptOnDevice = false }
                }
            case .read(let read):
                let rows = read.decisions.map { self.row($0) }
                mutate(id) {
                    $0.card = nil
                    $0.text = read.text
                    $0.badge = read.provider.map { prettyProvider($0) }
                        ?? (read.cloudPromptSent == nil ? "On device" : "On device · answered after a cloud attempt")
                    $0.decisions = rows
                    $0.cloudPromptSent = read.cloudPromptSent
                    $0.keptOnDevice = read.withheldForSensitivity
                }
            }
        } catch {
            let sent = (error as? CloudRequestFailure)?.cloudPromptSent
            let recovery = try? assistant.recoverEffects()
            mutate(id) {
                $0.badge = ActionStatusLabel.unverified
                $0.keptOnDevice = false
                $0.attemptID = card.attemptID
                $0.cloudPromptSent = sent ?? $0.cloudPromptSent
                if let recovery {
                    $0.card = recovery.showAgain.first { $0.attemptID == card.attemptID }
                    if let unresolved = recovery.unresolved.first(where: { $0.attemptID == card.attemptID }) {
                        $0.text = unresolved.summary
                    }
                }
            }
            append(.init(role: .system, text: "Couldn't verify completion. The request may already have been sent or acted on. Check the destination before starting a new request."), to: cid)
        }
    }

    /// Persists an edit (contact, method or exact time) without claiming. Body text is passed at Confirm.
    func edit(_ item: ChatItem, edits: [DraftEdit]) async {
        guard !busy, let assistant, let found = chatItem(item.id), let card = found.item.card else { return }
        let cid = found.conversation, id = item.id
        busy = true; defer { busy = false; persist() }
        do {
            let updated = try await assistant.editEffect(card.attemptID, edits: edits, expectedRevision: card.revision)
            mutate(id) { $0.card = updated; $0.text = updated.title }
        } catch {
            if let recovery = try? assistant.recoverEffects() {
                mutate(id) {
                    $0.card = recovery.showAgain.first { $0.attemptID == card.attemptID }
                    if let updated = $0.card { $0.text = updated.title }
                }
            }
            append(.init(role: .system, text: "Couldn't verify the saved edit. It may already have been saved. Review the card before confirming."), to: cid)
        }
    }

    func refreshContacts(_ item: ChatItem) async {
        guard !busy, let assistant, let found = chatItem(item.id), let card = found.item.card else { return }
        let cid = found.conversation, id = item.id
        busy = true; defer { busy = false; persist() }
        let access = await actions.requestContactsAccess()
        let fields = card.fields.filter { $0.kind == .contact }
        do {
            let updated = try await assistant.editEffect(card.attemptID,
                edits: fields.map { DraftEdit(field: $0.name, value: .refreshContact) }, expectedRevision: card.revision)
            mutate(id) { $0.card = updated }
            if access != .full && access != .limited {
                append(.init(role: .system, text: "Contacts access is off. Allow access in iOS Settings, then refresh the contact on this card."), to: cid)
            }
        } catch {
            append(.init(role: .system, text: "Could not refresh this contact. Review the latest card before confirming."), to: cid)
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
        guard !busy, let assistant, let found = chatItem(item.id), let card = found.item.card else { return }
        do {
            let effect = try assistant.cancelEffect(card.attemptID)
            mutate(item.id) { $0.card = nil; $0.text = effect.summary; $0.badge = ActionStatusLabel.label(for: effect.phase); $0.attemptID = effect.attemptID }
        } catch {
            append(.init(role: .system, text: "Couldn't cancel that card: \(error). The card was kept."), to: found.conversation)
        }
        persist()
    }

    /// Launch recovery. Waiting cards are re-attached to the chat message that already references their ledger
    /// attempt; any the history does not know (crash before the chat was saved) are added to the active chat.
    /// Read-only: it never performs or replays an effect.
    private func restoreHistory(_ assistant: Assistant) {
        do {
            let recovery = try assistant.recoverEffects()
            var byAttempt: [UUID: UUID] = [:]
            for c in book.conversations { for m in c.messages { if let a = m.attemptID { byAttempt[a] = m.id } } }
            var seen = Set<UUID>()
            var unplaced = 0
            defer { if unplaced > 0 { noteHistory("\(unplaced) waiting or unverified action\(unplaced == 1 ? "" : "s") could not be shown because every chat is full. Delete a chat and reopen the app. Nothing was run or cancelled.") } }
            for card in recovery.showAgain {
                seen.insert(card.attemptID.raw)
                if let mid = byAttempt[card.attemptID.raw] {
                    mutate(mid) { $0.card = card; $0.text = card.title; $0.badge = ActionStatusLabel.awaitingReview; $0.attemptID = card.attemptID }
                } else if let target = book.chatWithRoom() {
                    append(.init(role: .assistant, text: card.title, badge: ActionStatusLabel.awaitingReview, card: card, attemptID: card.attemptID), to: target)
                } else {
                    unplaced += 1
                }
            }
            for open in recovery.unresolved {
                seen.insert(open.attemptID.raw)
                if let mid = byAttempt[open.attemptID.raw] {
                    mutate(mid) { $0.card = nil; $0.text = open.summary; $0.badge = ActionStatusLabel.unverified; $0.attemptID = open.attemptID }
                } else if let target = book.chatWithRoom() {
                    append(.init(role: .system, text: open.summary, badge: ActionStatusLabel.unverified, attemptID: open.attemptID, ephemeral: true), to: target)
                } else {
                    unplaced += 1
                }
            }
            for c in book.conversations {
                for m in c.messages where m.pendingAction && m.attemptID.map({ !seen.contains($0) }) == true {
                    mutate(m.id) {
                        $0.card = nil; $0.badge = nil
                        $0.text = "This action is no longer waiting. It finished or was cancelled, and nothing here will run it again."
                    }
                }
            }
        } catch {
            if let target = book.chatWithRoom() { append(.init(role: .system, text: "Couldn't read saved actions: \(error)", ephemeral: true), to: target) }
            noteHistory("Saved actions could not be read.")
        }
        persist()
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

    /// Secret-free action diagnostics (JSONL, one event per line) into Documents,
    /// visible in Files / Finder. Evidence path for messaging-action verification.
    func exportActionDiagnostics() -> URL? {
        let jsonl = ActionDiagnostics.shared.exportJSONL()
        guard !jsonl.isEmpty else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let u = docs.appendingPathComponent("action-diagnostics.jsonl")
        guard (try? jsonl.write(to: u, atomically: true, encoding: .utf8)) != nil else { return nil }
        return u
    }
}

/// Cloud brains: Meta first. Keys in Keychain; model ids editable in Settings.
enum CloudSettings {
    static func chain() -> CloudBrainChain {
        var b: [CloudBrain] = []
        let d = UserDefaults.standard
        let metaModel = (d.string(forKey: "meta_model") ?? "muse-spark-1.3").trimmingCharacters(in: .whitespacesAndNewlines)
        if let k = Keychain.get("meta_key"),
           CloudSettingsCheck.meta(model: metaModel, keySaved: !k.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).isEnabled {
            b.append(CloudPresets.metaModelAPI(model: metaModel, apiKey: k))
        }
        let customURL = (d.string(forKey: "byok_url") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let k = Keychain.get("byok_key"), let u = URL(string: customURL) {
            let model = (d.string(forKey: "byok_model") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if CloudSettingsCheck.custom(baseURL: customURL, model: model,
                                         keySaved: !k.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).isEnabled {
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
