import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 0
    private let pages: [(String, String, String)] = [
        ("sparkle", "Your assistant, in your pocket", "A small Meta model runs entirely on this iPhone. Turn on Airplane Mode: it still works."),
        ("bolt.fill", "Reflex decides in milliseconds", "Every choice is one forward pass with a confidence score. When it isn't sure, it says so and asks for help."),
        ("brain", "It remembers, privately", "Facts you share stay in an on-device database. You can see and delete every memory."),
        ("arrow.up.forward.circle", "Hard questions go to a bigger brain", "Only when you're online and it's allowed, with names and numbers masked first."),
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
                if page < pages.count - 1 { withAnimation { page += 1 } }
                else {
                    Task {
                        await model.actions.requestAccess()
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
