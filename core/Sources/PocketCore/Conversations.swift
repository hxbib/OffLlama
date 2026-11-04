import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// Conversation data model. One `ConversationBook` is the whole chat history. Every message, pending message draft
// and in-flight result belongs to exactly one `ConversationID`; nothing here moves a message between chats.
// Effect cards are NOT stored here: a message keeps only the ledger `attemptID`, and the card is re-derived from the
// ledger on launch. The chat is a projection and never the effect executor.

public struct ConversationID: Hashable, Sendable, Codable {
    public let raw: UUID
    public init() { raw = UUID() }
    public init(raw: UUID) { self.raw = raw }
}

public enum StoredRole: String, Sendable, Codable, Equatable { case user, assistant, system }

public struct StoredMessage: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var role: StoredRole
    public var text: String
    public var badge: String?
    /// Ledger attempt this message projects (card, or the terminal text of a settled/unverified action).
    public var attemptID: UUID?
    /// True while the action is awaiting the user or its outcome is unverified. Clear keeps these messages.
    public var pendingAction: Bool
    public var keptOnDevice: Bool
    /// Rebuilt from the ledger on every launch, so never written to disk.
    public var ephemeral: Bool
    public var at: Date

    public init(id: UUID = UUID(), role: StoredRole, text: String, badge: String? = nil, attemptID: UUID? = nil,
                pendingAction: Bool = false, keptOnDevice: Bool = false, ephemeral: Bool = false, at: Date = Date()) {
        self.id = id; self.role = role; self.text = text; self.badge = badge; self.attemptID = attemptID
        self.pendingAction = pendingAction; self.keptOnDevice = keptOnDevice; self.ephemeral = ephemeral; self.at = at
    }
}

public struct ConversationLimits: Sendable, Equatable {
    public var maxConversations = 40
    public var maxMessagesPerConversation = 200
    public var maxMessageCharacters = 24_000
    public var maxDraftsPerConversation = 5
    public var maxEncodedBytes = 4 * 1024 * 1024
    public init() {}
    public static let standard = ConversationLimits()
}

public struct Conversation: Sendable, Codable, Equatable, Identifiable {
    public var id: ConversationID
    public var title: String
    public var created: Date
    public var updated: Date
    public var messages: [StoredMessage]
    /// Unfinished message drafts for THIS conversation only.
    public var drafts: [MessageDraft]

    public init(id: ConversationID = ConversationID(), title: String = Conversation.defaultTitle, created: Date = Date(),
                messages: [StoredMessage] = [], drafts: [MessageDraft] = []) {
        self.id = id; self.title = title; self.created = created; self.updated = created
        self.messages = messages; self.drafts = drafts
    }

    public static let defaultTitle = "New chat"

    public var pendingActionCount: Int { messages.filter(\.pendingAction).count }
    public var hasPendingActions: Bool { pendingActionCount > 0 }
    public var isEmpty: Bool { messages.isEmpty }
}

public enum ConversationError: Error, Equatable, CustomStringConvertible {
    case unknownConversation
    case chatFull(limit: Int)
    case tooManyChats(limit: Int)
    case messageTooLong(limit: Int)
    case hasPendingActions(count: Int)
    case storage(String)
    case tooLarge(bytes: Int, limit: Int)
    case corrupt

    public var description: String {
        switch self {
        case .unknownConversation: return "That chat no longer exists."
        case .chatFull(let n): return "This chat has \(n) messages, the most it can hold. Start a new chat to continue."
        case .tooManyChats(let n): return "You have \(n) chats, the most OffLlama keeps. Delete one to start another."
        case .messageTooLong(let n): return "That message is longer than \(n) characters."
        case .hasPendingActions(let n):
            return "This chat has \(n) action\(n == 1 ? "" : "s") waiting or unverified. Confirm or cancel \(n == 1 ? "it" : "them") first, or use Clear, which keeps \(n == 1 ? "it" : "them")."
        case .storage(let s): return "History could not be saved: \(s)"
        case .tooLarge: return "History is full, so it could not be saved. Delete an old chat."
        case .corrupt: return "Saved history could not be read."
        }
    }
}

public struct ConversationBook: Sendable, Codable, Equatable {
    public static let currentVersion = 1
    public var version: Int
    public var conversations: [Conversation]
    public var activeID: ConversationID

    public init() {
        let first = Conversation()
        version = Self.currentVersion; conversations = [first]; activeID = first.id
    }

    public init(version: Int, conversations: [Conversation], activeID: ConversationID) {
        self.version = version; self.conversations = conversations; self.activeID = activeID
        normalize()
    }

    private mutating func normalize() {
        if conversations.isEmpty { let c = Conversation(); conversations = [c]; activeID = c.id }
        if !conversations.contains(where: { $0.id == activeID }) { activeID = conversations[0].id }
    }

    // MARK: lookup

    public func index(of id: ConversationID) -> Int? { conversations.firstIndex { $0.id == id } }
    public func conversation(_ id: ConversationID) -> Conversation? { index(of: id).map { conversations[$0] } }
    public var active: Conversation { conversation(activeID) ?? conversations[0] }

    /// The conversation that owns a message. Card actions use this, never the active chat.
    public func owner(ofMessage messageID: UUID) -> (conversation: ConversationID, index: Int)? {
        for c in conversations {
            if let i = c.messages.firstIndex(where: { $0.id == messageID }) { return (c.id, i) }
        }
        return nil
    }

    public var pendingActionCount: Int { conversations.reduce(0) { $0 + $1.pendingActionCount } }

    // MARK: mutation (all bounded; nothing is evicted to make room)

    @discardableResult
    public mutating func newConversation(limits: ConversationLimits = .standard) throws -> ConversationID {
        // An untouched empty chat is reused, so repeated New chat taps do not pile up blanks.
        if let blank = conversations.first(where: { $0.isEmpty && $0.drafts.isEmpty }) {
            activeID = blank.id; return blank.id
        }
        guard conversations.count < limits.maxConversations else { throw ConversationError.tooManyChats(limit: limits.maxConversations) }
        let c = Conversation()
        conversations.insert(c, at: 0)
        activeID = c.id
        return c.id
    }

    public mutating func select(_ id: ConversationID) throws {
        guard index(of: id) != nil else { throw ConversationError.unknownConversation }
        activeID = id
    }

    public mutating func append(_ message: StoredMessage, to id: ConversationID, limits: ConversationLimits = .standard) throws {
        guard let i = index(of: id) else { throw ConversationError.unknownConversation }
        guard message.text.count <= limits.maxMessageCharacters else { throw ConversationError.messageTooLong(limit: limits.maxMessageCharacters) }
        guard conversations[i].messages.count < limits.maxMessagesPerConversation else {
            throw ConversationError.chatFull(limit: limits.maxMessagesPerConversation)
        }
        conversations[i].messages.append(message)
        conversations[i].updated = message.at
        if conversations[i].title == Conversation.defaultTitle, message.role == .user {
            conversations[i].title = Self.title(from: message.text)
        }
    }

    /// A chat that can take one more message: the active chat if it has room, else a fresh chat, else any chat with
    /// room. nil means every chat is full and no new chat is allowed.
    public mutating func chatWithRoom(limits: ConversationLimits = .standard) -> ConversationID? {
        if let c = conversation(activeID), c.messages.count < limits.maxMessagesPerConversation { return c.id }
        if let id = try? newConversation(limits: limits) { return id }
        return conversations.first { $0.messages.count < limits.maxMessagesPerConversation }?.id
    }

    /// Why a typed message must be refused before any work starts, or nil when it is admitted. Callers keep the typed
    /// text on refusal.
    public func refusal(forUserText text: String, in id: ConversationID, limits: ConversationLimits = .standard) -> ConversationError? {
        if text.count > limits.maxMessageCharacters { return .messageTooLong(limit: limits.maxMessageCharacters) }
        if !hasRoomForTurn(in: id, limits: limits) { return .chatFull(limit: limits.maxMessagesPerConversation) }
        return nil
    }

    /// Bounds a stored message. Over-long text is cut with an explicit marker, never dropped.
    public static func fit(_ text: String, limits: ConversationLimits = .standard) -> (text: String, truncated: Bool) {
        guard text.count > limits.maxMessageCharacters else { return (text, false) }
        let marker = "\n… (shortened to fit chat history)"
        return (String(text.prefix(limits.maxMessageCharacters - marker.count)) + marker, true)
    }

    /// Room for a user turn plus its reply and the few system lines a turn can add.
    public func hasRoomForTurn(in id: ConversationID, limits: ConversationLimits = .standard) -> Bool {
        guard let c = conversation(id) else { return false }
        return c.messages.count + 4 <= limits.maxMessagesPerConversation
    }

    public mutating func update(messageID: UUID, in id: ConversationID, _ change: (inout StoredMessage) -> Void) {
        guard let ci = index(of: id), let mi = conversations[ci].messages.firstIndex(where: { $0.id == messageID }) else { return }
        change(&conversations[ci].messages[mi])
    }

    public mutating func setDrafts(_ drafts: [MessageDraft], for id: ConversationID) {
        guard let i = index(of: id) else { return }
        conversations[i].drafts = drafts
    }

    /// Clear removes ordinary messages and unfinished message drafts. Messages that project a waiting or unverified
    /// ledger action stay, because the ledger still owns that action and the user must still be able to find it.
    @discardableResult
    public mutating func clear(_ id: ConversationID) throws -> (removed: Int, keptPending: Int) {
        guard let i = index(of: id) else { throw ConversationError.unknownConversation }
        let before = conversations[i].messages.count
        conversations[i].messages.removeAll { !$0.pendingAction }
        conversations[i].drafts = []
        if conversations[i].messages.isEmpty { conversations[i].title = Conversation.defaultTitle }
        return (before - conversations[i].messages.count, conversations[i].messages.count)
    }

    /// Delete is refused while the chat projects a waiting or unverified action, so no action can lose its only
    /// visible handle. Resolve it (Confirm or Cancel) or use Clear.
    public mutating func delete(_ id: ConversationID) throws {
        guard let i = index(of: id) else { throw ConversationError.unknownConversation }
        let pending = conversations[i].pendingActionCount
        guard pending == 0 else { throw ConversationError.hasPendingActions(count: pending) }
        conversations.remove(at: i)
        normalize()
    }

    public static func title(from text: String) -> String {
        let flat = text.split(whereSeparator: { $0.isNewline || $0 == "\t" }).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if flat.isEmpty { return Conversation.defaultTitle }
        return flat.count <= 40 ? flat : String(flat.prefix(39)) + "…"
    }

    /// The snapshot that is written to disk: ephemeral messages are rebuilt from the ledger and are left out.
    public func persistable() -> ConversationBook {
        var copy = self
        for i in copy.conversations.indices { copy.conversations[i].messages.removeAll { $0.ephemeral } }
        return copy
    }
}

// MARK: on-device context

/// Bounded recent-turn context for ON-DEVICE generation only. It is never added to routing, Reflex decisions,
/// message drafts or any cloud request.
public enum ConversationContext {
    public static let maxTurns = 6
    public static let maxCharacters = 1_200
    public static let maxCharactersPerMessage = 300

    /// Stored text is untrusted. The on-device tokenizer parses special tokens, so any `<|...|>` marker is broken up
    /// before the text can reach a prompt; otherwise a saved reply could forge a system or assistant header.
    public static func neutralize(_ text: String) -> String {
        text.replacingOccurrences(of: "<|", with: "< |").replacingOccurrences(of: "|>", with: "| >")
    }

    public static func render(_ messages: [StoredMessage]) -> String {
        let usable = messages.filter {
            ($0.role == .user || $0.role == .assistant) && $0.attemptID == nil && !$0.pendingAction && !$0.ephemeral
                && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var lines: [String] = []
        var used = 0
        for m in usable.suffix(maxTurns).reversed() {
            var t = neutralize(m.text).split(whereSeparator: { $0.isNewline }).joined(separator: " ")
            if t.count > maxCharactersPerMessage { t = String(t.prefix(maxCharactersPerMessage - 1)) + "…" }
            let line = (m.role == .user ? "User: " : "Assistant: ") + t
            if used + line.count + 1 > maxCharacters { break }
            used += line.count + 1
            lines.append(line)
        }
        guard !lines.isEmpty else { return "" }
        return "Earlier in this chat (most recent last):\n" + lines.reversed().joined(separator: "\n") + "\n"
    }
}

// MARK: ledger reconciliation

/// Read-only check of which restored draft request IDs already reached the effect ledger. A crash between card
/// staging and draft consumption leaves a saved draft whose action already exists; following it up would create a
/// second action, so such drafts are dropped on restore.
public enum LedgerRequestIndex {
    public static func requestIDsWithAttempts(db: SQLiteDB, among ids: [UserRequestID]) throws -> Set<UserRequestID> {
        guard !ids.isEmpty else { return [] }
        let marks = ids.map { _ in "?" }.joined(separator: ",")
        let tables = try db.query("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'action_attempts'")
        guard !tables.isEmpty else { return [] }
        let rows = try db.query("SELECT DISTINCT request_id FROM action_attempts WHERE request_id IN (\(marks))",
                                ids.map { .text($0.raw.uuidString) })
        return Set(rows.compactMap { $0["request_id"]?.text.flatMap(UUID.init(uuidString:)) }.map { UserRequestID(raw: $0) })
    }

    public static func reconcile(_ book: inout ConversationBook, db: SQLiteDB) throws -> Int {
        let all = book.conversations.flatMap { $0.drafts.map(\.requestID) }
        let staged = try requestIDsWithAttempts(db: db, among: all)
        guard !staged.isEmpty else { return 0 }
        var dropped = 0
        for i in book.conversations.indices {
            let before = book.conversations[i].drafts.count
            book.conversations[i].drafts.removeAll { staged.contains($0.requestID) }
            dropped += before - book.conversations[i].drafts.count
        }
        return dropped
    }
}

// MARK: protected snapshot store

/// One protected JSON snapshot for the whole book. Chosen over one file per conversation because a single atomic
/// replace keeps all chats and the active selection consistent, and the 4 MiB bound keeps the write small.
public final class ConversationStore: @unchecked Sendable {
    public static let filename = "history-v1.json"
    /// Prefix of the renamed file. Each set-aside gets its own suffix, so a second bad file never replaces the first.
    public static let corruptFilename = "history-v1.unreadable"
    public let directory: URL
    public let limits: ConversationLimits
    private let lock = NSLock()

    public init(directory: URL, limits: ConversationLimits = .standard) {
        self.directory = directory; self.limits = limits
    }

    public var fileURL: URL { directory.appendingPathComponent(Self.filename) }

    public enum LoadResult: Equatable {
        case empty
        case loaded(ConversationBook)
        /// The file was kept (renamed) rather than overwritten.
        case unreadable
    }

    public func load() throws -> LoadResult {
        lock.lock(); defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }
        do {
            let data = try Data(contentsOf: fileURL)
            let book = try JSONDecoder.history.decode(ConversationBook.self, from: data)
            guard book.version == ConversationBook.currentVersion else { return try setAside() }
            return .loaded(ConversationBook(version: book.version, conversations: book.conversations, activeID: book.activeID))
        } catch is DecodingError {
            return try setAside()
        } catch {
            throw ConversationError.storage("history could not be read")
        }
    }

    private func setAside() throws -> LoadResult {
        let aside = directory.appendingPathComponent(Self.corruptFilename + "-" + UUID().uuidString)
        do { try FileManager.default.moveItem(at: fileURL, to: aside); try Self.protect(aside) }
        catch { throw ConversationError.storage("unreadable history could not be set aside") }
        return .unreadable
    }

    public func save(_ book: ConversationBook) throws {
        lock.lock(); defer { lock.unlock() }
        let data: Data
        do { data = try JSONEncoder.history.encode(book.persistable()) }
        catch { throw ConversationError.storage("history could not be encoded") }
        guard data.count <= limits.maxEncodedBytes else {
            throw ConversationError.tooLarge(bytes: data.count, limit: limits.maxEncodedBytes)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.protect(directory)
            let tmp = directory.appendingPathComponent(Self.filename + ".tmp")
            defer { try? FileManager.default.removeItem(at: tmp) }
            try? FileManager.default.removeItem(at: tmp)
            #if os(iOS) || os(tvOS) || os(watchOS)
            try data.write(to: tmp, options: [.completeFileProtection])
            #else
            try data.write(to: tmp)
            #endif
            try Self.protect(tmp)
            let replaced = tmp.path.withCString { source in
                fileURL.path.withCString { destination in rename(source, destination) }
            }
            guard replaced == 0 else { throw ConversationError.storage("history could not be replaced") }
            try Self.protect(fileURL)
        } catch let e as ConversationError { throw e }
        catch { throw ConversationError.storage("the file could not be written or protected") }
    }

    /// Reads back the protection and backup-exclusion attributes of the history file, for tests and diagnostics.
    public func attributeReadback() -> (protection: String?, excludedFromBackup: Bool?) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let protection = (attrs?[.protectionKey] as? FileProtectionType)?.rawValue ?? attrs?[.protectionKey] as? String
        let excluded = try? fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        return (protection, excluded)
    }

    static func protect(_ url: URL) throws {
        #if os(iOS) || os(tvOS) || os(watchOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let protection = (attributes[.protectionKey] as? FileProtectionType)?.rawValue ?? attributes[.protectionKey] as? String
        guard protection == FileProtectionType.complete.rawValue else {
            throw ConversationError.storage("file protection could not be verified")
        }
        #endif
        #if os(iOS) || os(tvOS) || os(watchOS) || os(macOS)
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutable.setResourceValues(values)
        mutable.removeAllCachedResourceValues()
        guard try mutable.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true else {
            throw ConversationError.storage("backup exclusion could not be verified")
        }
        #endif
    }
}

extension JSONEncoder {
    static var history: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e }
}
extension JSONDecoder {
    static var history: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }
}
