import AppIntents
import Foundation
import PDFKit
import UniformTypeIdentifiers
import PocketCore

/// Wires the open-world skill registry into the Assistant: bundled Resources/Skills/builtin.json (Swift built-ins if
/// missing) + user skills dropped into Files › OffLlama › Skills/*.json. Adding an ability needs no retraining.
enum SkillSetup {
    static var userSkillsDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Skills")
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        return docs
    }

    static func registry() -> SkillRegistry {
        let bundled = Bundle.main.url(forResource: "builtin", withExtension: "json")
            ?? Bundle.main.url(forResource: "builtin", withExtension: "json", subdirectory: "Skills")
        var reg = bundled.map { SkillRegistry.load(from: $0) } ?? SkillRegistry()
        _ = try? reg.merge(contentsOf: userSkillsDir)
        return reg
    }

    /// Idempotent. Call once after the Assistant is created (AppModel.boot); the intents below also call it.
    static func install(on a: Assistant, memory: MemoryStore?) {
        guard a.skills == nil else { return }
        _ = memory   // auto-reply effects write through PocketEffects, not the read-only runner
        a.skills = registry()
        a.skillRunner = IOSSkillRunner()
    }

    @MainActor static func ensureInstalled() async {
        await AppModel.shared.boot()
        if let a = AppModel.shared.assistant { install(on: a, memory: AppModel.shared.memory) }
    }
}

/// "OffLlama: handle text". Share sheet / Shortcuts hand text (selected emails from Mail, a Safari page, a note)
/// or a file (PDF/txt) to the app; the assistant then runs the instruction on it, on device first.
/// This is how "analyze my last few emails" works on iOS, where no app may read Mail: Mail › select › Share ›
/// Shortcut “PG Share Emails” (Receive text from Share Sheet → OffLlama: handle text).
struct HandleTextIntent: AppIntent {
    static let title: LocalizedStringResource = "OffLlama: handle text"
    static let description = IntentDescription("Give OffLlama text or a document (emails, a page, a PDF) and tell it what to do with it.")
    static let openAppWhenRun = true

    @Parameter(title: "Text") var text: String?
    @Parameter(title: "File") var file: IntentFile?
    @Parameter(title: "Instruction", default: "Summarize this") var instruction: String
    @Parameter(title: "Source", default: "share") var source: String

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$instruction)") { \.$text; \.$file; \.$source }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        var body = text ?? ""
        if let f = file {
            let fromFile = (f.filename.lowercased().hasSuffix(".pdf") ? PDFDocument(data: f.data)?.string : String(data: f.data, encoding: .utf8)) ?? ""
            body = body.isEmpty ? fromFile : body + "\n\n" + fromFile
        }
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .result(value: "Nothing was shared.") }
        await SkillSetup.ensureInstalled()
        let ask = Self.utterance(for: instruction, source: source)
        let reply = await AppModel.shared.send(ask, sharedText: body, source: source)
        return .result(value: reply)
    }

    /// Steers the request toward the skill that reads the shared text (email_digest / summarize_text / html_viz).
    static func utterance(for instruction: String, source: String) -> String {
        let i = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.lowercased().contains("mail"), !i.lowercased().contains("email") { return "\(i.isEmpty ? "Summarize" : i) these emails" }
        return i.isEmpty ? "Summarize what I just shared" : i
    }
}

/// Siri / Spotlight entry points for common skills (App Shortcut phrases may only use enum/entity parameters).
enum QuickSkill: String, AppEnum {
    case battery, alarm, timer, emails, chart, document, instagram
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Action"
    static let caseDisplayRepresentations: [QuickSkill: DisplayRepresentation] = [
        .battery: "check battery and storage", .alarm: "set an alarm", .timer: "start a timer",
        .emails: "summarize shared emails", .chart: "chart shared numbers", .document: "analyze a document",
        .instagram: "DM on Instagram"]
    var utterance: String {
        switch self {
        case .battery: return "how much battery do I have"
        case .alarm: return "set an alarm"
        case .timer: return "start a timer"
        case .emails: return "summarize my recent emails"
        case .chart: return "make a chart of these numbers"
        case .document: return "analyze this document"
        case .instagram: return "dm on instagram"
        }
    }
}

struct RunSkillIntent: AppIntent {
    static let title: LocalizedStringResource = "OffLlama Action"
    static let description = IntentDescription("Run a OffLlama phone action. Anything that messages someone still asks you to confirm.")
    static let openAppWhenRun = true
    @Parameter(title: "Action") var action: QuickSkill
    @Parameter(title: "Details") var details: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        await SkillSetup.ensureInstalled()
        let reply = await AppModel.shared.send([action.utterance, details ?? ""].filter { !$0.isEmpty }.joined(separator: " "))
        return .result(value: reply)
    }
}

// Siri phrases: iOS allows ONE AppShortcutsProvider per app (PocketGlimmerShortcuts in Intents.swift), so a second
// provider here would fail the AppIntents metadata build step. Paste these two lines into its `appShortcuts` body:
//
//   AppShortcut(intent: HandleTextIntent(), phrases: ["Share with \(.applicationName)", "Summarize with \(.applicationName)"],
//               shortTitle: "Handle text", systemImageName: "doc.text.magnifyingglass")
//   AppShortcut(intent: RunSkillIntent(), phrases: ["Ask \(.applicationName) to \(\.$action)", "\(.applicationName) \(\.$action)"],
//               shortTitle: "Action", systemImageName: "wand.and.stars")
//
// Without them both intents still appear as actions in the Shortcuts app (that is all “PG Share Emails” needs).
