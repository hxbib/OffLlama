import SwiftUI
import Charts
import UIKit
import PocketCore

/// Live decision feed + the "share of decisions handled in milliseconds" chart, built only from logged telemetry.
struct ReflexView: View {
    @Environment(AppModel.self) private var model
    @State private var export: TelemetryExport?
    @State private var exportFailed = false
    @State private var byRound = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if model.daily.isEmpty {
                        ContentUnavailableView("No decisions yet", systemImage: "bolt",
                                               description: Text("Ask OffLlama to do something and its decisions appear here."))
                    } else {
                        Picker("Group by", selection: $byRound) { Text("By round").tag(true); Text("By day").tag(false) }
                            .pickerStyle(.segmented)
                        if byRound { RoundChart(rounds: model.rounds).frame(height: 200).padding(.vertical, 8) }
                        else { ReflexChart(days: model.daily).frame(height: 200).padding(.vertical, 8) }
                        let total = model.daily.reduce(0) { $0 + $1.total }
                        let local = model.daily.reduce(0) { $0 + $1.handledLocally }
                        LabeledContent("Decisions logged", value: "\(total)")
                        LabeledContent("Handled on device", value: total == 0 ? "–" : String(format: "%.0f%%", Double(local) / Double(total) * 100))
                        DisclosureGroup("Details") {
                            Text("Telemetry from this phone only. Each round is a new model file. A decision is handled on device when the model's certainty reaches the bar (τ). Certainty is not the chance an action succeeds.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                if !model.decisions.isEmpty {
                    Section("Latest") {
                        ForEach(model.decisions) { DecisionCard(row: $0) }
                    }
                }
            }
            .navigationTitle("Reflex")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let url = model.exportCSV() { export = TelemetryExport(url: url) }
                        else { exportFailed = true }
                    } label: { Label("Export latest CSV", systemImage: "square.and.arrow.up") }
                }
            }
            .onAppear { model.refresh() }
            .sheet(item: $export) { CSVShareSheet(url: $0.url) }
            .alert("Couldn’t export decisions", isPresented: $exportFailed) {
                Button("OK", role: .cancel) { }
            } message: { Text("The CSV could not be written. Please try again.") }
        }
    }
}

private struct TelemetryExport: Identifiable {
    let id = UUID()
    let url: URL
}

private struct CSVShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
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
