//
//  yapsoApp.swift
//  yapso
//
//  Created by Sahajdeep Chhabra on 2026-10-19.
//

import SwiftUI
import SwiftData

@main
struct yapsoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Syncs via CloudKit automatically once the iCloud capability is enabled; local-only until then.
        .modelContainer(for: [Attempt.self, CoachProfile.self])
    }
}
