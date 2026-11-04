import SwiftUI
import PocketCore

/// Saved chats. Clear and Delete always ask first and say what they change.
struct ConversationListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pendingClear: ConversationID?
    @State private var pendingDelete: ConversationID?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.book.conversations) { c in
                        Button {
                            model.selectChat(c.id); dismiss()
                        } label: { row(c) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) { pendingDelete = c.id }
                            Button("Clear") { pendingClear = c.id }.tint(.orange)
                        }
                        .contextMenu {
                            Button("Clear messages", systemImage: "eraser") { pendingClear = c.id }
                            Button("Delete chat", systemImage: "trash", role: .destructive) { pendingDelete = c.id }
                        }
                    }
                } footer: {
                    Text("Chats are stored only on this iPhone, protected while it is locked, and left out of backups. Clearing or deleting a chat does not delete saved memories. A waiting or unverified action is tracked separately and stays findable.")
                }
            }
            .navigationTitle("Chats").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { if let e = model.newChat() { message = e } else { dismiss() } } label: { Label("New chat", systemImage: "square.and.pencil") }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Clear this chat?", isPresented: Binding(get: { pendingClear != nil }, set: { if !$0 { pendingClear = nil } }),
                                titleVisibility: .visible) {
                Button("Clear messages", role: .destructive) {
                    if let id = pendingClear { message = model.clearChat(id) }
                    pendingClear = nil
                }
                Button("Cancel", role: .cancel) { pendingClear = nil }
            } message: {
                Text("This removes the messages and unfinished message drafts in this chat from this iPhone. It cannot be undone. Saved memories are not deleted. Any action that is waiting for you or whose outcome is unverified stays, and nothing is sent or cancelled.")
            }
            .confirmationDialog("Delete this chat?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete chat", role: .destructive) {
                    if let id = pendingDelete { message = model.deleteChat(id) }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("This removes the whole chat from this iPhone. It cannot be undone. Saved memories are not deleted. A chat with a waiting or unverified action cannot be deleted until that action is resolved.")
            }
            .alert("Chats", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) { }
            } message: { Text(message ?? "") }
        }
    }

    private func row(_ c: Conversation) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(c.title).font(.body.weight(c.id == model.activeConversationID ? .semibold : .regular)).lineLimit(1)
                HStack(spacing: 8) {
                    Text(c.updated, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                    Text("\(c.messages.count) message\(c.messages.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                }
                if c.hasPendingActions {
                    Label("\(c.pendingActionCount) action\(c.pendingActionCount == 1 ? "" : "s") waiting or unverified", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            if c.id == model.activeConversationID { Image(systemName: "checkmark").foregroundStyle(Theme.accent).accessibilityLabel("Current chat") }
        }
        .frame(minHeight: 44).contentShape(Rectangle())
    }
}
