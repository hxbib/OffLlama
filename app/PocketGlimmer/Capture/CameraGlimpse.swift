import PhotosUI
import SwiftUI
import UIKit
import Vision

/// A photo prepared on device before anything can leave: rotation baked into pixels, downscaled to <= 1024 px,
/// re-encoded as JPEG q0.8 (the original HEIC/JPEG and its GPS/EXIF are not carried over), plus on-device OCR text
/// that only feeds the local sensitivity decision. `MultimodalGate` still strips any APP1/APP2 segments before sending.
struct GlimpsePhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    let jpeg: Data
    let originalBytes: Int
    let photoText: String

    static func prepare(_ source: UIImage, originalBytes: Int? = nil, maxSide: CGFloat = 1024, quality: CGFloat = 0.8) async -> GlimpsePhoto? {
        let s = source.size
        guard s.width > 0, s.height > 0 else { return nil }
        let scale = min(1, maxSide / max(s.width, s.height))
        let target = CGSize(width: floor(s.width * scale), height: floor(s.height * scale))
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1; fmt.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: fmt).image { _ in source.draw(in: CGRect(origin: .zero, size: target)) }
        guard let jpeg = resized.jpegData(compressionQuality: quality) else { return nil }
        let text = await recognizeText(resized.cgImage)
        return GlimpsePhoto(image: resized, jpeg: jpeg, originalBytes: originalBytes ?? source.jpegData(compressionQuality: 1)?.count ?? 0, photoText: text)
    }

    /// Apple Vision text recognition, on device. Used for the local sensitivity decision only; never sent.
    static func recognizeText(_ cg: CGImage?) async -> String {
        guard let cg else { return "" }
        return await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let req = VNRecognizeTextRequest()
                req.recognitionLevel = .fast
                req.usesLanguageCorrection = false
                try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
                let lines = req.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
                cont.resume(returning: lines.prefix(40).joined(separator: "\n"))
            }
        }
    }
}

/// Composer camera button: take a photo or pick one, then open the Glimpse sheet.
struct CameraButton: View {
    @Environment(AppModel.self) private var model
    @State private var askSource = false
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showLibrary = false
    @State private var photo: GlimpsePhoto?
    @State private var preparing = false

    var body: some View {
        Button {
            guard model.isOnline else { model.chat.append(.init(role: .system, text: "Voice and camera understanding need the cloud; nothing was sent.")); return }
            askSource = true
        } label: {
            Image(systemName: preparing ? "hourglass.circle" : "camera.circle")
                .font(.system(size: 30))
                .foregroundStyle(model.isOnline ? Theme.accent : Color.secondary)
        }
        .disabled(model.busy || preparing)
        .accessibilityLabel("Camera")
        .confirmationDialog("Glimpse", isPresented: $askSource) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) { Button("Take photo") { showCamera = true } }
            Button("Choose photo") { showLibrary = true }
        } message: { Text("The photo is checked for sensitive content on this iPhone before anything is sent.") }
        .photosPicker(isPresented: $showLibrary, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) {
            guard let item = pickerItem else { return }
            pickerItem = nil
            preparing = true
            Task {
                defer { preparing = false }
                guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
                photo = await GlimpsePhoto.prepare(img, originalBytes: data.count)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(onImage: { img in
                showCamera = false
                preparing = true
                Task { photo = await GlimpsePhoto.prepare(img); preparing = false }
            }, onCancel: { showCamera = false })
            .ignoresSafeArea()
        }
        .sheet(item: $photo) { GlimpseView(photo: $0).environment(model) }
    }
}

/// UIKit camera (SwiftUI has no first-party camera view on iOS 18).
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) } else { parent.onCancel() }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onCancel() }
    }
}
