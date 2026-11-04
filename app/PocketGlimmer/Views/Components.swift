import SwiftUI

/// Top-of-screen pill: airplane/offline vs online, and the loaded model.
struct StatusPill: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: model.isOnline ? "wifi" : "airplane")
                .symbolEffect(.bounce, value: model.isOnline)
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
        .accessibilityLabel(String(format: "Confidence %.0f percent, threshold %.0f", value * 100, tau * 100))
    }
}

/// The decision object: type -> choice, confidence vs tau, latency; expands to the full distribution + tool-call JSON.
struct DecisionCard: View {
    let row: DecisionRow
    var startExpanded = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(row.type).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                        Text(row.choice.replacingOccurrences(of: "_", with: " ")).font(.callout.weight(.medium)).foregroundStyle(.primary)
                        Spacer()
                        if row.escalated {
                            Label("below τ", systemImage: "arrow.up.forward.circle").labelStyle(.titleAndIcon)
                                .font(.caption2.weight(.medium)).foregroundStyle(.orange)
                        }
                        Text(String(format: "%.0f%%", row.confidence * 100)).font(.callout.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Theme.confidenceColor(row.confidence, tau: row.tau))
                        Text(String(format: "%.0f ms", row.ms)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.tertiary).rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    ConfidenceBar(value: row.confidence, tau: row.tau)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(row.probabilities, id: \.id) { p in
                        HStack {
                            Text(p.id.replacingOccurrences(of: "_", with: " ")).font(.caption)
                            Spacer()
                            Text(String(format: "%.3f", p.p)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    Text(String(format: "τ = %.2f · one forward pass · letter logits → prior-corrected softmax", row.tau))
                        .font(.caption2).foregroundStyle(.tertiary).padding(.top, 2)
                }
                if let json = row.toolCallJSON {
                    Text(json).font(.caption.monospaced()).textSelection(.enabled)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("Tool call JSON")
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear { expanded = startExpanded }
    }
}

typealias DecisionCell = DecisionCard
