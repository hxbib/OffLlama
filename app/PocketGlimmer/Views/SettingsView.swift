import SwiftUI
import UIKit
import Security

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var keyStatus = ""
    @AppStorage("meta_model") private var metaModel = "muse-spark-1.3"
    @AppStorage("byok_url") private var byokURL = ""
    @AppStorage("byok_model") private var byokModel = ""
    @AppStorage("voice_stays_on_device") private var voiceStaysOnDevice = false
    @State private var metaKey = ""
    @State private var metaKeySaved = Keychain.get("meta_key") != nil
    @State private var byokKey = ""
    @State private var byokKeySaved = Keychain.get("byok_key") != nil
    @State private var exportStatus = ""
    @AppStorage("pg_kv_prefix") private var kvPrefix = false

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
                    TextField("Model", text: $metaModel).textInputAutocapitalization(.never)
                    SecureField("New API key", text: $metaKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text(metaKeySaved ? "Key saved in Keychain" : "No key saved").font(.caption).foregroundStyle(.secondary)
                    if metaKeySaved { Button("Remove Meta key", role: .destructive) { removeKey("meta_key") } }
                } header: { Text("Meta Model API · Muse Spark / Muse Wonder") } footer: {
                    Text("Standard mode only. Contributor-mode ids are refused before any request leaves the phone.")
                }
                Section {
                    Toggle("Voice stays on this iPhone", isOn: $voiceStaysOnDevice)
                } header: { Text("Voice") } footer: {
                    Text("Off: the recording is sent to Muse Voice Transcribe after you release the mic, then deleted. The transcript goes through the same privacy gate as typed text. On: hold-to-talk sends nothing.")
                }
                DisclosureGroup("Other OpenAI-compatible endpoint") {
                    TextField("Base URL (…/v1/)", text: $byokURL).textInputAutocapitalization(.never).keyboardType(.URL)
                    TextField("Model", text: $byokModel).textInputAutocapitalization(.never)
                    SecureField("New API key", text: $byokKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text(byokKeySaved ? "Key saved in Keychain" : "No key saved").font(.caption).foregroundStyle(.secondary)
                    if byokKeySaved { Button("Remove endpoint key", role: .destructive) { removeKey("byok_key") } }
                }
                Section {
                    Button("Export decisions for distillation") {
                        if let r = model.exportDistillation() {
                            exportStatus = "\(r.rows) escalated decision\(r.rows == 1 ? "" : "s") → Files › Pocket Glimmer › \(r.url.lastPathComponent)"
                        } else { exportStatus = "Export failed (model not loaded yet?)" }
                    }
                    if !exportStatus.isEmpty { Text(exportStatus).font(.caption).foregroundStyle(.secondary) }
                } header: { Text("Distillation loop") } footer: {
                    Text("Exports recent low-confidence decisions and their request context for future model training. The app does not upload this file. Your device backup settings may include it.")
                }
                Section("Apple Dictation and Vocal Shortcuts") {
                    Text("Tap the microphone on the Apple keyboard to dictate, then review your text before sending.")
                    Text("In Shortcuts, create a shortcut with Dictate Text followed by Ask OffLlama, passing the dictated text as Request. In Settings > Accessibility > Vocal Shortcuts, assign that shortcut the phrase Hey OffLlama. Opening the app may require unlocking your iPhone.")
                }
                Section("About") {
                    Text("Built with Llama").font(.callout.weight(.semibold))
                    Text("On-device model: Llama 3.2, licensed under the Llama 3.2 Community License, Copyright © Meta Platforms, Inc. All Rights Reserved.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section { Button("Save") {
                    var failures: [String] = []
                    if !metaKey.isEmpty {
                        if Keychain.set(metaKey, for: "meta_key") == errSecSuccess { metaKey = "" } else { failures.append("Meta") }
                    }
                    if !byokKey.isEmpty {
                        if Keychain.set(byokKey, for: "byok_key") == errSecSuccess { byokKey = "" } else { failures.append("endpoint") }
                    }
                    refreshKeyState()
                    keyStatus = failures.isEmpty ? "Settings saved." : "Could not save the \(failures.joined(separator: " and ")) key. The previous key was retained."
                    model.reloadCloud()
                }
                    if !keyStatus.isEmpty { Text(keyStatus).font(.caption) }
                } footer: { Text("Keys are stored in the iOS Keychain on this device only. Without keys, built-in cloud inference is unavailable. Links and Shortcuts can still open other apps.") }
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } } }
            .navigationTitle("Settings")
            .onDisappear { clearSecrets() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { clearSecrets() } }
        }
    }

    private func clearSecrets() { metaKey = ""; byokKey = "" }
    private func refreshKeyState() {
        metaKeySaved = Keychain.get("meta_key") != nil
        byokKeySaved = Keychain.get("byok_key") != nil
    }
    private func removeKey(_ key: String) {
        let status = Keychain.remove(key)
        refreshKeyState()
        keyStatus = (status == errSecSuccess || status == errSecItemNotFound) ? "Key removed." : "Could not remove key."
        model.reloadCloud()
    }
}
