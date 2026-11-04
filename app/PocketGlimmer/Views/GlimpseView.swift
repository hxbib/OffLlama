import SwiftUI
import UIKit
import PocketCore

/// Camera "glimpse": photo -> sensitivity Reflex card -> (if allowed) Muse Spark 1.3 answer and/or SAM 3.1 boxes +
/// masks, with one line saying exactly what left the phone. Everything goes through `MultimodalGate`.
struct GlimpseView: View {
    let photo: GlimpsePhoto
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable { case ask = "Ask Spark", find = "Find (SAM 3.1)", both = "Both"; var id: String { rawValue } }
    @State private var question = "What is this, and what should I do about it?"
    @State private var concept = ""
    @State private var mode: Mode = .both
    @State private var running = false
    @State private var result: GlimpseResult?
    @State private var overlays: [MaskOverlay] = []
    @State private var error: String?
    @AppStorage("photos_stay_on_device") private var photosStayOnDevice = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Image(uiImage: photo.image).resizable().aspectRatio(contentMode: .fit)
                        .overlay { SegmentOverlay(overlays: overlays) }
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    Text(preparedLine)
                        .font(.caption2).foregroundStyle(.secondary)

                    if result == nil {
                        Picker("Mode", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                        if mode != .find {
                            TextField("Ask about the photo", text: $question, axis: .vertical).lineLimit(1...3).textFieldStyle(.roundedBorder)
                        }
                        if mode != .ask {
                            TextField(mode == .both ? "Object to outline (optional, Spark picks one)" : "Object to outline, e.g. sticky note", text: $concept)
                                .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never)
                        }
                        Toggle("Photos stay on this iPhone", isOn: $photosStayOnDevice).font(.callout)
                        Button { Task { await run() } } label: {
                            Label(running ? "Checking on device…" : "Glimpse", systemImage: "camera.viewfinder").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).disabled(running || (mode == .find && concept.trimmingCharacters(in: .whitespaces).isEmpty))
                    }

                    if let r = result { ResultBlock(result: r, segmentCount: overlays.count) }
                    if let error { Text(error).font(.callout).foregroundStyle(.red) }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Glimpse").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { UIApplication.resignKeyboard() } }
                ToolbarItem(placement: .principal) { StatusPill() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var preparedLine: String {
        let kb = String(format: "%.0f KB → %.0f KB JPEG", Double(photo.originalBytes) / 1024, Double(photo.jpeg.count) / 1024)
        return "Prepared on device: \(kb), \(Int(photo.image.size.width))×\(Int(photo.image.size.height)) px, location data removed"
    }

    private var intent: String {
        switch mode {
        case .ask, .both: return question
        case .find: return "Outline every \(concept) in this photo"
        }
    }

    private func run() async {
        guard let assistant = model.assistant else { error = "The on-device model is still loading."; return }
        guard let key = Keychain.get("meta_key") else { error = "Camera understanding needs a Meta Model API key (Settings). Nothing was sent."; return }
        running = true; defer { running = false }
        let gate = MultimodalGate(assistant: assistant, metaAPIKey: key)
        gate.photosStayOnDevice = photosStayOnDevice
        let c = concept.trimmingCharacters(in: .whitespaces)
        let task: MultimodalGate.ImageTask
        switch mode {
        case .ask: task = .describe(question: question)
        case .find: task = .segment(concept: c)
        case .both: task = .describeAndSegment(question: question, concept: c.isEmpty ? nil : c)
        }
        do {
            await model.refreshScrubberNames()
            let r = try await gate.glimpse(imageJPEG: photo.jpeg, intent: intent, task: task, photoText: photo.photoText)
            result = r
            if case .segmented(let segs, _) = r.outcome { overlays = MaskOverlay.build(segs) }
            record(r)
        } catch {
            self.error = "Glimpse failed: \(error.localizedDescription)"
        }
    }

    /// Mirror the turn into the chat so it shows the same badges, decision cards and privacy sheet as text turns.
    private func record(_ r: GlimpseResult) {
        let rows = r.decisions.map { DecisionRow($0) }
        for row in rows { model.decisions.insert(row, at: 0) }
        model.chat.append(.init(role: .user, text: "Photo: " + intent))
        let sent = r.cloudPayloads.map { "\($0.line)\ntext: \($0.textSent)" }.joined(separator: "\n\n")
        switch r.outcome {
        case .keptOnDevice(let why):
            model.chat.append(.init(role: .assistant, text: why, badge: "on device", decisions: rows, keptOnDevice: true))
        case .offline(let msg):
            model.chat.append(.init(role: .assistant, text: msg, badge: "offline", decisions: rows))
        case .answered(let text):
            model.chat.append(.init(role: .assistant, text: text, badge: prettyProvider(r.provider ?? ""), decisions: rows, cloudPromptSent: sent))
        case .segmented(let segs, let answer):
            let text = (answer.map { $0 + "\n" } ?? "") + "SAM 3.1 outlined \(segs.count) × \(segs.first?.label ?? "object")."
            model.chat.append(.init(role: .assistant, text: text, badge: r.provider ?? "", decisions: rows, cloudPromptSent: sent))
        }
    }
}

private struct ResultBlock: View {
    let result: GlimpseResult
    let segmentCount: Int

    static func samLine(_ segs: [Segment]) -> String {
        guard let first = segs.first else { return "SAM 3.1 found no matches." }
        var line = "SAM 3.1 outlined \(segs.count) × \"\(first.label)\""
        if let best = segs.compactMap(\.confidence).max() { line += String(format: " (best %.0f%%)", best * 100) }
        return line
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(result.decisions.enumerated()), id: \.offset) { _, d in DecisionCard(row: DecisionRow(d), startExpanded: true) }
            switch result.outcome {
            case .keptOnDevice(let why):
                Label("Kept on device · nothing sent", systemImage: "lock.fill").font(.callout.weight(.semibold)).foregroundStyle(Theme.accent)
                Text(why).font(.callout)
            case .offline(let msg):
                Label(msg, systemImage: "airplane").font(.callout)
            case .answered(let text):
                Text(text).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
            case .segmented(let segs, let answer):
                if let answer { Text(answer).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14)) }
                Text(Self.samLine(segs)).font(.callout.weight(.medium))
            }
            if !result.cloudPayloads.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("What left the phone", systemImage: "arrow.up.forward.circle").font(.caption.weight(.semibold))
                    ForEach(Array(result.cloudPayloads.enumerated()), id: \.offset) { _, p in
                        Text(p.line).font(.caption.monospaced())
                        if !p.textSent.isEmpty { Text("text: " + p.textSent).font(.caption2.monospaced()).foregroundStyle(.secondary) }
                    }
                    Text(String(format: "≈ $%.4f · Standard mode (not used to train Meta models)", result.usage.estimatedUSD))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

/// One SAM 3.1 match, ready to draw: normalized box + a tinted mask image aligned to the box.
struct MaskOverlay: Identifiable {
    let id: Int
    let rect: CGRect          // 0...1 fractions of the image
    let mask: UIImage?
    let label: String

    static let palette: [(UInt8, UInt8, UInt8)] = [(92, 107, 255), (255, 149, 0), (52, 199, 89), (255, 45, 85), (175, 82, 222), (90, 200, 250)]

    /// one_bit masks are small (a few KB of pixels each); decoding all of them takes milliseconds on device.
    static func build(_ segs: [Segment]) -> [MaskOverlay] {
        segs.enumerated().map { i, s in
            let n = s.box.normalized
            let c = palette[i % palette.count]
            var img: UIImage?
            if let m = s.mask, let raster = try? m.raster() { img = tint(raster, width: m.width, height: m.height, color: c) }
            let pct = s.confidence.map { String(format: " %.0f%%", $0 * 100) } ?? ""
            return MaskOverlay(id: s.id, rect: CGRect(x: n.x, y: n.y, width: n.w, height: n.h), mask: img, label: "\(s.id)\(pct)")
        }
    }

    /// 0/1 raster -> premultiplied RGBA image, 45% alpha where the mask is set.
    static func tint(_ raster: [UInt8], width: Int, height: Int, color: (UInt8, UInt8, UInt8)) -> UIImage? {
        guard raster.count == width * height else { return nil }
        let a: UInt16 = 115
        let pr = UInt8(UInt16(color.0) * a / 255), pg = UInt8(UInt16(color.1) * a / 255), pb = UInt8(UInt16(color.2) * a / 255)
        var px = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) where raster[i] == 1 {
            px[i * 4] = pr; px[i * 4 + 1] = pg; px[i * 4 + 2] = pb; px[i * 4 + 3] = UInt8(a)
        }
        guard let provider = CGDataProvider(data: Data(px) as CFData),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Draws SAM 3.1 boxes and masks over the fitted photo (the overlay has exactly the image's frame).
struct SegmentOverlay: View {
    let overlays: [MaskOverlay]
    var body: some View {
        Canvas { ctx, size in
            for (i, o) in overlays.enumerated() {
                let r = CGRect(x: o.rect.minX * size.width, y: o.rect.minY * size.height,
                               width: o.rect.width * size.width, height: o.rect.height * size.height)
                let c = MaskOverlay.palette[i % MaskOverlay.palette.count]
                let color = Color(red: Double(c.0) / 255, green: Double(c.1) / 255, blue: Double(c.2) / 255)
                if let m = o.mask { ctx.draw(Image(uiImage: m), in: r) }
                ctx.stroke(Path(roundedRect: r, cornerRadius: 3), with: .color(color), lineWidth: 2)
                ctx.draw(Text(o.label).font(.caption2.weight(.bold)).foregroundColor(color), at: CGPoint(x: r.minX + 4, y: r.minY + 2), anchor: .topLeading)
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel("\(overlays.count) outlined objects")
    }
}
