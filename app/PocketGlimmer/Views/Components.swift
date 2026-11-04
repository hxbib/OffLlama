import SwiftUI
import UIKit
import PocketCore

/// Top-of-screen pill: airplane/offline vs online, and the loaded model.
struct StatusPill: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: model.isOnline ? "wifi" : "airplane")
                .symbolEffect(.bounce, value: reduceMotion ? false : model.isOnline)
            Text(model.isOnline ? "Online" : "Offline · fully on device")
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(model.isOnline ? Color.secondary.opacity(0.12) : Color.green.opacity(0.18), in: Capsule())
        .foregroundStyle(model.isOnline ? Color.secondary : Color.green)
        .accessibilityLabel(model.isOnline ? "Online" : "Offline, running on device")
    }
}

struct ConfidenceBar: View {
    let value: Double
    var tau: Double = 0.9
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Theme.confidenceColor(value, tau: tau)).frame(width: max(4, g.size.width * value))
                    .animation(.easeOut(duration: 0.25), value: value)
                Rectangle().fill(.primary.opacity(0.45)).frame(width: 1.5, height: 10).offset(x: g.size.width * tau - 0.75)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 6)
        .accessibilityLabel(String(format: "Model certainty %.0f percent. Needs %.0f percent.", value * 100, tau * 100))
    }
}

/// One decision in plain words: what was chosen and how sure the model was of that choice. The number is the model's
/// certainty about its choice, not the chance an action works or a message arrives. Raw ids and scores are under Details.
struct DecisionCard: View {
    let row: DecisionRow
    var startExpanded = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.titleText).font(.caption).foregroundStyle(.secondary)
                            Text(row.choiceText).font(.callout.weight(.medium)).foregroundStyle(.primary)
                        }
                        Spacer()
                        Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.tertiary).rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    Text(row.certaintyText).font(.caption).foregroundStyle(Theme.confidenceColor(row.confidence, tau: row.tau))
                    ConfidenceBar(value: row.confidence, tau: row.tau)
                    if let note = row.topChoiceNote { Text(note).font(.caption2).foregroundStyle(.orange) }
                }
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Details").font(.caption.weight(.semibold))
                    Text("Decision type: \(row.type) · top option: \(row.choice)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                    ForEach(row.probabilities, id: \.id) { p in
                        HStack {
                            Text(p.id).font(.caption.monospaced())
                            Spacer()
                            Text(String(format: "%.3f", p.p)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    Text(String(format: "Bar (τ) %.2f. Time for this decision: %@. One forward pass, letter scores corrected for prior bias.", row.tau, DecisionPresentation.seconds(row.ms)))
                        .font(.caption2).foregroundStyle(.tertiary).padding(.top, 2)
                }
                if let json = row.toolCallJSON {
                    Text(json).font(.caption.monospaced()).textSelection(.enabled)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("Planned action details")
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear { expanded = startExpanded }
    }
}

typealias DecisionCell = DecisionCard

extension UIApplication {
    /// Ends editing in whichever field currently holds the keyboard, SwiftUI-focused or not.
    static func resignKeyboard() {
        shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
