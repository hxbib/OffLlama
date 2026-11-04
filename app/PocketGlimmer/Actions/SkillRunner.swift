import Foundation
import UIKit
import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import PocketCore

/// Runs reply-only native reads. Effects (URL, Shortcut, EventKit, compose sheets, auto-reply memory) are
/// executed by `PocketEffects` after a claim; this runner has no path that opens a URL, runs a Shortcut, or sends.
final class IOSSkillRunner: SkillRunner, @unchecked Sendable {
    func run(_ skill: Skill, args: [String: String]) async throws -> String {
        guard CapabilityCatalog.isReplyOnly(skill.id) else {
            return "\(skill.title) is an effect; it must be confirmed through the effect ledger · nothing done"
        }
        switch skill.invocation {
        case .native(let handler):
            return await runNative(handler, skill: skill, args: args)
        case .cloudReason:
            return "Handled by the assistant, not the phone."   // PocketCore answers these before reaching the runner
        default:
            return "\(skill.title) is an effect; it must be confirmed through the effect ledger · nothing done"
        }
    }

    // MARK: Native read handlers

    private func runNative(_ handler: String, skill: Skill, args: [String: String]) async -> String {
        switch handler {
        case "device_status": return await deviceStatus()
        case "analyze_document": return await DocumentPicker.pickText() ?? ""
        case "html_viz":
            let data = args["data"] ?? ""
            guard let reply = HTMLViz.reply(text: data, title: args["title"] ?? "Chart") else {
                return "No numbers to chart. Paste them like “rent 1200, food 400”, or share a document first."
            }
            return reply
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
