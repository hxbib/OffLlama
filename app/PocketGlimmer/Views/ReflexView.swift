import SwiftUI
import Charts
import PocketCore

/// Live decision feed + the "share of decisions handled in milliseconds" chart, built only from logged telemetry.
struct ReflexView: View {
    @Environment(AppModel.self) private var model
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if model.daily.isEmpty {
                        Text("No decisions logged yet. Every Reflex decision you make shows up here.").foregroundStyle(.secondary)
                    } else {
                        ReflexChart(days: model.daily).frame(height: 200).padding(.vertical, 8)
                        let total = model.daily.reduce(0) { $0 + $1.total }
                        let local = model.daily.reduce(0) { $0 + $1.handledLocally }
                        LabeledContent("Decisions logged", value: "\(total)")
                        LabeledContent("Handled on device", value: total == 0 ? "–" : String(format: "%.0f%%", Double(local) / Double(total) * 100))
                    }
                } header: { Text("Handled by Reflex, per day") } footer: {
                    Text("Real telemetry from this phone. A decision counts as handled when its confidence clears the threshold.")
                }
                Section("Live") {
                    ForEach(model.decisions) { DecisionCell(row: $0) }
                }
            }
            .navigationTitle("Reflex")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let u = exportURL { ShareLink(item: u) { Image(systemName: "square.and.arrow.up") } }
                    else { Button { exportURL = model.exportCSV() } label: { Image(systemName: "tablecells") } }
                }
            }
            .onAppear { model.refresh() }
        }
    }
}

struct ReflexChart: View {
    let days: [DailyReflexShare]
    var body: some View {
        Chart(days, id: \.day) { d in
            AreaMark(x: .value("Day", d.day), y: .value("Share", d.share))
                .foregroundStyle(Theme.accent.opacity(0.15).gradient).interpolationMethod(.monotone)
            LineMark(x: .value("Day", d.day), y: .value("Share", d.share))
                .foregroundStyle(Theme.accent).interpolationMethod(.monotone).lineStyle(.init(lineWidth: 2.5))
            PointMark(x: .value("Day", d.day), y: .value("Share", d.share))
                .foregroundStyle(Theme.accent)
                .annotation(position: .top) { Text("\(d.total)").font(.caption2).foregroundStyle(.secondary) }
        }
        .chartYScale(domain: 0...1)
        .chartYAxis { AxisMarks(values: [0, 0.5, 1]) { v in AxisGridLine(); AxisValueLabel { Text("\(Int((v.as(Double.self) ?? 0) * 100))%") } } }
    }
}
