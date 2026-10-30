import SwiftUI

@main
struct ZeroLogApp: App {
    @State private var model = AppModel()

    init() {
        Style.apply()
        // Opened early so the watch can receive settings even if the user never
        // visits Settings again this launch.
        PhoneSettingsSync.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Color.textPrimary)
                .preferredColorScheme(.dark)
        }
    }
}

/// First launch: gym setup. After that: Today, History, Settings.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.settings == nil {
            OnboardingView()
        } else {
            TabView {
                TodayView()
                    .tabItem { Label("Today", systemImage: "figure.strengthtraining.traditional") }
                HistoryView()
                    .tabItem { Label("History", systemImage: "clock") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
        }
    }
}
