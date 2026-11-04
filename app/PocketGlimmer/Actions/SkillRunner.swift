import Foundation
import UIKit
import SwiftUI
import WebKit
import PDFKit
import Contacts
import UniformTypeIdentifiers
import PocketCore

/// Runs registry skills (core/Sources/PocketCore/Skills.swift) with public iOS APIs only: URL schemes / universal links,
/// the Shortcuts URL scheme, and a few native handlers. Nothing taps inside other apps. Every status string says
/// exactly what happened ("opened", "copied", "handed to Shortcut"); nothing claims a message was sent.
/// ActionExecutor tools (send_message, send_email, EventKit) never reach here: PocketCore routes them to SystemActions.
final class IOSSkillRunner: SkillRunner, @unchecked Sendable {
    let contacts = CNContactStore()
    /// Persists auto-reply rules to memory (set by AppModel when the store exists).
    var memory: MemoryStore?

    func run(_ skill: Skill, args: [String: String]) async throws -> String {
        switch skill.invocation {
        case .urlScheme(let template):
            return await openURLSkill(skill, template: template, args: args)
        case .shortcut(let name, let input):
            let text = SkillTemplate.fill(input, args: args, encode: false)
            let result = await runShortcut(name: name, text: text, skill: skill)
            // The hand-off is all the app can confirm: Shortcuts may still report a missing Shortcut.
            guard skill.id == "appletv_play", result.hasPrefix("Couldn't open Shortcuts") else { return result }
            var search = URLComponents(string: "https://tv.apple.com/search")!
            search.queryItems = [URLQueryItem(name: "term", value: text)]
            if let u = search.url, await ComposeSheets.open(u) {
                return "Opened TV app search for “\(text)” · pick the latest episode"
            }
            return result
        case .native(let handler):
            return await runNative(handler, skill: skill, args: args)
        case .cloudReason:
            return "Handled by the assistant, not the phone."   // PocketCore answers these before reaching the runner
        }
    }

    // MARK: URL skills

    private func openURLSkill(_ skill: Skill, template: String, args: [String: String]) async -> String {
        var a = args
        if template.contains("{phone}") {
            let who = SystemActions.displayName(a["contact"] ?? "")
            guard let phone = phoneNumber(for: who) else { return "No phone number for \(who) in Contacts · nothing opened" }
            a["phone"] = phone.filter { $0.isNumber || $0 == "+" }
        }
        var copied = false
        if let clip = skill.clipboard {
            let text = SkillTemplate.fill(clip, args: a, encode: false)
            if !text.isEmpty { await MainActor.run { UIPasteboard.general.string = text }; copied = true }
        }
        let filled = SkillTemplate.fill(template, args: a, raw: ["url"])
        guard let url = URL(string: filled) else { return "Couldn't build a link for \(skill.title) · nothing opened" }
        let opened = await ComposeSheets.open(url)
        guard opened else {
            return "\(skill.title): the app isn't installed or the link was refused · nothing sent" + (copied ? " (text is on your clipboard)" : "")
        }
        switch skill.id {
        case "instagram_dm": return "Opened Instagram DM with @\(a["contact"] ?? "")" + (copied ? "; message copied to clipboard · paste and tap Send" : "")
        case "x_dm": return "Opened @\(a["contact"] ?? "")'s X profile; tap Message" + (copied ? ", the text is on your clipboard · paste and send" : "")
        case "whatsapp_send": return "Opened WhatsApp with the message filled in · pick the chat and tap Send"
        case "call", "facetime": return "iOS is asking to \(skill.id == "call" ? "call" : "FaceTime") \(SystemActions.displayName(a["contact"] ?? ""))"
        case "uber_ride": return "Opened Uber with the drop-off set · confirm the ride in Uber"
        default: return "Opened \(skill.title)" + (copied ? " · text copied to clipboard" : "")
        }
    }

    private func phoneNumber(for name: String) -> String? {
        let keys = [CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        guard !name.isEmpty,
              let c = (try? contacts.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys))?.first
        else { return nil }
        return c.phoneNumbers.first?.value.stringValue
    }

    // MARK: Shortcuts bridge

    private func runShortcut(name: String, text: String, skill: Skill) async -> String {
        guard let url = URL(string: SkillTemplate.shortcutURL(name: name, text: text)) else { return "Bad Shortcut name · nothing run" }
        let opened = await ComposeSheets.open(url)
        return opened
            ? "Handed to Shortcut “\(name)”\(text.isEmpty ? "" : " (\(text))") · if it isn't installed, Shortcuts will say so (recipe in docs/SKILLS.md)"
            : "Couldn't open Shortcuts · \(skill.title) not done"
    }

    // MARK: Native handlers

    private func runNative(_ handler: String, skill: Skill, args: [String: String]) async -> String {
        switch handler {
        case "device_status": return await deviceStatus()
        case "analyze_document": return await DocumentPicker.pickText() ?? ""
        case "html_viz":
            let data = args["data"] ?? ""
            guard let r = HTMLViz.render(text: data, title: args["title"] ?? "Chart") else {
                return "No numbers to chart. Paste them like “rent 1200, food 400”, or share a document first."
            }
            await HTMLSheet.present(html: r.html, title: args["title"] ?? "Chart")
            return "Chart ready: \(r.bars) bars, drawn on device"
        case "autoreply_rule":
            let trigger = args["trigger"] ?? "message", reply = args["reply"] ?? ""
            let text = "Auto-reply rule: when someone sends a \(trigger), reply “\(reply)”"
            if let memory {
                _ = try? await memory.upsert(ExtractedFact(subject: "user", attribute: "autoreply_rule", value: "\(trigger) -> \(reply)",
                                                           text: text, provenance: MemoryProvenance.userStated))
            }
            return "Saved: \(text). iOS doesn't let any app read or answer Instagram DMs, so I can't send these myself. "
                + "Closest real option: Shortcuts → Automation → Message (iMessage only) → Send Message “\(reply)”. For Instagram, I'll remind you when you open it."
        default:
            return "\(skill.title) isn't available on this build · nothing done"
        }
    }

    @MainActor private func deviceStatus() -> String {
        let dev = UIDevice.current
        dev.isBatteryMonitoringEnabled = true
        let lvl = dev.batteryLevel
        let state: String
        switch dev.batteryState { case .charging: state = " (charging)"; case .full: state = " (full)"; default: state = "" }
        let battery = lvl < 0 ? "Battery: unknown" : "Battery: \(Int((lvl * 100).rounded()))%\(state)"
        let home = URL(fileURLWithPath: NSHomeDirectory())
        var storage = "Storage: unknown"
        if let v = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
           let free = v.volumeAvailableCapacityForImportantUsage, let total = v.volumeTotalCapacity {
            let f = ByteCountFormatter(); f.countStyle = .file
            storage = "Storage: \(f.string(fromByteCount: free)) free of \(f.string(fromByteCount: Int64(total)))"
        }
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled ? " · Low Power Mode on" : ""
        return "\(battery) · \(storage)\(lowPower)"
    }
}

// MARK: - Document picker -> text (PDF via PDFKit, .txt, .md). Word/.docx is not supported on device.

@MainActor
final class DocumentPicker: NSObject, UIDocumentPickerDelegate {
    static let shared = DocumentPicker()
    private var pending: CheckedContinuation<String?, Never>?

    static func pickText() async -> String? {
        guard shared.pending == nil, let top = ComposeSheets.presenter() else { return nil }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .plainText, .text], asCopy: true)
        picker.delegate = shared
        picker.allowsMultipleSelection = false
        return await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            shared.pending = c
            top.present(picker, animated: true)
        }
    }

    nonisolated static func text(of url: URL) -> String? {
        if url.pathExtension.lowercased() == "pdf" { return PDFDocument(url: url)?.string }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func finish(_ s: String?) { let c = pending; pending = nil; c?.resume(returning: s) }

    nonisolated func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        MainActor.assumeIsolated { finish(urls.first.flatMap(Self.text(of:))) }
    }
    nonisolated func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        MainActor.assumeIsolated { finish(nil) }
    }
}

// MARK: - HTML sheet (WKWebView, no network: generated HTML only)

struct HTMLWebView: UIViewRepresentable {
    let html: String
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = false   // static SVG; no scripts
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.isOpaque = false
        return v
    }
    func updateUIView(_ v: WKWebView, context: Context) { v.loadHTMLString(html, baseURL: nil) }
}

struct HTMLSheetView: View {
    let html: String, title: String
    var dismiss: () -> Void
    var body: some View {
        NavigationStack {
            HTMLWebView(html: html)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done", action: dismiss) }
                    ToolbarItem(placement: .topBarLeading) { ShareLink(item: html) }
                }
        }
    }
}

@MainActor
enum HTMLSheet {
    static func present(html: String, title: String) {
        guard let top = ComposeSheets.presenter() else { return }
        weak var host: UIViewController?
        let view = HTMLSheetView(html: html, title: title) { host?.dismiss(animated: true) }
        let vc = UIHostingController(rootView: view)
        host = vc
        top.present(vc, animated: true)
    }
}
