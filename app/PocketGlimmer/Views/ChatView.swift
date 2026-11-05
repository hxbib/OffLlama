import SwiftUI
import UIKit
import Contacts
import PocketCore

struct ChatView: View {
    @Environment(AppModel.self) private var model
    @State private var input = ""
    @FocusState private var focused: Bool
    @State private var showChats = false
    @State private var newChatError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var sendSize = 32

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if model.chat.isEmpty { EmptyChat() }
                        ForEach(model.chat) { item in Bubble(item: item).id(item.id) }
                        if model.busyConversationID == model.activeConversationID { ProgressView().padding(.top, 4) }
                        Color.clear.frame(height: 1).id(Self.bottomID)
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.chat.count) { scrollToBottom(proxy) }
                .onChange(of: focused) { _, isFocused in if isFocused { scrollToBottom(proxy) } }
                .onChange(of: input) { if focused { scrollToBottom(proxy) } }
                // The composer is a bottom safe-area inset, so the scroll view, the keyboard and the composer
                // share one inset. A plain VStack under a ScrollView leaves the last rows to the keyboard.
                .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            }
            .toolbar {
                ToolbarItem(placement: .principal) { StatusPill() }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showChats = true } label: { Label("Chats", systemImage: "list.bullet") }
                        .accessibilityHint("Shows your saved chats")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newChatError = model.newChat() } label: { Label("New chat", systemImage: "square.and.pencil") }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showChats) { ConversationListView() }
            .alert("Can't start a new chat", isPresented: Binding(get: { newChatError != nil }, set: { if !$0 { newChatError = nil } })) {
                Button("OK", role: .cancel) { }
            } message: { Text(newChatError ?? "") }
        }
    }

    private static let bottomID = "chat-bottom"

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if reduceMotion { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
        else { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) } }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if let notice = model.historyNotice {
                Text(notice).font(.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.top, 6)
            }
            HStack(alignment: .bottom, spacing: 10) {
                if focused {
                    Button { focused = false; UIApplication.resignKeyboard() } label: {
                        Image(systemName: "keyboard.chevron.compact.down").font(.title3).frame(minWidth: 44, minHeight: 44)
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Hide keyboard")
                } else {
                    MicButton()
                    CameraButton()
                }
                TextField("Ask or tell me something", text: $input, axis: .vertical)
                    .lineLimit(1...5).focused($focused)
                    .accessibilityLabel("Message")
                    .accessibilityHint("Type, or use the microphone on the keyboard to dictate with Apple Dictation.")
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.quaternary))
                Button {
                    guard model.assistant != nil, !model.busy else { return }
                    let t = input
                    Task {
                        await model.send(t, onAccepted: {
                            if input == t { input = "" }
                        })
                    }
                } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: sendSize)).frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Send")
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy || model.assistant == nil)
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
        .background(.bar)
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
            VStack(spacing: 6) {
                Text(item.text).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let b = item.badge { outcomeChip(b) }
            }
            .frame(maxWidth: .infinity).padding(.horizontal, 24)
            .contextMenu { copyButton }
        case .user:
            HStack { Spacer(minLength: 56)
                Text(item.text).padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .foregroundStyle(.white)
                    .contextMenu { copyButton }
            }
        case .assistant:
            HStack { VStack(alignment: .leading, spacing: 6) {
                    if let card = item.card {
                        DraftCardView(item: item, card: card)
                    } else {
                        ReplyBodyView(text: item.text)
                            .contextMenu { copyButton }
                    }
                    HStack(spacing: 6) {
                        if item.keptOnDevice {
                            Label("Private · not sent", systemImage: "lock.fill")
                                .font(.caption.weight(.medium)).foregroundStyle(Theme.accent)
                                .accessibilityLabel("Private. Marked sensitive, nothing was sent.")
                        } else if let b = item.badge {
                            if item.cloudPromptSent != nil {
                                Button { showPrivacy = true } label: {
                                    Label(Self.outcome(b), systemImage: "cloud").font(.caption.weight(.medium))
                                }
                                .buttonStyle(.borderless).tint(Theme.accent)
                                .accessibilityHint("Shows the masked text prepared for the cloud")
                            } else {
                                outcomeChip(b)
                            }
                        }
                        if !item.decisions.isEmpty || item.detail != nil {
                            Button { withAnimation(.snappy) { showDecisions.toggle() } } label: {
                                Image(systemName: showDecisions ? "chevron.up.circle" : "info.circle")
                                    .font(.caption).frame(minWidth: 32, minHeight: 32)
                            }
                            .buttonStyle(.borderless).foregroundStyle(.tertiary)
                            .accessibilityLabel(showDecisions ? "Hide details" : "Details")
                        }
                    }.padding(.leading, 8)
                    if showDecisions {
                        if let detail = item.detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                                .padding(.horizontal, 10).fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(spacing: 2) { ForEach(item.decisions) { DecisionCard(row: $0, startExpanded: $0.toolCallJSON != nil) } }
                            .padding(10).background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                Spacer(minLength: 48)
            }
            .sheet(isPresented: $showPrivacy) { PrivacySheet(sent: item.cloudPromptSent ?? "", provider: item.badge ?? "") }
        }
    }

    private var copyButton: some View {
        Button { UIPasteboard.general.string = item.text } label: { Label("Copy", systemImage: "doc.on.doc") }
    }

    private func outcomeChip(_ badge: String) -> some View {
        Text(Self.outcome(badge)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
    }

    /// Drops timing from a status badge; every other qualifier (cloud attempt, best effort, unverified) stays.
    static func outcome(_ badge: String) -> String {
        badge.replacingOccurrences(of: #" · answered in [^·]+$"#, with: "", options: .regularExpression)
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
                Button(CNContactStore.authorizationStatus(for: .contacts) == .notDetermined ? "Allow Contacts" : "Refresh contact") {
                    Task { await model.refreshContacts(item) }
                }
                .disabled(model.busy)
                .frame(minHeight: 44)
                if CNContactStore.authorizationStatus(for: .contacts) == .denied {
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .frame(minHeight: 44)
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
