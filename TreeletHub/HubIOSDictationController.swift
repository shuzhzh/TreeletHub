import AVFoundation
import Combine
import Foundation
import Speech

/// Push-to-talk on the phone: capture the iPhone microphone, transcribe on-device,
/// and hand the final text back so it can be sent to the Mac over the LAN.
@MainActor
final class HubIOSDictationController: ObservableObject {
    enum DictationError: LocalizedError {
        case microphoneDenied
        case speechDenied
        case recognizerUnavailable
        case emptyTranscript

        var errorDescription: String? {
            switch self {
            case .microphoneDenied:
                return "需要在 iPhone「设置 → 隐私与安全性 → 麦克风」中允许 TreeletHub"
            case .speechDenied:
                return "需要在 iPhone「设置 → 隐私与安全性 → 语音识别」中允许 TreeletHub"
            case .recognizerUnavailable:
                return "当前系统语言不支持语音识别"
            case .emptyTranscript:
                return "没有识别到语音内容，请靠近麦克风再说一次"
            }
        }
    }

    /// Live partial transcript for UI feedback while the user is speaking.
    @Published private(set) var partialTranscript = ""
    @Published private(set) var isRecording = false

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latestTranscript = ""
    private var finalContinuation: CheckedContinuation<String, Never>?

    func start() async throws {
        try await ensurePermissionsAndRecognizer()
        cancel()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        latestTranscript = ""
        partialTranscript = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.latestTranscript = result.bestTranscription.formattedString
                    self.partialTranscript = self.latestTranscript
                    if result.isFinal {
                        self.finishWaitingForFinal()
                    }
                }
                if error != nil {
                    self.finishWaitingForFinal()
                }
            }
        }
    }

    /// Stops capture and returns the best transcript (may be empty).
    func stopAndFinalize(timeoutNanoseconds: UInt64 = 1_800_000_000) async -> String {
        guard isRecording || request != nil else {
            return latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        request?.endAudio()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false

        let text: String = await withTaskGroup(of: String.self) { group in
            group.addTask { @MainActor in
                await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
                    if self.finalContinuation != nil {
                        cont.resume(returning: self.latestTranscript)
                        return
                    }
                    self.finalContinuation = cont
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return await MainActor.run { self.latestTranscript }
            }
            let first = await group.next() ?? ""
            group.cancelAll()
            return first
        }

        task?.cancel()
        task = nil
        request = nil
        finishWaitingForFinal()
        deactivateSession()

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        request?.endAudio()
        task?.cancel()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false
        latestTranscript = ""
        partialTranscript = ""
        request = nil
        task = nil
        finishWaitingForFinal()
        deactivateSession()
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func finishWaitingForFinal() {
        if let cont = finalContinuation {
            finalContinuation = nil
            cont.resume(returning: latestTranscript)
        }
    }

    private func ensurePermissionsAndRecognizer() async throws {
        let micOK = await requestMicrophoneAccess()
        guard micOK else { throw DictationError.microphoneDenied }

        let speech = await requestSpeechAuthorization()
        guard speech == .authorized else { throw DictationError.speechDenied }

        let preferred = SFSpeechRecognizer(locale: Locale.autoupdatingCurrent)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let preferred, preferred.isAvailable else {
            throw DictationError.recognizerUnavailable
        }
        recognizer = preferred
    }

    private func requestMicrophoneAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current != .notDetermined { return current }
        return await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
    }
}
