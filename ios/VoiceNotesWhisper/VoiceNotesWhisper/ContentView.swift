import SwiftUI
import AVFoundation
import Combine
import WhisperKit
import Speech
import UIKit
import AudioToolbox
private let firstLaunchTipsSeenKey = "firstLaunchTipsSeen"
private let whisperModelPreparedOnceKey = "whisperModelPreparedOnce"

private func logAudioSessionState(_ place: String) {
    let session = AVAudioSession.sharedInstance()

    print("")
    print("========== AUDIO SESSION: \(place) ==========")
    print("[AUDIO] category=\(session.category.rawValue)")
    print("[AUDIO] mode=\(session.mode.rawValue)")
    print("[AUDIO] isOtherAudioPlaying=\(session.isOtherAudioPlaying)")
    print("[AUDIO] sampleRate=\(session.sampleRate)")
    print("[AUDIO] inputChannels=\(session.inputNumberOfChannels)")
    print("[AUDIO] outputVolume=\(session.outputVolume)")
    print("[AUDIO] currentRoute=\(session.currentRoute)")
    print("========== END AUDIO SESSION ==========")
    print("")
}

private func playRecordingStartSound() {
    logAudioSessionState("BEFORE START SOUND 1113")

    print("[SOUND] play start sound 1113")
    AudioServicesPlaySystemSound(1113)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        logAudioSessionState("AFTER START SOUND 1113")
    }
}

private func playRecordingStopSound() {
    logAudioSessionState("BEFORE STOP SOUND 1114")

    print("[SOUND] play stop sound 1114")
    AudioServicesPlaySystemSound(1114)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        logAudioSessionState("AFTER STOP SOUND 1114")
    }
}

private func restorePlaybackAudioSessionAfterDictation() {
    do {
        let session = AVAudioSession.sharedInstance()

        logAudioSessionState("BEFORE RESTORE PLAYBACK AFTER DICTATION")

        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)

        print("[SOUND] audio session restored to playback after dictation")

        logAudioSessionState("AFTER RESTORE PLAYBACK AFTER DICTATION")
    } catch {
        print("[SOUND] failed to restore playback audio session: \(error.localizedDescription)")
        print("[SOUND] failed to restore playback audio session debug: \(String(reflecting: error))")
        logAudioSessionState("RESTORE PLAYBACK FAILED")
    }
}

struct ContentView: View {
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var liveRecognizer = LiveSpeechRecognizer()
    @StateObject private var transcriber = WhisperTranscriber()

    @State private var isShareSheetPresented = false
    @State private var welcomeAlertStep = 0
    @State private var topStatusText = "Готово"
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {

                Text(topStatusText)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()

                    Button {
                        transcriber.transcript = ""
                        transcriber.prefixTextForNextTranscription = ""
                        topStatusText = "Готово"

                        UserDefaults.standard.removeObject(forKey: lastTranscriptShortcutKey)
                        UserDefaults.standard.set(false, forKey: lastTranscriptReadyShortcutKey)
                        UserDefaults.standard.synchronize()
                    } label: {
                        TrashIcon()
                            .stroke(.tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                            .frame(width: 24, height: 24)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .opacity(
                                recorder.isRecording ||
                                transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? 0.35
                                : 1
                            )
                    }
                    .accessibilityLabel("Очистить")
                    .disabled(
                        recorder.isRecording ||
                        transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
                .padding(.horizontal, 15)

                AutoScrollingTextView(
                    text: Binding(
                        get: {
                            if recorder.isRecording {
                                return displayedRecordingText()
                            } else {
                                return transcriber.transcript
                            }
                        },
                        set: { newValue in
                            if recorder.isRecording {
                                liveRecognizer.liveText = newValue
                            } else {
                                transcriber.transcript = newValue
                            }
                        }
                    ),
                    shouldScrollToBottom: recorder.isRecording || transcriber.isTranscribing
                )
                .frame(minHeight: 360)
                .padding(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.gray.opacity(0.35))
                )

                HStack {
                    Button {
                        UIPasteboard.general.string = transcriber.transcript
                    } label: {
                        CopyIcon()
                            .stroke(.tint, lineWidth: 1.5)
                            .frame(width: 24, height: 24)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .opacity(transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
                    }
                    .accessibilityLabel("Скопировать")
                    .disabled(transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()
                    
                    if recorder.isRecording {
                        Button {
                            let liveText = liveRecognizer.liveText
                                .trimmingCharacters(in: .whitespacesAndNewlines)

                            // Keep live text visible while Whisper is working.
                            // Оставляем live-текст на экране, пока работает Whisper.
                            transcriber.transcript = combinedTranscript(
                                prefix: transcriber.prefixTextForNextTranscription,
                                current: liveText
                            )
                            transcriber.statusText = "Проверяю текст через Whisper..."
                            print("[STATUS] Проверяю текст через Whisper...")

                            topStatusText = "Запись остановлена, расшифровываю и ставлю знаки"

                            liveRecognizer.stopLiveRecognition()
                            playRecordingStopSound()
                            recorder.stopRecording()

                            if let url = recorder.lastRecordingURL {
                                Task {
                                    await transcriber.transcribe(url: url, liveText: liveText)

                                    if transcriber.transcript == "*тишина*" {
                                        topStatusText = "Тишина"
                                    } else if transcriber.statusText.contains("ошибка") || transcriber.statusText.contains("Не удалось") {
                                        topStatusText = transcriber.statusText
                                    } else {
                                        topStatusText = "Готово"
                                    }
                                }
                            }
                        } label: {
                            RecordCircleButton(isRecording: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            playRecordingStartSound()
                            startDictation(fromShortcut: false)
                        } label: {
                            RecordCircleButton(isRecording: false)
                        }
                        .buttonStyle(.plain)
                        .disabled(transcriber.isTranscribing || !transcriber.isModelReady)
                        .opacity(transcriber.isTranscribing || !transcriber.isModelReady ? 0.45 : 1)
                    }

                    Spacer()

                    Button {
                        isShareSheetPresented = true
                    } label: {
                        ShareArrowIcon()
                            .stroke(.tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                            .frame(width: 24, height: 24)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .opacity(transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
                    }
                    .accessibilityLabel("Поделиться")
                    .disabled(transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                
                .padding(.horizontal, 15)

                Spacer()
            }
            .padding()
            .sheet(isPresented: $isShareSheetPresented) {
                ShareSheet(items: [transcriber.transcript])
            }
            .alert(welcomeAlertTitle, isPresented: Binding(
                get: { welcomeAlertStep != 0 },
                set: { isPresented in
                    if !isPresented {
                        welcomeAlertStep = 0
                    }
                }
            )) {
                Button(welcomeAlertStep == 1 ? "Далее" : "Понятно") {
                    if welcomeAlertStep == 1 {
                        welcomeAlertStep = 0

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            welcomeAlertStep = 2
                        }
                    } else {
                        welcomeAlertStep = 0
                    }
                }
            } message: {
                Text(welcomeAlertMessage)
            }
            .onAppear {
                startDictationIfRequestedFromShortcut()
                showFirstLaunchTipsIfNeeded()
                transcriber.preloadModelInBackground { status in
                    if !recorder.isRecording && !transcriber.isTranscribing {
                        topStatusText = status
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    startDictationIfRequestedFromShortcut()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                startDictationIfRequestedFromShortcut()
            }
        }
    }

    private func startDictation(fromShortcut: Bool) {
        guard !recorder.isRecording, !transcriber.isTranscribing else { return }

        if fromShortcut {
            transcriber.prefixTextForNextTranscription = ""
            transcriber.transcript = ""
        } else {
            transcriber.prefixTextForNextTranscription = transcriber.transcript
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        transcriber.statusText = "Готово к расшифровке"
        topStatusText = "Запись идёт..."
        liveRecognizer.liveText = ""

        UserDefaults.standard.removeObject(forKey: lastTranscriptShortcutKey)
        UserDefaults.standard.set(false, forKey: lastTranscriptReadyShortcutKey)
        UserDefaults.standard.set(fromShortcut, forKey: returnToShortcutsAfterTranscriptionKey)
        UserDefaults.standard.synchronize()

        recorder.startRecording()

        Task {
            await liveRecognizer.startLiveRecognition()
        }
    }

    private func startDictationIfRequestedFromShortcut() {
        guard UserDefaults.standard.bool(forKey: startDictationShortcutKey) else {
            return
        }

        UserDefaults.standard.set(false, forKey: startDictationShortcutKey)
        UserDefaults.standard.synchronize()

        startDictation(fromShortcut: true)
    }
    
    private var welcomeAlertTitle: String {
        switch welcomeAlertStep {
        case 1:
            return "Добро пожаловать в Аб!"
        case 2:
            return "Новый абзац"
        default:
            return ""
        }
    }

    private var welcomeAlertMessage: String {
        switch welcomeAlertStep {
        case 1:
            return "Нажмите иконку «Микрофон» и диктуйте, текст появится сразу. Нажмите иконку «Стоп», и приложение расшифрует аудио с пунктуацией."
        case 2:
            return "Скажите «Новый абзац» во время диктовки, чтобы перейти на новый абзац."
        default:
            return ""
        }
    }

    private func showFirstLaunchTipsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: firstLaunchTipsSeenKey) else {
            return
        }

        // Do not show first-launch tips while dictation is auto-started from Shortcuts.
        // Не показываем подсказки, если запись уже запущена из Команд.
        guard !recorder.isRecording else {
            return
        }

        UserDefaults.standard.set(true, forKey: firstLaunchTipsSeenKey)
        UserDefaults.standard.synchronize()

        welcomeAlertStep = 1
    }
    
    private func displayedRecordingText() -> String {
        let combinedText = combinedTranscript(
            prefix: transcriber.prefixTextForNextTranscription,
            current: liveRecognizer.liveText
        )

        let liveTextEndsWithParagraphBreak = liveRecognizer.liveText.range(
            of: #"\n\s*$"#,
            options: [.regularExpression]
        ) != nil

        guard liveTextEndsWithParagraphBreak else {
            return combinedText
        }

        return combinedText.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n▌"
    }

    private func combinedTranscript(prefix: String, current: String) -> String {
        let cleanPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)

        if !cleanPrefix.isEmpty && !cleanCurrent.isEmpty {
            return "\(cleanPrefix)\n\n\(cleanCurrent)"
        }

        if !cleanPrefix.isEmpty {
            return cleanPrefix
        }

        return cleanCurrent
    }
}

final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var statusText = "Готово"
    @Published var lastRecordingURL: URL?

    private var audioRecorder: AVAudioRecorder?

    func startRecording() {
        Task {
            let granted = await requestMicrophonePermission()

            await MainActor.run {
                guard granted else {
                    self.statusText = "Нет доступа к микрофону"
                    return
                }

                self.startRecordingOnMainThread()
            }
        }
    }

private func startRecordingOnMainThread() {
    do {
        print("")
        print("========== RECORDER START ==========")

        let session = AVAudioSession.sharedInstance()

        logAudioSessionState("RECORDER BEFORE SET PLAY AND RECORD")

        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        logAudioSessionState("RECORDER AFTER SET PLAY AND RECORD")

        let url = makeRecordingURL()

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        print("[RECORDER] creating AVAudioRecorder")
        print("[RECORDER] url=\(url.path)")

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self

        print("[RECORDER] calling recorder.record()")

        let didStart = recorder.record()

        print("[RECORDER] recorder.record() returned=\(didStart)")

        guard didStart else {
            self.statusText = "Не удалось начать запись"
            print("[RECORDER] record returned false")
            print("========== END RECORDER START FAILED ==========")
            print("")
            return
        }

        self.audioRecorder = recorder
        self.lastRecordingURL = url
        self.isRecording = true
        self.statusText = "Запись идёт..."

        logAudioSessionState("RECORDER AFTER RECORD STARTED")

        print("========== END RECORDER START ==========")
        print("")
    } catch {
        self.statusText = "Ошибка записи: \(error.localizedDescription)"
        print("[RECORDER] start failed: \(error.localizedDescription)")
        print("[RECORDER] start failed debug: \(String(reflecting: error))")
        logAudioSessionState("RECORDER START FAILED")
        print("========== END RECORDER START FAILED ==========")
        print("")
    }
}

func stopRecording() {
    print("")
    print("========== RECORDER STOP ==========")

    logAudioSessionState("RECORDER BEFORE STOP")

    audioRecorder?.stop()
    audioRecorder = nil
    isRecording = false
    statusText = "Запись остановлена"

    logAudioSessionState("RECORDER AFTER STOP")

    print("========== END RECORDER STOP ==========")
    print("")
}

    private func makeRecordingURL() -> URL {
        let fileName = "recording-\(Int(Date().timeIntervalSince1970)).m4a"
        return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

@MainActor
final class LiveSpeechRecognizer: ObservableObject {
    @Published var liveText = ""
    @Published var statusText = "Live-распознавание готово"

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let audioEngine = AVAudioEngine()

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func startLiveRecognition() async {
        let authorized = await requestSpeechAuthorization()

        guard authorized else {
            statusText = "Нет доступа к распознаванию речи"
            return
        }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            statusText = "Live-распознавание недоступно"
            return
        }

        do {
            stopLiveRecognition()

            liveText = ""
            statusText = "Live: слушаю..."

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true

            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let result {
                        self?.liveText = result.bestTranscription.formattedString
                        self?.statusText = result.isFinal ? "Live: финальный черновик" : "Live: распознаю..."
                    }

                    if error != nil {
                        self?.stopLiveRecognition()
                    }
                }
            }
        } catch {
            statusText = "Ошибка live-распознавания: \(error.localizedDescription)"
            stopLiveRecognition()
        }
    }

    func stopLiveRecognition() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

@MainActor
final class WhisperTranscriber: ObservableObject {
    @Published var transcript = ""
    @Published var statusText = "Готово к расшифровке"
    @Published var isTranscribing = false
    @Published var isModelReady = false

    private var whisperKit: WhisperKit?
    private var isPreloadingModel = false
    var prefixTextForNextTranscription = ""

    init() {
        // If the model was prepared before, allow recording immediately on later launches.
        // Если модель уже готовилась раньше, при следующих запусках сразу разрешаем запись.
        isModelReady = UserDefaults.standard.bool(forKey: whisperModelPreparedOnceKey)
    }
        
    func preloadModelInBackground(onStatus: ((String) -> Void)? = nil) {
        guard whisperKit == nil, !isPreloadingModel else {
            return
        }

        isPreloadingModel = true

        Task { @MainActor in
            do {
                let wasPreparedBefore = UserDefaults.standard.bool(forKey: whisperModelPreparedOnceKey)

                if !wasPreparedBefore {
                    statusText = "Подождите, пока загрузится модель, это нужно один раз и займет пару минут."
                    onStatus?(statusText)
                    print("[STATUS] \(statusText)")
                }

                let config = WhisperKitConfig(model: "openai_whisper-medium")
                whisperKit = try await WhisperKit(config)
                isModelReady = true
                UserDefaults.standard.set(true, forKey: whisperModelPreparedOnceKey)

                if !isTranscribing {
                    statusText = "Готово к расшифровке"
                    onStatus?("Готово")
                    print("[STATUS] \(statusText)")
                }
            } catch {
                if !isTranscribing {
                    statusText = "Не удалось загрузить модель. Проверьте интернет и перезапустите приложение."
                    onStatus?(statusText)
                    print("[STATUS] \(statusText)")
                }
            }

            isPreloadingModel = false
        }
    }

    private func loadWhisperKitIfNeeded() async throws -> WhisperKit {
        if let whisperKit {
            return whisperKit
        }

        while isPreloadingModel {
            try await Task.sleep(nanoseconds: 200_000_000)

            if let whisperKit {
                return whisperKit
            }
        }

        let config = WhisperKitConfig(model: "openai_whisper-medium")
        let loadedWhisperKit = try await WhisperKit(config)
        whisperKit = loadedWhisperKit
        isModelReady = true

        return loadedWhisperKit
    }

    func transcribe(url: URL, liveText: String) async {
        isTranscribing = true
        statusText = "Загружаю модель Whisper..."
        print("[STATUS] Загружаю модель Whisper...")

        do {
            let whisperKit = try await loadWhisperKitIfNeeded()

            statusText = "Финально расшифровываю..."
            print("[STATUS] Финально расшифровываю...")

            let options = DecodingOptions(
                task: .transcribe,
                language: "ru",
                temperature: 0,
                temperatureFallbackCount: 0,
                usePrefillPrompt: true,
                detectLanguage: false
            )

            let results = try await whisperKit.transcribe(
                audioPath: url.path,
                decodeOptions: options
            )

            let rawText = results
                .map { $0.text }
                .joined(separator: " ")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            let cleanedWhisperText = cleanupTranscriptCommandsOnly(rawText)
            let cleanedLiveText = cleanupTranscriptCommandsOnly(liveText)

            if cleanedLiveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // If Apple live recognition heard nothing, ignore Whisper output completely.
                // Если Apple live-распознавание не услышало ничего, полностью игнорируем вывод Whisper.
                transcript = "*тишина*"
                statusText = "Тишина"
            } else if cleanedWhisperText.isEmpty {
                transcript = cleanedLiveText
                statusText = "Оставлен live-текст"
            } else {
                let trimmedWhisperText = trimWhisperTextToLiveWords(
                    whisperText: cleanedWhisperText,
                    liveText: cleanedLiveText
                )

                transcript = trimmedWhisperText
                statusText = trimmedWhisperText == cleanedWhisperText
                    ? "Готово"
                    : "Готово: лишний хвост Whisper удалён"

                print("[STATUS] \(statusText)")
            }
        } catch {
            let cleanedLiveFallback = cleanupTranscriptCommandsOnly(liveText)

            if cleanedLiveFallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                transcript = "*тишина*"
                statusText = "Тишина"
            } else {
                transcript = cleanedLiveFallback
                statusText = "Оставлен live-текст: ошибка Whisper"
                print("[STATUS] \(statusText)")
            }
        }

        let prefix = prefixTextForNextTranscription
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let current = transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !prefix.isEmpty && !current.isEmpty {
            transcript = "\(prefix)\n\n\(current)"
        } else if !current.isEmpty {
            transcript = current
        }

        prefixTextForNextTranscription = ""

        // Delete temporary audio after transcription attempt.
        // Удаляем временное аудио после попытки расшифровки.
        try? FileManager.default.removeItem(at: url)

        UserDefaults.standard.set(transcript, forKey: lastTranscriptShortcutKey)
        UserDefaults.standard.set(true, forKey: lastTranscriptReadyShortcutKey)
        UserDefaults.standard.synchronize()

        let shouldReturnToShortcuts = UserDefaults.standard.bool(forKey: returnToShortcutsAfterTranscriptionKey)

        isTranscribing = false

        restorePlaybackAudioSessionAfterDictation()

        if shouldReturnToShortcuts {
            UserDefaults.standard.set(false, forKey: returnToShortcutsAfterTranscriptionKey)
            UserDefaults.standard.synchronize()

            // Clear app screen after saving text for Shortcuts.
            // Очищаем экран приложения после сохранения текста для Команд.
            transcript = ""
            statusText = "Готово к расшифровке"

            returnToShortcutsApp()
        }
    }
    
    private func returnToShortcutsApp() {
        guard let url = URL(string: "shortcuts://") else {
            return
        }

        UIApplication.shared.open(url)
    }
    
    private struct RecognizedWord {
        let normalized: String
        let endIndex: String.Index
    }

    private func trimWhisperTextToLiveWords(whisperText: String, liveText: String) -> String {
        let whisperWords = recognizedWords(in: whisperText)
        let liveWords = recognizedWords(in: liveText).map { $0.normalized }

        guard whisperWords.count >= 4, liveWords.count >= 4 else {
            return whisperText
        }

        // First try: compare the ending of Apple live text with Whisper text.
        // Первая попытка: сравниваем конец live-текста Apple с текстом Whisper.
        //
        // This catches the normal case where Whisper only added a tail after the real ending.
        // Это ловит обычный случай, когда Whisper просто добавил хвост после настоящего конца.
        let maxSuffixLength = min(14, liveWords.count)
        let minSuffixLength = min(2, maxSuffixLength)

        for suffixLength in stride(from: maxSuffixLength, through: minSuffixLength, by: -1) {
            let liveSuffix = Array(liveWords.suffix(suffixLength))

            guard let lastMatchedWhisperWord = findBestMatchingSuffix(
                liveSuffix,
                in: whisperWords
            ) else {
                continue
            }

            let endIndex = endIndexIncludingTrailingPunctuation(
                in: whisperText,
                after: lastMatchedWhisperWord.endIndex
            )

            let trimmed = String(whisperText[..<endIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.count < whisperText.trimmingCharacters(in: .whitespacesAndNewlines).count {
                print("[TRIM] Cutting Whisper tail by ending match")
                return cleanupTranscriptCommandsOnly(trimmed)
            }

            return whisperText
        }

        // Second try: if exact ending did not match, compare Apple and Whisper by word order.
        // Вторая попытка: если точный конец не совпал, сравниваем Apple и Whisper по порядку слов.
        //
        // Apple live text is treated as the real speech boundary.
        // Live-текст Apple считаем границей реальной речи.
        //
        // If Whisper added even one extra word after the last reliable common boundary, cut it.
        // Если Whisper добавил хотя бы одно лишнее слово после последней надёжной общей границы, режем.
        if let boundary = findLastAlignedBoundary(
            liveWords: liveWords,
            whisperWords: whisperWords
        ) {
            let extraWhisperWords = whisperWords.count - boundary.whisperIndex - 1

            guard extraWhisperWords >= 1 else {
                return whisperText
            }

            print("[TRIM] Cutting Whisper tail by aligned boundary: extraWords=\(extraWhisperWords)")

            let endIndex = endIndexIncludingTrailingPunctuation(
                in: whisperText,
                after: boundary.word.endIndex
            )

            let trimmed = String(whisperText[..<endIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.count < whisperText.trimmingCharacters(in: .whitespacesAndNewlines).count {
                return cleanupTranscriptCommandsOnly(trimmed)
            }
        }

        return whisperText
    }
    
    private func findLastAlignedBoundary(
        liveWords: [String],
        whisperWords: [RecognizedWord]
    ) -> (word: RecognizedWord, whisperIndex: Int)? {
        guard !liveWords.isEmpty, !whisperWords.isEmpty else {
            return nil
        }

        let liveCount = liveWords.count
        let whisperCount = whisperWords.count

        // Longest common subsequence by normalized words.
        // Самая длинная общая подпоследовательность по нормализованным словам.
        var dp = Array(
            repeating: Array(repeating: 0, count: whisperCount + 1),
            count: liveCount + 1
        )

        for liveIndex in 1...liveCount {
            for whisperIndex in 1...whisperCount {
                if liveWords[liveIndex - 1] == whisperWords[whisperIndex - 1].normalized {
                    dp[liveIndex][whisperIndex] = dp[liveIndex - 1][whisperIndex - 1] + 1
                } else {
                    dp[liveIndex][whisperIndex] = max(
                        dp[liveIndex - 1][whisperIndex],
                        dp[liveIndex][whisperIndex - 1]
                    )
                }
            }
        }

        let matchedCount = dp[liveCount][whisperCount]

        // Do not trust the boundary if Apple and Whisper barely overlap.
        // Не доверяем границе, если Apple и Whisper почти не совпали.
        let requiredMatches = max(
            4,
            Int(ceil(Double(liveCount) * 0.55))
        )

        guard matchedCount >= requiredMatches else {
            print("[TRIM] Not enough Apple/Whisper overlap: matched=\(matchedCount), live=\(liveCount), whisper=\(whisperCount)")
            return nil
        }

        var liveIndex = liveCount
        var whisperIndex = whisperCount

        var lastMatchedLiveIndex: Int?
        var lastMatchedWhisperIndex: Int?

        while liveIndex > 0, whisperIndex > 0 {
            if liveWords[liveIndex - 1] == whisperWords[whisperIndex - 1].normalized {
                if lastMatchedLiveIndex == nil {
                    lastMatchedLiveIndex = liveIndex - 1
                    lastMatchedWhisperIndex = whisperIndex - 1
                }

                liveIndex -= 1
                whisperIndex -= 1
            } else if dp[liveIndex - 1][whisperIndex] >= dp[liveIndex][whisperIndex - 1] {
                liveIndex -= 1
            } else {
                whisperIndex -= 1
            }
        }

        guard
            let lastMatchedLiveIndex,
            let lastMatchedWhisperIndex
        else {
            return nil
        }

        // The boundary must be close to the end of Apple live text.
        // Граница должна быть близко к концу live-текста Apple.
        let unmatchedLiveTail = liveCount - lastMatchedLiveIndex - 1

        guard unmatchedLiveTail <= 3 else {
            print("[TRIM] Last common word is too far from Apple ending: unmatchedLiveTail=\(unmatchedLiveTail)")
            return nil
        }

        print(
            "[TRIM] Apple/Whisper boundary found: matched=\(matchedCount), live=\(liveCount), whisper=\(whisperCount), whisperBoundary=\(lastMatchedWhisperIndex)"
        )

        return (
            word: whisperWords[lastMatchedWhisperIndex],
            whisperIndex: lastMatchedWhisperIndex
        )
    }
    
    private func findLastMatchingSuffix(
        _ suffix: [String],
        in whisperWords: [RecognizedWord]
    ) -> RecognizedWord? {
        guard !suffix.isEmpty, whisperWords.count >= suffix.count else {
            return nil
        }

        let lastStartIndex = whisperWords.count - suffix.count

        for startIndex in stride(from: lastStartIndex, through: 0, by: -1) {
            var isMatch = true

            for offset in 0..<suffix.count {
                if whisperWords[startIndex + offset].normalized != suffix[offset] {
                    isMatch = false
                    break
                }
            }

            if isMatch {
                return whisperWords[startIndex + suffix.count - 1]
            }
        }

        return nil
    }

    private func findBestMatchingSuffix(
        _ suffix: [String],
        in whisperWords: [RecognizedWord]
    ) -> RecognizedWord? {
        guard !suffix.isEmpty, whisperWords.count >= suffix.count else {
            return nil
        }

        let lastStartIndex = whisperWords.count - suffix.count

        // Allow small differences between Apple live recognition and Whisper.
        // Допускаем небольшие отличия между live-распознаванием Apple и Whisper.
        let requiredMatches = max(
            3,
            Int(ceil(Double(suffix.count) * 0.75))
        )

        for startIndex in stride(from: lastStartIndex, through: 0, by: -1) {
            var matches = 0

            for offset in 0..<suffix.count {
                if whisperWords[startIndex + offset].normalized == suffix[offset] {
                    matches += 1
                }
            }

            if matches >= requiredMatches {
                return whisperWords[startIndex + suffix.count - 1]
            }
        }

        return nil
    }
    
    private func endIndexIncludingTrailingPunctuation(
        in text: String,
        after wordEndIndex: String.Index
    ) -> String.Index {
        var endIndex = wordEndIndex
        var currentIndex = wordEndIndex

        let allowedTrailingCharacters = ".!?…»”\")'"

        while currentIndex < text.endIndex {
            let character = text[currentIndex]

            if allowedTrailingCharacters.contains(character) {
                endIndex = text.index(after: currentIndex)
                currentIndex = endIndex
            } else {
                break
            }
        }

        return endIndex
    }
    
    private func recognizedWords(in text: String) -> [RecognizedWord] {
        var words: [RecognizedWord] = []

        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.byWords, .localized]
        ) { substring, range, _, _ in
            guard let substring else { return }

            let normalized = self.normalizeWord(substring)

            guard !normalized.isEmpty else { return }

            words.append(
                RecognizedWord(
                    normalized: normalized,
                    endIndex: range.upperBound
                )
            )
        }

        return words
    }

    private func normalizeWord(_ word: String) -> String {
        word
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .filter { $0.isLetter || $0.isNumber }
    }

    private func cleanupTranscriptCommandsOnly(_ text: String) -> String {
        var cleaned = text

        // Explicit voice commands.
        // Явные голосовые команды.
        let replacements: [(String, String, Bool)] = [
            ("новый абзац", "\n\n", true)

        ]

        for (command, replacement, keepsPunctuation) in replacements {
            if keepsPunctuation {
                // If the sentence already ends before the voice command, keep that sign
                // and ignore punctuation after the command.
                // Если предложение уже закончилось перед голосовой командой,
                // оставляем этот знак и игнорируем знак после команды.
                let patternWithExistingSentenceEnd = #"(?i)([.!?])\s+\#(command)\s*[\.,!?]?"#

                let regexWithExistingSentenceEnd = try? NSRegularExpression(pattern: patternWithExistingSentenceEnd)
                let rangeWithExistingSentenceEnd = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)

                cleaned = regexWithExistingSentenceEnd?.stringByReplacingMatches(
                    in: cleaned,
                    range: rangeWithExistingSentenceEnd,
                    withTemplate: "$1\(replacement)"
                ) ?? cleaned

                // If recognition produced "text, новый абзац.", keep only the final sentence sign.
                // Если распознавание дало "текст, новый абзац.", оставляем только финальный знак.
                let patternWithPreviousPunctuation = #"(?i)[,;:]\s+\#(command)\s*([.!?])"#

                let regexWithPreviousPunctuation = try? NSRegularExpression(pattern: patternWithPreviousPunctuation)
                let rangeWithPreviousPunctuation = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)

                cleaned = regexWithPreviousPunctuation?.stringByReplacingMatches(
                    in: cleaned,
                    range: rangeWithPreviousPunctuation,
                    withTemplate: "$1\(replacement)"
                ) ?? cleaned

                let pattern = #"(?i)\#(command)\s*([\.,!?])?"#

                let regex = try? NSRegularExpression(pattern: pattern)
                let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)

                cleaned = regex?.stringByReplacingMatches(
                    in: cleaned,
                    range: range,
                    withTemplate: "$1\(replacement)"
                ) ?? cleaned
            } else {
            
                cleaned = cleaned.replacingOccurrences(
                    of: #"([.!?])\s*[.!?](\n\n)"#,
                    with: "$1$2",
                    options: [.regularExpression]
                )
            }
        }

        // Minimal cleanup only around line breaks.
        // Минимально чистим только пробелы вокруг переносов.
        cleaned = cleaned.replacingOccurrences(of: " \n", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: "\n ", with: "\n")

        // Remove a hanging space before sentence punctuation at a paragraph break.
        // Убираем висячий пробел перед точкой/знаком вопроса/восклицания перед новым абзацем.
        cleaned = cleaned.replacingOccurrences(
            of: #"\s+([.!?])(\n\n)"#,
            with: "$1$2",
            options: [.regularExpression]
        )

        // Remove duplicated sentence-ending punctuation before paragraph breaks.
        // Убираем лишний второй знак конца предложения перед новым абзацем.
        cleaned = cleaned.replacingOccurrences(
            of: #"([.!?])\s+[.!?]\n\n"#,
            with: "$1\n\n",
            options: [.regularExpression]
        )

        cleaned = capitalizeAfterLineBreaks(cleaned)

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func capitalizeAfterLineBreaks(_ text: String) -> String {
        var result = ""
        var shouldCapitalize = true

        for character in text {
            if shouldCapitalize && character.isLetter {
                result.append(String(character).uppercased())
                shouldCapitalize = false
            } else {
                result.append(character)
            }

            if character == "\n" {
                shouldCapitalize = true
            } else if !character.isWhitespace {
                shouldCapitalize = false
            }
        }

        return result
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct CopyIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let sx = rect.width / 20
        let sy = rect.height / 20

        path.addRoundedRect(
            in: CGRect(x: 8 * sx, y: 8 * sy, width: 8 * sx, height: 8 * sy),
            cornerSize: CGSize(width: 1 * sx, height: 1 * sy)
        )

        path.addRoundedRect(
            in: CGRect(x: 4 * sx, y: 4 * sy, width: 8 * sx, height: 8 * sy),
            cornerSize: CGSize(width: 1 * sx, height: 1 * sy)
        )

        return path
    }
}

struct TrashIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let sx = rect.width / 24
        let sy = rect.height / 24

        // Lid.
        // Крышка.
        path.move(to: CGPoint(x: 6.5 * sx, y: 8 * sy))
        path.addLine(to: CGPoint(x: 17.5 * sx, y: 8 * sy))

        // Handle.
        // Ручка.
        path.move(to: CGPoint(x: 9.5 * sx, y: 8 * sy))
        path.addLine(to: CGPoint(x: 10.3 * sx, y: 6 * sy))
        path.addLine(to: CGPoint(x: 13.7 * sx, y: 6 * sy))
        path.addLine(to: CGPoint(x: 14.5 * sx, y: 8 * sy))

        // Body.
        // Корпус.
        path.move(to: CGPoint(x: 8 * sx, y: 10 * sy))
        path.addLine(to: CGPoint(x: 9 * sx, y: 18 * sy))
        path.addCurve(
            to: CGPoint(x: 10.6 * sx, y: 19 * sy),
            control1: CGPoint(x: 9.1 * sx, y: 18.6 * sy),
            control2: CGPoint(x: 9.7 * sx, y: 19 * sy)
        )
        path.addLine(to: CGPoint(x: 13.4 * sx, y: 19 * sy))
        path.addCurve(
            to: CGPoint(x: 15 * sx, y: 18 * sy),
            control1: CGPoint(x: 14.3 * sx, y: 19 * sy),
            control2: CGPoint(x: 14.9 * sx, y: 18.6 * sy)
        )
        path.addLine(to: CGPoint(x: 16 * sx, y: 10 * sy))

        // Inner lines.
        // Внутренние линии.
        path.move(to: CGPoint(x: 11 * sx, y: 11.5 * sy))
        path.addLine(to: CGPoint(x: 11.2 * sx, y: 16.8 * sy))

        path.move(to: CGPoint(x: 13 * sx, y: 11.5 * sy))
        path.addLine(to: CGPoint(x: 12.8 * sx, y: 16.8 * sy))

        return path
    }
}
struct ShareArrowIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let sx = rect.width / 24
        let sy = rect.height / 24

        path.move(to: CGPoint(x: 9 * sx, y: 8 * sy))
        path.addLine(to: CGPoint(x: 9 * sx, y: 5.5 * sy))
        path.addCurve(
            to: CGPoint(x: 10.7 * sx, y: 4.8 * sy),
            control1: CGPoint(x: 9 * sx, y: 4.6 * sy),
            control2: CGPoint(x: 10.1 * sx, y: 4.2 * sy)
        )
        path.addLine(to: CGPoint(x: 17.5 * sx, y: 11 * sy))
        path.addCurve(
            to: CGPoint(x: 17.5 * sx, y: 12.4 * sy),
            control1: CGPoint(x: 17.9 * sx, y: 11.4 * sy),
            control2: CGPoint(x: 17.9 * sx, y: 12 * sy)
        )
        path.addLine(to: CGPoint(x: 10.7 * sx, y: 18.6 * sy))
        path.addCurve(
            to: CGPoint(x: 9 * sx, y: 17.9 * sy),
            control1: CGPoint(x: 10.1 * sx, y: 19.2 * sy),
            control2: CGPoint(x: 9 * sx, y: 18.8 * sy)
        )
        path.addLine(to: CGPoint(x: 9 * sx, y: 15 * sy))
        path.addCurve(
            to: CGPoint(x: 2.5 * sx, y: 17.5 * sy),
            control1: CGPoint(x: 6.2 * sx, y: 15 * sy),
            control2: CGPoint(x: 4.2 * sx, y: 15.7 * sy)
        )
        path.addCurve(
            to: CGPoint(x: 1.7 * sx, y: 17.1 * sy),
            control1: CGPoint(x: 2.2 * sx, y: 17.8 * sy),
            control2: CGPoint(x: 1.6 * sx, y: 17.6 * sy)
        )
        path.addCurve(
            to: CGPoint(x: 9 * sx, y: 8 * sy),
            control1: CGPoint(x: 2.3 * sx, y: 12 * sy),
            control2: CGPoint(x: 4.8 * sx, y: 8.7 * sy)
        )

        return path
    }
}

// Главная круглая кнопка записи
struct RecordCircleButton: View {
    let isRecording: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(.tint)
            // радиус - размер кнопки
                .frame(width: 80, height: 80)

            if isRecording {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.white)
                // размер иконки "стоп" на главной кнопке
                    .frame(width: 30, height: 30)
            } else {
                MicrophoneIconView()
                    .frame(width: 48, height: 58)
            }
        }
        .frame(width: 80, height: 80)
        .padding(.vertical, 4)
        .accessibilityLabel(isRecording ? "Остановить запись" : "Записать")
    }
}

struct MicrophoneIconView: View {
    var body: some View {
        ZStack {
            // Filled microphone capsule.
            // Залитая капсула микрофона.
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white)
                .frame(width: 14, height: 30)
                .offset(y: -9)

            MicrophoneArcIcon()
                .stroke(
                    .white,
                    style: StrokeStyle(
                        lineWidth: 5,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
        }
    }
}

struct MicrophoneArcIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let sx = rect.width / 48
        let sy = rect.height / 58

        // Lower microphone arc.
        // Нижняя дуга микрофона.
        path.move(to: CGPoint(x: 11 * sx, y: 31 * sy))
        path.addCurve(
            to: CGPoint(x: 24 * sx, y: 43 * sy),
            control1: CGPoint(x: 11 * sx, y: 38 * sy),
            control2: CGPoint(x: 16.5 * sx, y: 43 * sy)
        )
        path.addCurve(
            to: CGPoint(x: 37 * sx, y: 31 * sy),
            control1: CGPoint(x: 31.5 * sx, y: 43 * sy),
            control2: CGPoint(x: 37 * sx, y: 38 * sy)
        )

        // Stem.
        // Ножка.
        path.move(to: CGPoint(x: 24 * sx, y: 43 * sy))
        path.addLine(to: CGPoint(x: 24 * sx, y: 51 * sy))

        return path
    }
}

struct AutoScrollingTextView: UIViewRepresentable {
    @Binding var text: String
    let shouldScrollToBottom: Bool

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()

        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)

        context.coordinator.textView = textView

        let toolbar = UIToolbar()
        toolbar.sizeToFit()

        let flexibleSpace = UIBarButtonItem(
            barButtonSystemItem: .flexibleSpace,
            target: nil,
            action: nil
        )

        let doneButton = UIBarButtonItem(
            title: "Готово",
            style: .done,
            target: context.coordinator,
            action: #selector(Coordinator.dismissKeyboard)
        )

        toolbar.items = [flexibleSpace, doneButton]
        textView.inputAccessoryView = toolbar

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }

        guard shouldScrollToBottom, !text.isEmpty else {
            return
        }

        DispatchQueue.main.async {
            let endRange = NSRange(location: max(textView.text.count - 1, 0), length: 1)
            textView.scrollRangeToVisible(endRange)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        weak var textView: UITextView?

        init(text: Binding<String>) {
            self._text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }

        @objc func dismissKeyboard() {
            textView?.resignFirstResponder()
        }
    }
}
