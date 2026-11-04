import XCTest
@testable import PocketCore

/// Conversation isolation, bounded persistence, clear/delete rules, ledger reconciliation and on-device-only context.
/// Model decisions in the Assistant tests are scripted; they are not real-model behavior.
final class ConversationTests: XCTestCase {
    private func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("conv-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: u) }
        return u
    }

    private func msg(_ role: StoredRole, _ text: String, attempt: UUID? = nil, pending: Bool = false, ephemeral: Bool = false) -> StoredMessage {
        StoredMessage(role: role, text: text, attemptID: attempt, pendingAction: pending, ephemeral: ephemeral)
    }

    // MARK: isolation

    func testMessagesAndDraftsStayInTheirOwnConversation() throws {
        var book = ConversationBook()
        let a = book.activeID
        try book.append(msg(.user, "hello from A"), to: a)
        let b = try book.newConversation()
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(book.activeID, b)
        // A result captured for chat A lands in A even though B is active.
        try book.append(msg(.assistant, "reply for A"), to: a)
        let draft = MessageDraft(requestID: UserRequestID(), contact: "Dana", created: Date())
        book.setDrafts([draft], for: a)
        XCTAssertEqual(book.conversation(a)?.messages.map(\.text), ["hello from A", "reply for A"])
        XCTAssertTrue(book.conversation(b)!.messages.isEmpty)
        XCTAssertTrue(book.conversation(b)!.drafts.isEmpty)
        XCTAssertEqual(book.conversation(a)?.drafts.first?.requestID, draft.requestID)
        let m = book.conversation(a)!.messages[0]
        XCTAssertEqual(book.owner(ofMessage: m.id)?.conversation, a)
    }

    func testNewChatReusesAnUntouchedBlankChat() throws {
        var book = ConversationBook()
        let first = book.activeID
        XCTAssertEqual(try book.newConversation(), first)
        try book.append(msg(.user, "x"), to: first)
        let second = try book.newConversation()
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(book.conversations.count, 2)
        XCTAssertEqual(try book.newConversation(), second)
        XCTAssertEqual(book.conversations.count, 2)
    }

    func testTitleComesFromFirstUserMessage() throws {
        var book = ConversationBook()
        try book.append(msg(.assistant, "welcome"), to: book.activeID)
        XCTAssertEqual(book.active.title, "New chat")
        try book.append(msg(.user, "What is the capital of France? Please answer with a long explanation about it"), to: book.activeID)
        XCTAssertEqual(book.active.title.count, 40)
        XCTAssertTrue(book.active.title.hasSuffix("…"))
    }

    // MARK: bounds, no silent eviction

    func testFullChatAndTooManyChatsRefuseInsteadOfEvicting() throws {
        var limits = ConversationLimits(); limits.maxMessagesPerConversation = 3; limits.maxConversations = 2
        var book = ConversationBook()
        let id = book.activeID
        for i in 0..<3 { try book.append(msg(.user, "m\(i)"), to: id, limits: limits) }
        XCTAssertThrowsError(try book.append(msg(.user, "m3"), to: id, limits: limits)) {
            XCTAssertEqual($0 as? ConversationError, .chatFull(limit: 3))
        }
        XCTAssertEqual(book.conversation(id)?.messages.map(\.text), ["m0", "m1", "m2"])
        _ = try book.newConversation(limits: limits)
        try book.append(msg(.user, "other"), to: book.activeID, limits: limits)
        XCTAssertThrowsError(try book.newConversation(limits: limits)) {
            XCTAssertEqual($0 as? ConversationError, .tooManyChats(limit: 2))
        }
        XCTAssertEqual(book.conversations.count, 2)
        var tiny = ConversationLimits(); tiny.maxMessageCharacters = 5
        XCTAssertThrowsError(try book.append(msg(.user, "123456"), to: book.activeID, limits: tiny))
    }

    // MARK: clear and delete

    func testClearKeepsPendingActionsAndDropsDraftsAndEverythingElse() throws {
        var book = ConversationBook()
        let id = book.activeID
        let attempt = UUID()
        try book.append(msg(.user, "text Dana"), to: id)
        try book.append(msg(.assistant, "Draft: message to Dana", attempt: attempt, pending: true), to: id)
        try book.append(msg(.assistant, "hi"), to: id)
        book.setDrafts([MessageDraft(requestID: UserRequestID(), contact: "Sam")], for: id)
        let r = try book.clear(id)
        XCTAssertEqual(r.removed, 2)
        XCTAssertEqual(r.keptPending, 1)
        XCTAssertEqual(book.conversation(id)?.messages.map(\.attemptID), [attempt])
        XCTAssertTrue(book.conversation(id)!.drafts.isEmpty)
    }

    func testDeleteIsRefusedWhileAnActionIsPendingThenAllowed() throws {
        var book = ConversationBook()
        let id = book.activeID
        try book.append(msg(.assistant, "card", attempt: UUID(), pending: true), to: id)
        XCTAssertThrowsError(try book.delete(id)) { XCTAssertEqual($0 as? ConversationError, .hasPendingActions(count: 1)) }
        XCTAssertEqual(book.conversations.count, 1)
        book.update(messageID: book.active.messages[0].id, in: id) { $0.pendingAction = false }
        try book.delete(id)
        XCTAssertEqual(book.conversations.count, 1, "the book always keeps one chat")
        XCTAssertTrue(book.active.isEmpty)
    }

    func testClearingNeverTouchesTheLedger() async throws {
        let db = try SQLiteDB(path: ":memory:")
        let ledger = try EffectLedger(db: db)
        let before = try ledger.recover(now: Date())
        var book = ConversationBook()
        _ = try book.clear(book.activeID)
        XCTAssertEqual(try ledger.recover(now: Date()), before)
    }

    // MARK: persistence

    func testRoundTripAcrossRelaunchAndEphemeralIsNotWritten() throws {
        let store = ConversationStore(directory: tempDir())
        XCTAssertEqual(try store.load(), .empty)
        var book = ConversationBook()
        let a = book.activeID
        try book.append(msg(.user, "first"), to: a)
        try book.append(msg(.system, "rebuilt each launch", ephemeral: true), to: a)
        let draft = MessageDraft(requestID: UserRequestID(), contact: "Dana", channel: .imessage, lastAsked: .body, created: Date(timeIntervalSince1970: 1_000))
        book.setDrafts([draft], for: a)
        let b = try book.newConversation()
        try book.append(msg(.user, "second"), to: b)
        try store.save(book)

        let reopened = ConversationStore(directory: store.directory)
        guard case .loaded(let loaded) = try reopened.load() else { return XCTFail("not loaded") }
        XCTAssertEqual(loaded.activeID, b)
        XCTAssertEqual(loaded.conversation(a)?.messages.map(\.text), ["first"])
        XCTAssertEqual(loaded.conversation(a)?.drafts, [draft])
        XCTAssertEqual(loaded.conversation(b)?.messages.map(\.text), ["second"])
    }

    func testOversizeSnapshotFailsHonestlyAndKeepsTheOldFile() throws {
        var limits = ConversationLimits(); limits.maxEncodedBytes = 600
        let store = ConversationStore(directory: tempDir(), limits: limits)
        var book = ConversationBook()
        try book.append(msg(.user, "small"), to: book.activeID)
        try store.save(book)
        let good = try Data(contentsOf: store.fileURL)
        try book.append(msg(.user, String(repeating: "x", count: 2_000)), to: book.activeID)
        XCTAssertThrowsError(try store.save(book)) {
            guard case .tooLarge = $0 as? ConversationError else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(try Data(contentsOf: store.fileURL), good)
    }

    func testUnreadableHistoryIsSetAsideNotOverwritten() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ConversationStore(directory: dir)
        try Data("{not json".utf8).write(to: store.fileURL)
        XCTAssertEqual(try store.load(), .unreadable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(ConversationStore.corruptFilename)), Data("{not json".utf8))
        XCTAssertEqual(try store.load(), .empty)
    }

    func testFutureVersionIsSetAsideNotDowngraded() throws {
        let dir = tempDir()
        let store = ConversationStore(directory: dir)
        var book = ConversationBook(); book.version = 99
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder.history.encode(book).write(to: store.fileURL)
        XCTAssertEqual(try store.load(), .unreadable)
    }

    func testProtectionAndBackupExclusionReadback() throws {
        let store = ConversationStore(directory: tempDir())
        try store.save(ConversationBook())
        let r = store.attributeReadback()
        #if os(iOS) || os(tvOS) || os(watchOS)
        XCTAssertEqual(r.protection, FileProtectionType.complete.rawValue)
        #endif
        #if os(iOS) || os(tvOS) || os(watchOS) || os(macOS)
        XCTAssertEqual(r.excludedFromBackup, true)
        let dirValues = try store.directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(dirValues.isExcludedFromBackup, true)
        #endif
    }

    // MARK: ledger reconciliation

    func testRestoredDraftWhoseActionReachedTheLedgerIsDropped() async throws {
        let db = try SQLiteDB(path: ":memory:")
        let ledger = try EffectLedger(db: db)
        let effects = FakePhoneEffects()
        let dana = candidate("Dana", id: "dana", methods: [phone("mobile", "5550103")])
        effects.contactQueries["Dana"] = ContactLookup(access: .full, matches: [dana])
        effects.contactIDs["dana"] = ContactLookup(access: .full, matches: [dana])
        let staged = MessageDraft(requestID: UserRequestID(), contact: "Dana", channel: .imessage, body: "hi")
        let a = Assistant(reflex: Reflex(engine: ScriptedEngine(), telemetry: try TelemetryLog(db: db), source: "test"),
                          memory: try MemoryStore(db: db), actions: RecordingActions(), ledger: ledger, effects: effects,
                          cloud: CloudBrainChain([]), isOnline: { false })
        a.skills = SkillRegistry()
        let turn = try await a.stageCompletedDraft(staged, decisions: [], remembered: [], corrections: [], sharedText: nil)
        guard case .needsConfirmation = turn.reply else { return XCTFail("\(turn.reply)") }

        // Crash simulation: the saved snapshot still carries the draft that was already staged.
        let stillOpen = MessageDraft(requestID: UserRequestID(), contact: "Sam")
        var book = ConversationBook()
        book.setDrafts([staged, stillOpen], for: book.activeID)
        let dropped = try LedgerRequestIndex.reconcile(&book, db: db)
        XCTAssertEqual(dropped, 1)
        XCTAssertEqual(book.active.drafts.map(\.requestID), [stillOpen.requestID])
    }

    func testReconcileWithoutLedgerTableKeepsDrafts() throws {
        let db = try SQLiteDB(path: ":memory:")
        var book = ConversationBook()
        book.setDrafts([MessageDraft(requestID: UserRequestID(), contact: "Sam")], for: book.activeID)
        XCTAssertEqual(try LedgerRequestIndex.reconcile(&book, db: db), 0)
        XCTAssertEqual(book.active.drafts.count, 1)
    }

    // MARK: context

    func testContextIsBoundedAndSkipsCardsPendingAndSystem() {
        var messages: [StoredMessage] = []
        for i in 0..<30 { messages.append(msg(i % 2 == 0 ? .user : .assistant, "turn \(i) " + String(repeating: "y", count: 600))) }
        messages.append(msg(.assistant, "card title", attempt: UUID(), pending: true))
        messages.append(msg(.system, "Corrected: a → b"))
        let rendered = ConversationContext.render(messages)
        XCTAssertLessThanOrEqual(rendered.count, ConversationContext.maxCharacters + 80)
        XCTAssertFalse(rendered.contains("card title"))
        XCTAssertFalse(rendered.contains("Corrected"))
        XCTAssertTrue(rendered.contains("turn 29"))
        XCTAssertFalse(rendered.contains("turn 2 "))
        XCTAssertEqual(ConversationContext.render([]), "")
    }

    func testContextReachesOnlyTheOnDevicePromptAndNeverCloudOrRouting() async throws {
        let e = ScriptedEngine(); e.generated = "Paris."
        e.script(whenPromptContains: "How should", logits: ["A": 5, "B": -3, "C": -3, "D": -3])
        let db = try SQLiteDB(path: ":memory:")
        let box = CloudBox()
        let a = Assistant(reflex: Reflex(engine: e, telemetry: try TelemetryLog(db: db), source: "test"),
                          memory: try MemoryStore(db: db), actions: RecordingActions(),
                          ledger: try EffectLedger(db: db), effects: FakePhoneEffects(),
                          cloud: CloudBrainChain([box]), isOnline: { true })
        let ctx = ConversationContext.render([msg(.user, "I am planning a trip to France"), msg(.assistant, "Nice, where to?")])
        _ = try await a.handle("What is the capital?", conversationContext: ctx)
        XCTAssertEqual(e.generatePrompts.count, 1)
        XCTAssertTrue(e.generatePrompts[0].contains("planning a trip to France"))
        XCTAssertEqual(box.prompts.count, 0)

        // Cloud-routed turn: the on-device history must not appear in the outbound request.
        let e2 = ScriptedEngine()
        e2.script(whenPromptContains: "How should", logits: ["A": -5, "B": -3, "C": 5, "D": -3])
        e2.script(whenPromptContains: "acceptable to send this request", logits: ["A": 5, "B": -5])
        let box2 = CloudBox()
        let db2 = try SQLiteDB(path: ":memory:")
        let a2 = Assistant(reflex: Reflex(engine: e2, telemetry: try TelemetryLog(db: db2), source: "test"),
                           memory: try MemoryStore(db: db2), actions: RecordingActions(),
                           ledger: try EffectLedger(db: db2), effects: FakePhoneEffects(),
                           cloud: CloudBrainChain([box2]), isOnline: { true })
        let t2 = try await a2.handle("Compare two approaches to planning a long trip", conversationContext: ctx)
        XCTAssertEqual(box2.prompts.count, 1, "\(t2.reply)")
        XCTAssertFalse(box2.prompts.joined().contains("planning a trip to France"))
        XCTAssertFalse(box2.prompts.joined().contains("Earlier in this chat"))

        let plain = Assistant.localPrompt("q", mem: "m")
        XCTAssertEqual(plain, Assistant.localPrompt("q", mem: "m", history: ""), "default prompt is unchanged")
    }
}

private final class CloudBox: CloudBrain, @unchecked Sendable {
    let providerName = "box"
    let model = "m"
    private let lock = NSLock()
    private var seen: [String] = []
    var prompts: [String] { lock.withLock { seen } }
    func complete(_ messages: [ChatMessage], maxTokens: Int) async throws -> CloudAnswer {
        lock.withLock { seen.append(messages.map(\.content).joined(separator: "\n")) }
        return CloudAnswer(text: "cloud", provider: "box", model: "m", latencyMs: 1)
    }
}
