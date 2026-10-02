//
//  VoiceNotesWhisperApp.swift
//  VoiceNotesWhisper
//
//  Created by Александра Зенина on 26.05.2026.
//

import SwiftUI
import FirebaseCore

@main
struct VoiceNotesWhisperApp: App {

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
