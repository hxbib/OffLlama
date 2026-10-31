import SwiftUI
import UserNotifications

@main
struct PocketGlimmerApp: App {
    @State private var model = AppModel.shared
    var body: some Scene {
        WindowGroup {
            Group {
                if model.onboarded { RootView() } else { OnboardingView() }
            }
            .environment(model)
            .tint(Theme.accent)
            .task { await model.boot() }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            ChatView().tabItem { Label("Assistant", systemImage: "sparkle") }
            ReflexView().tabItem { Label("Reflex", systemImage: "bolt.fill") }
            MemoryView().tabItem { Label("Memory", systemImage: "brain") }
            SettingsView().tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.36, green: 0.42, blue: 1.0)
    static func confidenceColor(_ c: Double, tau: Double = 0.8) -> Color { c >= tau ? .green : (c >= tau - 0.2 ? .orange : .red) }
}
