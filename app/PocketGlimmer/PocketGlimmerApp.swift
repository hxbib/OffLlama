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
    /// At or above tau: handled on device (accent). Below tau: orange (escalate / ask / confirm).
    /// Default = the shipped calibration.json defaultTau (0.90), so a caller that forgets to pass the row's tau
    /// (e.g. ChatView's LiveReflexStrip) never paints an escalated 0.85 decision as "handled".
    static func confidenceColor(_ c: Double, tau: Double = 0.9) -> Color { c >= tau ? accent : .orange }
}
