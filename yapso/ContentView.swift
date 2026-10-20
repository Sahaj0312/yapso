//
//  ContentView.swift
//  yapso
//
//  Created by Sahajdeep Chhabra on 2026-10-19.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TodayView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Attempt.self, CoachProfile.self], inMemory: true)
}
