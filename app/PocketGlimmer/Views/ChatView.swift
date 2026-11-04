import SwiftUI
import UIKit
import PocketCore

struct ChatView: View {
    @Environment(AppModel.self) private var model
    @State private var input = ""
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var sendSize = 32

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if model.chat.isEmpty { EmptyChat() }
                            ForEach(model.chat) { item in Bubble(item: item).id(item.id) }
                            if model.busy { ProgressView().padding(.top, 4) }
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: model.chat.count) {
                        guard let l = model.chat.last else { return }
                        if reduceMotion { proxy.scrollTo(l.id, anchor: .bottom) } else { withAnimation { proxy.scrollTo(l.id, anchor: .bottom) } }
                    }
                }
                if let last = model.decisions.first { LiveReflexStrip(row: last) }
                HStack(spacing: 10) {
                    MicButton()       // hold to talk: uploads audio to Muse Voice Transcribe -> the same Reflex path as typed text (online only; not Apple Dictation)
                    CameraButton()    // glimpse: sensitivity gate -> Muse Spark 1.3 vision / SAM 3.1 (online only)
                    TextField("Ask or tell me something", text: $input, axis: .vertical)
                        .lineLimit(1...4).focused($focused)
                        .accessibilityLabel("Message")
                        .accessibilityHint("Type, or use the microphone on the keyboard to dictate with Apple Dictation.")
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
                    Button {
                        guard model.assistant != nil, !model.busy else { return }
                        let t = input; input = ""
                        Task { await model.send(t) }
                    } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: sendSize)).frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Send")
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || model.busy || model.assistant == nil)
                }
                .padding(.horizontal).padding(.vertical, 8)
            }
            .toolbar {
                ToolbarItem(placement: .principal) { StatusPill() }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false; UIApplication.resignKeyboard() } }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// The latest Reflex decision, always visible above the composer: the "acts instantly, shows confidence" moment.
struct LiveReflexStrip: View {
    let row: DecisionRow
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill").foregroundStyle(Theme.accent)
            Text(row.type).font(.caption.monospaced()).foregroundStyle(.secondary)
            Text(row.choice.replacingOccurrences(of: "_", with: " ")).font(.caption.weight(.semibold))
            Spacer()
            Text(String(format: "%.0f%%", row.confidence * 100)).font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.confidenceColor(row.confidence, tau: row.tau))
            Text(String(format: "%.0f ms", row.ms)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.bar)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .id(row.id)
    }
}

struct Bubble: View {
    @Environment(AppModel.self) private var model
    let item: ChatItem
    @State private var showDecisions = false
    @State private var showPrivacy = false
    var body: some View {
        switch item.role {
        case .system:
            Text(item.text).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        case .user:
            HStack { Spacer(minLength: 48)
                Text(item.text).padding(12).background(Theme.accent, in: RoundedRectangle(cornerRadius: 18)).foregroundStyle(.white)
            }
        case .assistant:
            HStack { VStack(alignment: .leading, spacing: 6) {
                    if let card = item.card {
                        DraftCardView(item: item, card: card)
                    } else {
                        ReplyBodyView(text: item.text)
                    }
                    if item.keptOnDevice {
                        Label("Kept on device · nothing sent", systemImage: "lock.fill")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Theme.accent.opacity(0.12), in: Capsule())
                            .foregroundStyle(Theme.accent)
                            .padding(.leading, 6)
                            .accessibilityLabel("Kept on device. Marked sensitive, nothing was sent.")
                    }
                    HStack(spacing: 8) {
                        if let b = item.badge {
                            if item.cloudPromptSent != nil {
                                Button { showPrivacy = true } label: {
                                    Label(b, systemImage: "lock.shield").font(.caption2.weight(.medium))
                                }.buttonStyle(.bordered).controlSize(.mini).tint(Theme.accent)
                            } else {
                                Text(b).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                        if !item.decisions.isEmpty {
                            Button { withAnimation(.snappy) { showDecisions.toggle() } } label: {
                                Label("\(item.decisions.count) decisions", systemImage: "bolt.fill").font(.caption2)
                            }.buttonStyle(.borderless).foregroundStyle(.secondary)
                        }
                    }.padding(.leading, 6)
                    if showDecisions {
                        VStack(spacing: 2) { ForEach(item.decisions) { DecisionCard(row: $0, startExpanded: $0.toolCallJSON != nil) } }
                            .padding(10).background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                Spacer(minLength: 48)
            }
            .sheet(isPresented: $showPrivacy) { PrivacySheet(sent: item.cloudPromptSent ?? "", provider: item.badge ?? "") }
        }
    }
}

/// The masked text prepared for a cloud request. Availability of this text does not confirm delivery.
struct PrivacySheet: View {
    let sent: String, provider: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Label(provider, systemImage: "arrow.up.forward.circle").font(.headline)
                    Text("Cloud request text").font(.subheadline.weight(.semibold))
                    Text("Masked on device. A failed request may already have reached the provider.").font(.subheadline).foregroundStyle(.secondary)
                    Text(highlighted).font(.callout.monospaced()).textSelection(.enabled)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    Text("Placeholders like [PERSON_1] are restored to real names only on this iPhone.").font(.caption).foregroundStyle(.secondary)
                }.padding()
            }
            .navigationTitle("Cloud request").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
    var highlighted: AttributedString {
        var a = AttributedString(sent)
        var search = a.startIndex
        while let r = a[search...].range(of: #"\[[A-Z]+_\d+\]"#, options: .regularExpression) {
            a[r].foregroundColor = Theme.accent; a[r].font = .callout.monospaced().weight(.semibold)
            search = r.upperBound
        }
        return a
    }
}

/// An editable projection of one durable ledger card. Text is gathered at Confirm; contact/method/time edits
/// are persisted through the revision-guarded edit path as soon as they are chosen.
struct DraftCardView: View {
    @Environment(AppModel.self) private var model
    let item: ChatItem
    let card: DraftCard
    @State private var textEdits: [String: String] = [:]
    @State private var instantEdits: [String: Date] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title).font(.headline)
            Text(card.reviewSentence).font(.caption).foregroundStyle(.secondary)
            ForEach(card.fields, id: \.name) { field in
                fieldView(field)
            }
            if !card.notice.isEmpty {
                Text(card.notice).font(.caption).foregroundStyle(.orange)
            }
            if let hint = card.duplicateHint {
                Text(hint.note).font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Button("Confirm") { confirm() }.buttonStyle(.borderedProminent)
                    .disabled(!card.canConfirm || model.busy)
                Button("Cancel", role: .cancel) { Task { await model.cancel(item) } }
                    .buttonStyle(.bordered).disabled(model.busy)
            }.controlSize(.small)
            .accessibilityElement(children: .contain)
            .accessibilityHint(draftHint)
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private func fieldView(_ field: DraftField) -> some View {
        switch field.kind {
        case .contact:
            VStack(alignment: .leading, spacing: 4) {
                Text(field.name.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption2).foregroundStyle(.secondary)
                if !field.choices.isEmpty {
                    Menu {
                        ForEach(field.choices, id: \.identifier) { choice in
                            Button {
                                Task { await model.edit(item, edits: [DraftEdit(field: field.name, value: .contactID(choice.identifier))]) }
                            } label: {
                                Text(choice.detail.isEmpty ? choice.displayName : "\(choice.displayName) — \(choice.detail)")
                            }
                        }
                    } label: {
                        Label(field.value.isEmpty ? "Choose contact" : field.value, systemImage: "person.crop.circle")
                    }
                } else {
                    Text(field.value.isEmpty ? "No matching contact" : field.value).font(.callout)
                }
            }
        case .method:
            VStack(alignment: .leading, spacing: 4) {
                Text("Destination").font(.caption2).foregroundStyle(.secondary)
                Menu {
                    ForEach(field.methods, id: \.self) { method in
                        Button(method.display) {
                            Task { await model.edit(item, edits: [DraftEdit(field: field.name, value: .contactMethod(method))]) }
                        }
                    }
                } label: {
                    Label(field.value.isEmpty ? "Choose phone or email" : field.value, systemImage: "phone")
                }
            }
        case .instant:
            VStack(alignment: .leading, spacing: 4) {
                Text(field.value.isEmpty ? "Choose the exact date and time" : field.value)
                    .font(.callout)
                HStack {
                    DatePicker("", selection: instantBinding(field), displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                    if let picked = instantEdits[field.name] {
                        Button("Use time") {
                            Task {
                                await model.edit(item, edits: [DraftEdit(field: field.name, value: .instant(picked))])
                                instantEdits[field.name] = nil
                            }
                        }.buttonStyle(.bordered).controlSize(.mini)
                    }
                }
                Text("Timezone: \(field.timeZoneID ?? TimeZone.current.identifier)").font(.caption2).foregroundStyle(.secondary)
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text(field.name.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption2).foregroundStyle(.secondary)
                if field.name == "destination" {
                    Text(field.value).font(.callout).textSelection(.enabled)
                } else {
                    TextField(field.value, text: textBinding(field), axis: .vertical)
                        .lineLimit(field.name == "body" ? 2...6 : 1...3)
                        .textFieldStyle(.roundedBorder)
                    if let value = textEdits[field.name], value != field.value {
                        Button("Save edit") {
                            Task {
                                await model.edit(item, edits: [DraftEdit(field: field.name, value: .text(value))])
                                textEdits[field.name] = nil
                            }
                        }.buttonStyle(.bordered).controlSize(.mini)
                    }
                }
            }
        }
    }

    private func textBinding(_ field: DraftField) -> Binding<String> {
        Binding(get: { textEdits[field.name] ?? field.value }, set: { textEdits[field.name] = $0 })
    }

    private func instantBinding(_ field: DraftField) -> Binding<Date> {
        Binding(get: { instantEdits[field.name] ?? field.instant ?? Date().addingTimeInterval(3600) },
                set: { instantEdits[field.name] = $0 })
    }

    private func confirm() {
        var edits: [DraftEdit] = []
        for field in card.fields where field.kind == .text {
            let value = textEdits[field.name] ?? field.value
            if value != field.value { edits.append(DraftEdit(field: field.name, value: .text(value))) }
        }
        for field in card.fields where field.kind == .instant {
            if let picked = instantEdits[field.name], picked != field.instant {
                edits.append(DraftEdit(field: field.name, value: .instant(picked)))
            }
        }
        Task { await model.confirm(item, edits: edits) }
    }

    /// VoiceOver hears a human title and the bound destination, not a raw tool id.
    private var draftHint: String {
        let destination = card.fields.first { $0.name == "destination" || $0.kind == .contact }?.value ?? ""
        let methods = card.fields.filter { $0.kind == .method }.map(\.value).filter { !$0.isEmpty }
        let whereText = ([destination] + methods).filter { !$0.isEmpty }.joined(separator: ", ")
        return [card.title, whereText.isEmpty ? "" : "to \(whereText)", card.reviewSentence]
            .filter { !$0.isEmpty }.joined(separator: ". ")
    }
}

struct EmptyChat: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.text.bubble.right").font(.system(size: 36, weight: .light)).foregroundStyle(Theme.accent)
            Text("Try: “Remind me to call Mom at 7”").foregroundStyle(.secondary)
            Text("or “I'm out of oat milk”").foregroundStyle(.tertiary)
        }
        .font(.callout).padding(.top, 120)
    }
}
