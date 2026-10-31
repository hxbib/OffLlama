import SwiftUI
import Charts
import PocketCore

/// Live decision feed + the "share of decisions handled in milliseconds" chart, built only from logged telemetry.
struct ReflexView: View {
    @Environment(AppModel.self) private var model
    @State private var exportURL: URL?
    @State private var byRound = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if model.daily.isEmpty {
                        Text("No decisions logged yet. Every Reflex decision you make shows up here.").foregroundStyle(.secondary)
                    } else {
                        Picker("Group by", selection: $byRound) { Text("Per model round").tag(true); Text("Per day").tag(false) }
                            .pickerStyle(.segmented)
                        if byRound { RoundChart(rounds: model.rounds).frame(height: 200).padding(.vertical, 8) }
                        else { ReflexChart(days: model.daily).frame(height: 200).padding(.vertical, 8) }
                        let total = model.daily.reduce(0) { $0 + $1.total }
                        let local = model.daily.reduce(0) { $0 + $1.handledLocally }
                        LabeledContent("Decisions logged", value: "\(total)")
                        LabeledContent("Handled on device", value: total == 0 ? "–" : String(format: "%.0f%%", Double(local) / Double(total) * 100))
                    }
                } header: { Text("Handled on device") } footer: {
                    Text("Real telemetry from this phone only. Each distillation round ships as a new model file, so rounds come straight from logged rows. A decision counts as handled when its confidence clears τ.")
                }
                Section("Live") {
                    ForEach(model.decisions) { DecisionCard(row: $0) }
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

/// On-device share per distillation round (model file), in the order the rounds were installed.
struct RoundChart: View {
    let rounds: [(model: String, total: Int, handledLocally: Int)]
    var body: some View {
        Chart(Array(rounds.enumerated()), id: \.offset) { i, r in
            let share = r.total == 0 ? 0 : Double(r.handledLocally) / Double(r.total)
            BarMark(x: .value("Round", "R\(i)"), y: .value("Share", share))
                .foregroundStyle(Theme.accent.gradient).cornerRadius(6)
                .annotation(position: .top) {
                    VStack(spacing: 0) {
                        Text("\(Int(share * 100))%").font(.caption.weight(.semibold))
                        Text("n=\(r.total)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
        }
        .chartYScale(domain: 0...1.1)
        .chartYAxis { AxisMarks(values: [0, 0.5, 1]) { v in AxisGridLine(); AxisValueLabel { Text("\(Int((v.as(Double.self) ?? 0) * 100))%") } } }
        .chartXAxis { AxisMarks { v in AxisValueLabel() } }
        .accessibilityLabel("On-device share per model round")
    }
}
