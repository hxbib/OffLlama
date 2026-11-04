import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("meta_model") private var metaModel = "muse-spark-1.3"
    @AppStorage("fireworks_model") private var fwModel = "accounts/fireworks/models/muse-glimmer-30b"
    @AppStorage("byok_url") private var byokURL = ""
    @AppStorage("byok_model") private var byokModel = ""
    @State private var metaKey = Keychain.get("meta_key") ?? ""
    @State private var fwKey = Keychain.get("fireworks_key") ?? ""
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
                } header: { Text("Meta Model API · Muse Spark / Muse Wonder") }
                Section {
                    TextField("Model", text: $fwModel).textInputAutocapitalization(.never)
                    SecureField("API key", text: $fwKey)
                } header: { Text("Muse Glimmer 30B (hosted open weights)") }
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
                    Text("Writes the last 30 days of low-confidence (escalated) decisions as JSONL for the next teacher-labeling round. The file stays on this iPhone until you share it; nothing is uploaded.")
                }
                Section("About") {
                    Text("Built with Llama").font(.callout.weight(.semibold))
                    Text("On-device model: Llama 3.2, licensed under the Llama 3.2 Community License, Copyright © Meta Platforms, Inc. All Rights Reserved.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section { Button("Save") {
                    Keychain.set(metaKey, for: "meta_key"); Keychain.set(fwKey, for: "fireworks_key"); Keychain.set(byokKey, for: "byok_key")
                    model.reloadCloud()
                } } footer: { Text("Keys are stored in the iOS Keychain on this device only. Without keys, everything stays on device.") }
            }
            .navigationTitle("Settings")
        }
    }
}
