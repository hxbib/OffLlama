import SwiftUI
import PocketCore

struct MemoryView: View {
    @Environment(AppModel.self) private var model
    var grouped: [(String, [MemoryFact])] {
        Dictionary(grouping: model.facts, by: { $0.subject == "user" ? "You" : $0.subject.capitalized })
            .sorted { $0.key == "You" ? true : ($1.key == "You" ? false : $0.key < $1.key) }
    }
    var body: some View {
        NavigationStack {
            List {
                if model.facts.isEmpty {
                    ContentUnavailableView("Nothing remembered yet", systemImage: "brain",
                                           description: Text("Tell me things like “I'm allergic to peanuts”. Memories are stored only on this phone; when a request escalates, the relevant ones are sent masked."))
                }
                if !model.onePager.isEmpty {
                    Section {
                        Text(model.onePager).font(.caption.monospaced()).textSelection(.enabled)
                    } header: { Text("Profile") } footer: {
                        Text("What the on-device model always sees, rebuilt from your memories. Never leaves the phone unless a request escalates, and then masked.")
                    }
                }
                if !model.board.isEmpty {
                    Section("Tasks") {
                        ForEach(model.board.dueSoon + model.board.open + model.board.shopping, id: \.fact.id) { item in
                            HStack {
                                Image(systemName: model.board.shopping.contains(item) ? "cart" : "circle")
                                Text(item.fact.value)
                                Spacer()
                                if let d = item.due { Text(d.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                if !model.corrections.isEmpty {
                    Section("Recently corrected") {
                        ForEach(model.corrections, id: \.new.id) { c in
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Corrected by you", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                                Text(c.old.text).strikethrough().foregroundStyle(.secondary)
                                Text(c.new.text)
                                Text(c.new.updatedAt.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                ForEach(grouped, id: \.0) { subject, facts in
                    Section(subject) {
                        ForEach(facts) { f in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(f.text)
                                HStack(spacing: 8) {
                                    Text(f.attribute.replacingOccurrences(of: "_", with: " ")).font(.caption.monospaced())
                                    if !f.aliases.isEmpty { Text("aka " + f.aliases.joined(separator: ", ")).font(.caption) }
                                    if let e = f.expiresAt { Label(e.formatted(.relative(presentation: .named)), systemImage: "hourglass").font(.caption) }
                                }.foregroundStyle(.secondary)
                            }
                            .swipeActions { Button("Forget", role: .destructive) { model.forget(f) } }
                        }
                    }
                }
            }
            .navigationTitle("Memory")
            .onAppear { model.refresh() }
        }
    }
}
