import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let pages: [(String, String, String)] = [
        ("airplane", "Your assistant, in your pocket", "A small Meta model runs entirely on this iPhone. Turn on Airplane Mode: it still works."),
        ("bolt.fill", "Reflex decides in milliseconds", "Every choice comes with a confidence score. When it isn't sure, it asks."),
        ("brain", "It remembers, privately", "Facts you share stay on this phone. You can see and delete every one."),
        ("arrow.up.forward.circle", "Hard questions go to a bigger brain", "Only when you're online and allow it, with names and numbers masked first."),
    ]
    var body: some View {
        VStack(spacing: 28) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    VStack(spacing: 18) {
                        Image(systemName: pages[i].0).font(.system(size: 56, weight: .light)).foregroundStyle(Theme.accent)
                        Text(pages[i].1).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                        Text(pages[i].2).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
                    }.tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            Button {
                if page < pages.count - 1 { withAnimation(reduceMotion ? nil : .default) { page += 1 } }
                else {
                    Task {
                        await model.actions.requestAccess()
                        await model.refreshScrubberNames()
                        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                        model.onboarded = true
                    }
                }
            } label: {
                Text(page < pages.count - 1 ? "Continue" : "Allow access & start").frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).padding(.horizontal, 24)
            Text(model.modelState).font(.caption).foregroundStyle(.tertiary).padding(.bottom, 8)
        }
        .padding(.top, 40)
    }
}
