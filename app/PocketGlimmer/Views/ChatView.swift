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
                    if let b = item.badge { Text(b).font(.caption2.monospaced()).foregroundStyle(.secondary).padding(.leading, 6) }
                }
                Spacer(minLength: 48)
            }
        }
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
