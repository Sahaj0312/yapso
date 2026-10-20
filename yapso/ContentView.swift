//
//  ContentView.swift
//  yapso
//
//  Created by Sahajdeep Chhabra on 2026-10-19.
//

import SwiftUI
import SwiftData

nonisolated enum AppTab: String, Hashable {
    case today, history, progress
}

struct ContentView: View {
    @State private var router = AppRouter(tab: AppConfig.initialTab)
    @AppStorage(Preferences.hasOnboarded) private var hasOnboarded = false
    @State private var showOnboarding = false

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) { TodayView().tint(.primary) }
            Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) { HistoryView().tint(.primary) }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) { ProgressScreen().tint(.primary) }
        }
        .sensoryFeedback(.selection, trigger: router.tab)
        // Ember for the selected tab; each tab's content sets ink for its own buttons.
        .tint(.ember)
        .environment(router)
        .onAppear { showOnboarding = !hasOnboarded || AppConfig.forceOnboarding }
        .onChange(of: hasOnboarded) { _, done in if !done { showOnboarding = true } }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                hasOnboarded = true
                showOnboarding = false
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Attempt.self, CoachProfile.self], inMemory: true)
}
