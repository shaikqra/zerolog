import SwiftUI

@main
struct ZeroLogApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(.plate)
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
