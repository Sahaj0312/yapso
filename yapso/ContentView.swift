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
    @State private var tab = AppConfig.initialTab
    @AppStorage(Preferences.hasOnboarded) private var hasOnboarded = false
    @State private var showOnboarding = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) { TodayView() }
            Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) { HistoryView() }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) { ProgressScreen() }
        }
        .sensoryFeedback(.selection, trigger: tab)
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
