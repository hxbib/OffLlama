import SwiftUI

/// Top-of-screen pill: airplane/offline vs online, and the loaded model.
struct StatusPill: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: model.isOnline ? "wifi" : "airplane")
                .symbolEffect(.bounce, value: model.isOnline)
            Text(model.isOnline ? "Online · cloud brain available" : "Offline · fully on device")
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
    var tau: Double = 0.8
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Theme.confidenceColor(value, tau: tau)).frame(width: max(4, g.size.width * value))
                Rectangle().fill(.primary.opacity(0.5)).frame(width: 1).offset(x: g.size.width * tau)
            }
        }
        .frame(height: 6)
    }
}

struct DecisionCell: View {
    let row: DecisionRow
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.type).font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f ms", row.ms)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack {
                Text(row.choice.replacingOccurrences(of: "_", with: " ")).font(.callout.weight(.medium))
                Spacer()
                if row.escalated {
                    Label("escalated", systemImage: "arrow.up.forward.circle").font(.caption2).foregroundStyle(.orange)
                }
                Text(String(format: "%.0f%%", row.confidence * 100)).font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.confidenceColor(row.confidence))
            }
            ConfidenceBar(value: row.confidence)
        }
        .padding(.vertical, 4)
    }
}
