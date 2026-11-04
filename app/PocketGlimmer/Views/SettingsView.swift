import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("meta_model") private var metaModel = "muse-spark-1.3"
    @AppStorage("byok_url") private var byokURL = ""
    @AppStorage("byok_model") private var byokModel = ""
    @AppStorage("voice_stays_on_device") private var voiceStaysOnDevice = false
    @State private var metaKey = Keychain.get("meta_key") ?? ""
    @State private var byokKey = Keychain.get("byok_key") ?? ""
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
                    SecureField("API key", text: $metaKey)
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
                    SecureField("API key", text: $byokKey)
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
                Section("About") {
                    Text("Built with Llama").font(.callout.weight(.semibold))
                    Text("On-device model: Llama 3.2, licensed under the Llama 3.2 Community License, Copyright © Meta Platforms, Inc. All Rights Reserved.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section { Button("Save") {
                    Keychain.set(metaKey, for: "meta_key"); Keychain.set(byokKey, for: "byok_key")
                    model.reloadCloud()
                } } footer: { Text("Keys are stored in the iOS Keychain on this device only. Without keys, built-in cloud inference is unavailable. Links and Shortcuts can still open other apps.") }
            }
            .navigationTitle("Settings")
        }
    }
}
