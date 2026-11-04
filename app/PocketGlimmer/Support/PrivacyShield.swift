import SwiftUI
import UIKit

/// Covers every presentation layer (sheets included) while a scene is not active, so the app-switcher snapshot
/// never shows chat, memory, a photo or Settings. A SwiftUI overlay would miss UIKit-presented sheets.
@MainActor
final class PrivacyShield {
    static let shared = PrivacyShield()
    private var windows: [ObjectIdentifier: UIWindow] = [:]
    private var installed = false

    func install() {
        guard !installed else { return }
        installed = true
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: .main) { [weak self] note in
            guard let scene = note.object as? UIWindowScene else { return }
            MainActor.assumeIsolated { self?.cover(scene) }
        }
        nc.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] note in
            guard let scene = note.object as? UIWindowScene else { return }
            MainActor.assumeIsolated { self?.uncover(scene) }
        }
    }

    private func cover(_ scene: UIWindowScene) {
        let id = ObjectIdentifier(scene)
        guard windows[id] == nil else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        let host = UIHostingController(rootView: PrivacyCoverView())
        host.view.backgroundColor = .systemBackground
        window.rootViewController = host
        window.isHidden = false
        windows[id] = window
    }

    private func uncover(_ scene: UIWindowScene) {
        guard let window = windows.removeValue(forKey: ObjectIdentifier(scene)) else { return }
        window.isHidden = true
    }
}

struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(Theme.accent)
                Text("OffLlama").font(.title2.weight(.semibold))
            }
            .accessibilityElement(children: .combine)
        }
    }
}
