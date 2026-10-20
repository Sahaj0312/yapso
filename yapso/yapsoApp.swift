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
    init() {
        Theme.applyAppearance()
        #if DEBUG
        if AppConfig.resetData || DebugSeed.isRequested,
           let container = try? ModelContainer(for: Attempt.self, CoachProfile.self) {
            if AppConfig.resetData {
                try? FileManager.default.removeItem(at: Recordings.directory)
                try? container.mainContext.delete(model: Attempt.self)
                try? container.mainContext.delete(model: CoachProfile.self)
                try? container.mainContext.save()
            }
            if DebugSeed.isRequested { DebugSeed.seedHistory(in: container.mainContext) }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Fetch the offline speech model early so a practice talk without network isn't stuck waiting on a download.
                .task { await OnDeviceTranscriber.prepareModel() }
                .task { await Task.detached(priority: .background) { Recordings.purgeExpired() }.value }
        }
        // Syncs via CloudKit automatically once the iCloud capability is enabled; local-only until then.
        .modelContainer(for: [Attempt.self, CoachProfile.self])
    }
}
