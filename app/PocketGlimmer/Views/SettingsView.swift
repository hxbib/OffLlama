import SwiftUI
import UIKit
import PocketCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("voice_stays_on_device") private var voiceStaysOnDevice = false
    @AppStorage("pg_kv_prefix") private var kvPrefix = false

    @State private var metaModel = UserDefaults.standard.string(forKey: "meta_model") ?? "muse-spark-1.3"
    @State private var byokURL = UserDefaults.standard.string(forKey: "byok_url") ?? ""
    @State private var byokModel = UserDefaults.standard.string(forKey: "byok_model") ?? ""
    @State private var metaKey = ""
    @State private var byokKey = ""
    @State private var metaKeySaved = Keychain.presence("meta_key") == .saved
    @State private var byokKeySaved = Keychain.presence("byok_key") == .saved
    @State private var results: [SaveLine] = []
    @State private var exportStatus = ""

    struct SaveLine: Identifiable, Equatable {
        enum Level { case good, warning, problem }
        let id = UUID()
        let level: Level
        let text: String
        var symbol: String {
            switch level { case .good: return "checkmark.circle.fill"; case .warning: return "exclamationmark.triangle.fill"; case .problem: return "xmark.octagon.fill" }
        }
        var tint: Color { switch level { case .good: return .green; case .warning: return .orange; case .problem: return .red } }
    }

    private var metaPreview: CloudRouteStatus { CloudSettingsCheck.meta(model: metaModel, keySaved: metaKeySaved || !metaKey.isEmpty) }
    private var byokPreview: CloudRouteStatus { CloudSettingsCheck.custom(baseURL: byokURL, model: byokModel, keySaved: byokKeySaved || !byokKey.isEmpty) }
    private var hasUnsavedChanges: Bool {
        let d = UserDefaults.standard
        return !metaKey.isEmpty || !byokKey.isEmpty
            || metaModel.trimmed != (d.string(forKey: "meta_model") ?? "muse-spark-1.3").trimmed
            || byokURL.trimmed != (d.string(forKey: "byok_url") ?? "").trimmed
            || byokModel.trimmed != (d.string(forKey: "byok_model") ?? "").trimmed
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Reflex + local answers", value: model.modelState)
                    StatusPill()
                    Toggle("Reuse cached prompt prefix", isOn: $kvPrefix)
                } header: { Text("On-device model") } footer: {
                    Text("Keeps each decision type's fixed prompt prefix in the KV cache so a decision only evaluates the new part. Applies on next launch.")
                }
                Section {
                    TextField("Model", text: $metaModel).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("New API key", text: $metaKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Meta API key").accessibilityHint("Enter a key to save or replace the saved one. Leave empty to keep it.")
                    keyStateRow(saved: metaKeySaved, entered: !metaKey.isEmpty)
                    routeRow(metaPreview)
                    if metaKeySaved { Button("Remove Meta key", role: .destructive) { removeKey("meta_key", label: "Meta", clearsEntry: { metaKey = "" }) } }
                } header: { Text("Meta Model API · Muse Spark / Muse Wonder") } footer: {
                    Text("Standard mode only. Contributor-mode ids are refused before any request leaves the phone. The key field is always empty; the saved key is never shown.")
                }
                Section {
                    Toggle("Voice stays on this iPhone", isOn: $voiceStaysOnDevice)
                } header: { Text("Muse voice upload") } footer: {
                    Text("The waveform button in chat records audio and, after you release it, uploads it to Muse Voice Transcribe, then deletes it. It needs internet and a Meta key, and it is not Apple Dictation. On: the waveform button sends nothing.")
                }
                DisclosureGroup("Other OpenAI-compatible endpoint") {
                    TextField("Base URL (…/v1/)", text: $byokURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("Model", text: $byokModel).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("New API key", text: $byokKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Endpoint API key").accessibilityHint("Enter a key to save or replace the saved one. Leave empty to keep it.")
                    keyStateRow(saved: byokKeySaved, entered: !byokKey.isEmpty)
                    routeRow(byokPreview)
                    if byokKeySaved { Button("Remove endpoint key", role: .destructive) { removeKey("byok_key", label: "Endpoint", clearsEntry: { byokKey = "" }) } }
                }
                Section {
                    Button("Export decisions for distillation") {
                        if let r = model.exportDistillation() {
                            exportStatus = "\(r.rows) escalated decision\(r.rows == 1 ? "" : "s") → Files › OffLlama › \(r.url.lastPathComponent)"
                        } else { exportStatus = "Export failed (model not loaded yet?)" }
                    }
                    if !exportStatus.isEmpty { Text(exportStatus).font(.caption).foregroundStyle(.secondary) }
                } header: { Text("Distillation loop") } footer: {
                    Text("Exports recent low-confidence decisions and their request context for future model training. The app does not upload this file. Your device backup settings may include it.")
                }
                Section("Apple Dictation and Vocal Shortcuts") {
                    Text("To dictate text, tap the microphone on the Apple keyboard, speak, and review the text before you send it. Whether dictation works offline depends on your iPhone, its language and its settings.")
                    Text("For a hands-free route, make a shortcut in Shortcuts: Dictate Text, then Ask OffLlama with Request set to the Dictated Text. In Settings › Accessibility › Vocal Shortcuts, add the phrase “Hey OffLlama” and choose that shortcut. Opening the app may need your iPhone unlocked.")
                }
                Section("About") {
                    Text("Built with Llama").font(.callout.weight(.semibold))
                    Text("On-device model: Llama 3.2, licensed under the Llama 3.2 Community License, Copyright © Meta Platforms, Inc. All Rights Reserved.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("Save", action: save)
                    if hasUnsavedChanges { Label("Changes are not saved yet.", systemImage: "pencil.circle").font(.caption).foregroundStyle(.secondary) }
                    ForEach(results) { line in
                        Label { Text(line.text).font(.caption) } icon: { Image(systemName: line.symbol).foregroundStyle(line.tint) }
                            .accessibilityElement(children: .combine)
                    }
                } footer: { Text("Keys are stored in the iOS Keychain on this device only. Without a working key, cloud help is unavailable and OffLlama answers on the phone. Links and Shortcuts can still open other apps.") }
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { UIApplication.resignKeyboard() } } }
            .navigationTitle("Settings")
            .onAppear { refreshKeyState() }
            .onDisappear { clearSecrets() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { clearSecrets() } }
        }
    }

    @ViewBuilder private func keyStateRow(saved: Bool, entered: Bool) -> some View {
        Label(entered ? "New key entered. Save to store it." : (saved ? "A key is saved in Keychain." : "No key saved."),
              systemImage: saved ? "key.fill" : "key").font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private func routeRow(_ status: CloudRouteStatus) -> some View {
        let level: SaveLine.Level = status.isEnabled ? .good : (status.state == .refused ? .problem : .warning)
        let line = SaveLine(level: level, text: status.detail)
        if status.state != .notConfigured {
            Label { Text(status.detail).font(.caption) } icon: { Image(systemName: line.symbol).foregroundStyle(line.tint) }
                .accessibilityElement(children: .combine)
        }
    }

    private func save() {
        UIApplication.resignKeyboard()
        let d = UserDefaults.standard
        metaModel = metaModel.trimmed; byokURL = byokURL.trimmed; byokModel = byokModel.trimmed
        d.set(metaModel, forKey: "meta_model"); d.set(byokURL, forKey: "byok_url"); d.set(byokModel, forKey: "byok_model")

        var lines: [SaveLine] = []
        let store = KeychainStore()
        for (account, label, entry) in [("meta_key", "Meta", metaKey), ("byok_key", "Endpoint", byokKey)] {
            let outcome = KeyEntry.commit(entered: entry, account: account, store: store)
            guard let text = KeyEntry.message(outcome, label: label) else { continue }
            switch outcome {
            case .saved: lines.append(.init(level: .good, text: text)); if account == "meta_key" { metaKey = "" } else { byokKey = "" }
            case .failed, .malformed: lines.append(.init(level: .problem, text: text))
            case .nothingEntered: break
            }
        }
        refreshKeyState()
        model.reloadCloud()
        let meta = CloudSettingsCheck.meta(model: metaModel, keySaved: metaKeySaved)
        let custom = CloudSettingsCheck.custom(baseURL: byokURL, model: byokModel, keySaved: byokKeySaved)
        lines.append(.init(level: meta.isEnabled ? .good : (meta.state == .refused ? .problem : .warning), text: "Meta: " + meta.detail))
        if custom.state != .notConfigured {
            lines.append(.init(level: custom.isEnabled ? .good : (custom.state == .refused ? .problem : .warning), text: "Endpoint: " + custom.detail))
        }
        results = lines
        UIAccessibility.post(notification: .announcement, argument: lines.map(\.text).joined(separator: " "))
    }

    private func clearSecrets() { metaKey = ""; byokKey = "" }

    private func refreshKeyState() {
        metaKeySaved = Keychain.presence("meta_key") == .saved
        byokKeySaved = Keychain.presence("byok_key") == .saved
    }

    private func removeKey(_ account: String, label: String, clearsEntry: () -> Void) {
        let removal = KeyEntry.remove(account: account, store: KeychainStore())
        clearsEntry()
        refreshKeyState()
        model.reloadCloud()
        let failed: Bool = { if case .failed = removal { return true } else { return false } }()
        results = [.init(level: failed ? .problem : .good, text: KeyEntry.message(removal, label: label))]
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
