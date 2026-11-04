import SwiftUI
import WebKit
import PocketCore

/// The assistant's reply: selectable prose, with fenced HTML/SVG documents shown inline in an isolated web view.
struct ReplyBodyView: View {
    let text: String

    var body: some View {
        let segments = RichReply.segments(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .prose(let prose):
                    Text(prose).textSelection(.enabled)
                        .padding(12)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
                case .markup(let markup):
                    MarkupCard(markup: markup)
                }
            }
        }
    }
}

@MainActor private enum HeightMemory {
    static var byPage: [Int: CGFloat] = [:]
}

private struct MarkupCard: View {
    let markup: EmbeddedMarkup
    @State private var showFull = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            IsolatedMarkupView(markup: markup, maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
            HStack(spacing: 4) {
                Button { showFull = true } label: {
                    Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right").frame(minHeight: 44)
                }
                ShareLink(item: markup.source, preview: SharePreview("OffLlama \(markup.kind.rawValue.uppercased())")) {
                    Label("Share source", systemImage: "square.and.arrow.up").frame(minHeight: 44)
                }
                Spacer(minLength: 0)
            }
            .font(.footnote).padding(.leading, 6)
        }
        .sheet(isPresented: $showFull) {
            NavigationStack {
                IsolatedMarkupView(markup: markup, maxHeight: nil, fill: true)
                    .navigationTitle(markup.kind == .svg ? "SVG" : "HTML").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showFull = false } }
                        ToolbarItem(placement: .topBarLeading) { ShareLink(item: markup.source) }
                    }
            }
        }
    }
}

/// Owns one isolated controller. The page loads once per distinct markup, never on unrelated SwiftUI updates.
private struct IsolatedMarkupView: View {
    let markup: EmbeddedMarkup
    let maxHeight: CGFloat?
    var fill = false
    @State private var controller: IsolatedHTMLController?
    @State private var contentHeight: CGFloat = 0
    @State private var unavailable = false

    private var memoryKey: Int { markup.source.hashValue }

    var body: some View {
        Group {
            if let controller {
                WebViewHost(webView: controller.webView)
                    .accessibilityLabel("Generated \(markup.kind.rawValue.uppercased()) content")
                    .accessibilityHint("Scrolls inside the message")
            } else if unavailable {
                Text("This document could not be shown safely. You can still share its source.")
                    .font(.callout).foregroundStyle(.secondary).padding(12)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: fill ? nil : height)
        .frame(maxHeight: fill ? .infinity : nil)
        .task(id: markup) { await prepare() }
    }

    private var height: CGFloat {
        let measured = contentHeight > 0 ? contentHeight : (HeightMemory.byPage[memoryKey] ?? 160)
        return min(max(measured, 80), maxHeight ?? 360)
    }

    @MainActor private func prepare() async {
        if controller == nil {
            do {
                let c = IsolatedHTMLController(rules: try await IsolatedHTMLController.ruleList())
                c.onContentHeight = { h in contentHeight = h; HeightMemory.byPage[memoryKey] = h }
                controller = c
            } catch { unavailable = true; return }
        }
        controller?.load(page: RichReply.page(for: markup))
    }
}

private struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
