import AppIntents
import Foundation

let startDictationShortcutKey = "shouldStartDictationFromShortcut"
let lastTranscriptShortcutKey = "lastTranscriptForShortcut"
let lastTranscriptReadyShortcutKey = "lastTranscriptReadyForShortcut"
let returnToShortcutsAfterTranscriptionKey = "returnToShortcutsAfterTranscription"

struct StartDictationIntent: AppIntent {
    static var title: LocalizedStringResource = "Начать диктовку"
    static var description = IntentDescription("Открывает VoiceNotes и сразу запускает диктовку.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.removeObject(forKey: lastTranscriptShortcutKey)
        UserDefaults.standard.set(false, forKey: lastTranscriptReadyShortcutKey)
        UserDefaults.standard.set(true, forKey: startDictationShortcutKey)
        UserDefaults.standard.synchronize()
        return .result()
    }
}

struct GetLastTranscriptIntent: AppIntent {
    static var title: LocalizedStringResource = "Получить последнюю расшифровку"
    static var description = IntentDescription("Возвращает последнюю готовую расшифровку из VoiceNotes.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        for _ in 0..<20 {
            let isReady = UserDefaults.standard.bool(forKey: lastTranscriptReadyShortcutKey)
            let text = UserDefaults.standard.string(forKey: lastTranscriptShortcutKey) ?? ""

            if isReady && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .result(value: text)
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        return .result(value: "")
    }
}

struct VoiceNotesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDictationIntent(),
            phrases: [
                "Начать диктовку в \(.applicationName)",
                "Новая диктовка в \(.applicationName)",
                "Записать заметку в \(.applicationName)"
            ],
            shortTitle: "Начать диктовку",
            systemImageName: "mic"
        )

        AppShortcut(
            intent: GetLastTranscriptIntent(),
            phrases: [
                "Получить последнюю расшифровку из \(.applicationName)",
                "Взять текст из \(.applicationName)"
            ],
            shortTitle: "Получить текст",
            systemImageName: "doc.text"
        )
    }
}
