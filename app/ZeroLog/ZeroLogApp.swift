import SwiftUI

@main
struct ZeroLogApp: App {
    @State private var model: AppModel

    init() {
        // ORDER IS THE WHOLE POINT. Swift evaluates stored-property
        // initialisers BEFORE the init body, so the previous shape --
        // `@State private var model = AppModel()` -- read settings.json and
        // history.json FIRST and deleted them second. Every UI-test launch
        // after a completed test therefore loaded the previous test's state
        // and opened on Today instead of setup, then the too-late reset
        // wiped the files so the NEXT launch ran clean: a perfect
        // pass/fail/pass alternation that kept the behaviour suite red from
        // the day it was born. The model is now constructed explicitly,
        // after the reset it must come after.
        TestSupport.resetStateIfRequested()
        Style.apply()
        // Opened early so the watch can receive settings even if the user never
        // visits Settings again this launch.
        PhoneSettingsSync.shared.start()
        _model = State(initialValue: AppModel())
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
                LiftProgressView()
                    .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                HistoryView()
                    .tabItem { Label("History", systemImage: "clock") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
        }
    }
}
