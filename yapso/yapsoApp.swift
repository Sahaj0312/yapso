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
        #if DEBUG
        if AppConfig.resetData {
            try? FileManager.default.removeItem(at: Recordings.directory)
            if let container = try? ModelContainer(for: Attempt.self, CoachProfile.self) {
                try? container.mainContext.delete(model: Attempt.self)
                try? container.mainContext.save()
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Fetch the offline speech model early so a practice talk without network isn't stuck waiting on a download.
                .task { await OnDeviceTranscriber.prepareModel() }
        }
        // Syncs via CloudKit automatically once the iCloud capability is enabled; local-only until then.
        .modelContainer(for: [Attempt.self, CoachProfile.self])
    }
}
