import SwiftUI

struct ChatView: View {
    @Environment(AppModel.self) private var model
    @State private var input = ""
    @FocusState private var focused: Bool

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
                    .onChange(of: model.chat.count) { if let l = model.chat.last { withAnimation { proxy.scrollTo(l.id, anchor: .bottom) } } }
                }
                if let last = model.decisions.first { LiveReflexStrip(row: last) }
                HStack(spacing: 10) {
                    TextField("Ask or tell me something", text: $input, axis: .vertical)
                        .lineLimit(1...4).focused($focused)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
                    Button {
                        let t = input; input = ""
                        Task { await model.send(t) }
                    } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 32)) }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || model.busy)
                }
                .padding(.horizontal).padding(.vertical, 8)
            }
            .toolbar { ToolbarItem(placement: .principal) { StatusPill() } }
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
            Text(String(format: "%.0f%%", row.confidence * 100)).font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.confidenceColor(row.confidence))
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
                    Text(item.text).padding(12).background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
                    if let p = item.pending {
                        HStack {
                            Button("Confirm") { Task { await model.confirm(item) } }.buttonStyle(.borderedProminent)
                            Button("Cancel", role: .cancel) { model.cancel(item) }.buttonStyle(.bordered)
                        }.controlSize(.small).accessibilityHint("Runs \(p.tool)")
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

/// What actually left the phone: names, emails, numbers replaced by placeholders before the cloud call.
struct PrivacySheet: View {
    let sent: String, provider: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Label(provider, systemImage: "arrow.up.forward.circle").font(.headline)
                    Text("Sent after masking on device:").font(.subheadline).foregroundStyle(.secondary)
                    Text(highlighted).font(.callout.monospaced()).textSelection(.enabled)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    Text("Placeholders like [PERSON_1] are restored to real names only on this iPhone.").font(.caption).foregroundStyle(.secondary)
                }.padding()
            }
            .navigationTitle("Privacy").navigationBarTitleDisplayMode(.inline)
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

struct EmptyChat: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkle").font(.system(size: 36, weight: .light)).foregroundStyle(Theme.accent)
            Text("Try: “Remind me to call Mom at 7”").foregroundStyle(.secondary)
            Text("or “I'm out of oat milk”").foregroundStyle(.tertiary)
        }
        .font(.callout).padding(.top, 120)
    }
}
