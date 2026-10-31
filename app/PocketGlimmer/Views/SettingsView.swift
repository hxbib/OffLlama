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

    var body: some View {
        NavigationStack {
            Form {
                Section("On-device model") {
                    LabeledContent("Reflex + local answers", value: model.modelState)
                    StatusPill()
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
                Section { Button("Save") {
                    Keychain.set(metaKey, for: "meta_key"); Keychain.set(fwKey, for: "fireworks_key"); Keychain.set(byokKey, for: "byok_key")
                    model.reloadCloud()
                } } footer: { Text("Keys are stored in the iOS Keychain on this device only. Without keys, everything stays on device.") }
            }
            .navigationTitle("Settings")
        }
    }
}
