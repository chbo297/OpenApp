//
//  OpenAPPVoiceRecognitionManager.swift
//  OpenAPPUI
//

#if canImport(AVFoundation) && canImport(Speech) && (os(iOS) || targetEnvironment(macCatalyst))
import AVFoundation
import Foundation
import Speech

public enum OpenAPPVoiceRecognitionLoadingReason: Sendable {
    case requestingSpeechPermission
    case requestingMicrophonePermission
    case preparingAudioSession
    case waitingForRecognizer
}

public struct OpenAPPVoiceRecognitionLoadingContext: Sendable {
    public let reason: OpenAPPVoiceRecognitionLoadingReason
    public let timestamp: TimeInterval
}

public struct OpenAPPVoiceRecognitionRecordingContext: Sendable {
    public let partialText: String
    public let finalText: String
    public let combinedText: String
    public let audioLevel: Double
    public let timestamp: TimeInterval
}

public enum OpenAPPVoiceRecognitionEndReason: Sendable {
    case userStopped
    case cancelled
    case interrupted
    case permissionDenied
    case recognizerUnavailable
    case audioSessionUnavailable
    case failed(String)
}

public struct OpenAPPVoiceRecognitionEndContext: Sendable {
    public let reason: OpenAPPVoiceRecognitionEndReason
    public let finalText: String
    public let timestamp: TimeInterval
}

public enum OpenAPPVoiceRecognitionEvent: Sendable {
    case loading(OpenAPPVoiceRecognitionLoadingContext)
    case recording(OpenAPPVoiceRecognitionRecordingContext)
    case ended(OpenAPPVoiceRecognitionEndContext)
}

public enum OpenAPPVoiceRecognitionStopResult: Sendable {
    case alreadyStopped
    case stopped(finalText: String, reason: OpenAPPVoiceRecognitionEndReason)
}

// Mutable recognition state is isolated to `audioQueue`.
public final class OpenAPPVoiceRecognitionManager: NSObject, @unchecked Sendable {
    public static let shared = OpenAPPVoiceRecognitionManager()

    /// Enables direct console logs for voice-recognition state changes. 默认关闭，调试音频层时再手动打开。
    public var isConsoleLoggingEnabled: Bool {
        get {
            loggingLock.lock()
            defer { loggingLock.unlock() }
            return _isConsoleLoggingEnabled
        }
        set {
            loggingLock.lock()
            _isConsoleLoggingEnabled = newValue
            loggingLock.unlock()
        }
    }

    private let audioQueue = DispatchQueue(
        label: "com.openapp.voiceRecognition.audio",
        qos: .userInitiated
    )
    private let loggingLock = NSLock()
    private var _isConsoleLoggingEnabled = false

    private enum InternalState {
        case idle
        case starting(UUID)
        case recording(UUID)
        case stopping(UUID)

        var sessionID: UUID? {
            switch self {
            case .idle:
                return nil
            case .starting(let id), .recording(let id), .stopping(let id):
                return id
            }
        }
    }

    private var state: InternalState = .idle
    private var continuation: AsyncStream<OpenAPPVoiceRecognitionEvent>.Continuation?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var finalText = ""
    private var partialText = ""

    public func startRecording(locale: Locale = .current) -> AsyncStream<OpenAPPVoiceRecognitionEvent> {
        let sessionID = UUID()
        log("startRecording requested locale=\(locale.identifier) session=\(shortSessionID(sessionID))")

        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.audioQueue.async { [weak self] in
                    guard let self = self, self.state.sessionID == sessionID else { return }
                    self.log("stream terminated session=\(self.shortSessionID(sessionID))")
                    self.finishCurrentSession(reason: .cancelled)
                }
            }

            self.audioQueue.async { [weak self] in
                guard let self = self else {
                    DispatchQueue.main.async {
                        continuation.finish()
                    }
                    return
                }
                if self.state.sessionID != nil {
                    self.finishCurrentSession(reason: .cancelled)
                }

                self.continuation = continuation
                self.setState(.starting(sessionID), reason: "start recording")
                self.finalText = ""
                self.partialText = ""
                self.emitLoading(.requestingSpeechPermission, sessionID: sessionID)
                self.requestSpeechPermission(sessionID: sessionID, locale: locale)
            }
        }
    }

    public func stopRecording() async -> OpenAPPVoiceRecognitionStopResult {
        await stopRecording(reason: .userStopped)
    }

    func requestStopRecording(reason: OpenAPPVoiceRecognitionEndReason) {
        audioQueue.async { [weak self] in
            self?.finishCurrentRecording(reason: reason, resumes: nil)
        }
    }

    func stopRecording(reason: OpenAPPVoiceRecognitionEndReason) async -> OpenAPPVoiceRecognitionStopResult {
        await withCheckedContinuation { continuation in
            audioQueue.async { [weak self] in
                self?.finishCurrentRecording(reason: reason, resumes: continuation)
                    ?? continuation.resume(returning: .alreadyStopped)
            }
        }
    }

    private func finishCurrentRecording(
        reason: OpenAPPVoiceRecognitionEndReason,
        resumes continuation: CheckedContinuation<OpenAPPVoiceRecognitionStopResult, Never>?
    ) {
        log("stopRecording requested reason=\(describe(reason))")
        guard let sessionID = state.sessionID else {
            log("stopRecording ignored: already stopped")
            continuation?.resume(returning: .alreadyStopped)
            return
        }

        setState(.stopping(sessionID), reason: "stop requested reason=\(describe(reason))")
        let text = combinedText
        finishCurrentSession(reason: reason)
        continuation?.resume(returning: .stopped(finalText: text, reason: reason))
    }

    private func requestSpeechPermission(sessionID: UUID, locale: Locale) {
        let status = SFSpeechRecognizer.authorizationStatus()
        log("speech permission status=\(describe(status)) session=\(shortSessionID(sessionID))")
        switch status {
        case .authorized:
            requestMicrophonePermission(sessionID: sessionID, locale: locale)
        case .denied, .restricted:
            finishSessionIfCurrent(sessionID, reason: .permissionDenied)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                self?.audioQueue.async { [weak self] in
                    guard let self = self, self.state.sessionID == sessionID else { return }
                    self.log("speech permission callback status=\(self.describe(status)) session=\(self.shortSessionID(sessionID))")
                    if status == .authorized {
                        self.requestMicrophonePermission(sessionID: sessionID, locale: locale)
                    } else {
                        self.finishSessionIfCurrent(sessionID, reason: .permissionDenied)
                    }
                }
            }
        @unknown default:
            finishSessionIfCurrent(sessionID, reason: .permissionDenied)
        }
    }

    private func requestMicrophonePermission(sessionID: UUID, locale: Locale) {
        emitLoading(.requestingMicrophonePermission, sessionID: sessionID)
        let audioSession = AVAudioSession.sharedInstance()

        let permission = audioSession.recordPermission
        log("microphone permission status=\(describe(permission)) session=\(shortSessionID(sessionID))")
        switch permission {
        case .granted:
            startAudioSession(sessionID: sessionID, locale: locale)
        case .denied:
            finishSessionIfCurrent(sessionID, reason: .permissionDenied)
        case .undetermined:
            audioSession.requestRecordPermission { [weak self] granted in
                self?.audioQueue.async { [weak self] in
                    guard let self = self, self.state.sessionID == sessionID else { return }
                    self.log("microphone permission callback granted=\(granted) session=\(self.shortSessionID(sessionID))")
                    if granted {
                        self.startAudioSession(sessionID: sessionID, locale: locale)
                    } else {
                        self.finishSessionIfCurrent(sessionID, reason: .permissionDenied)
                    }
                }
            }
        @unknown default:
            finishSessionIfCurrent(sessionID, reason: .permissionDenied)
        }
    }

    private func startAudioSession(sessionID: UUID, locale: Locale) {
        guard state.sessionID == sessionID else {
            log("startAudioSession ignored for stale session=\(shortSessionID(sessionID)) current=\(shortSessionID(state.sessionID))")
            return
        }
        emitLoading(.preparingAudioSession, sessionID: sessionID)

        let speechRecognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            log("speech recognizer unavailable locale=\(locale.identifier) session=\(shortSessionID(sessionID))")
            finishSessionIfCurrent(sessionID, reason: .recognizerUnavailable)
            return
        }
        log("speech recognizer ready locale=\(speechRecognizer.locale.identifier) session=\(shortSessionID(sessionID))")

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            log("audio session active session=\(shortSessionID(sessionID))")
        } catch {
            log("audio session unavailable error=\(error.localizedDescription) session=\(shortSessionID(sessionID))")
            finishSessionIfCurrent(sessionID, reason: .audioSessionUnavailable)
            return
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        recognizer = speechRecognizer
        audioEngine = engine
        recognitionRequest = request

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.audioQueue.async { [weak self] in
                self?.handleRecognitionCallback(sessionID: sessionID, result: result, error: error)
            }
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAudioSessionInterruption(_:)),
                name: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance()
            )
            setState(.recording(sessionID), reason: "audio engine started")
            emitRecording(sessionID: sessionID)
        } catch {
            inputNode.removeTap(onBus: 0)
            log("audio engine start failed error=\(error.localizedDescription) session=\(shortSessionID(sessionID))")
            finishSessionIfCurrent(sessionID, reason: .failed(error.localizedDescription))
        }
    }

    private func handleRecognitionCallback(
        sessionID: UUID,
        result: SFSpeechRecognitionResult?,
        error: Error?
    ) {
        guard state.sessionID == sessionID else {
            log("recognition callback ignored for stale session=\(shortSessionID(sessionID)) current=\(shortSessionID(state.sessionID))")
            return
        }
        guard case .recording = state else {
            if case .stopping = state { return }
            log("recognition callback ignored while state=\(describe(state)) session=\(shortSessionID(sessionID))")
            return
        }

        if let result = result {
            partialText = result.bestTranscription.formattedString
            if result.isFinal {
                finalText = partialText
            }
            emitRecording(sessionID: sessionID)
        }

        if let error = error {
            log("recognition callback error=\(error.localizedDescription) session=\(shortSessionID(sessionID))")
            finishSessionIfCurrent(sessionID, reason: .failed(error.localizedDescription))
        }
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: rawType) == .began else {
            return
        }
        audioQueue.async { [weak self] in
            guard let self = self, self.state.sessionID != nil else { return }
            self.log("audio session interrupted current=\(self.describe(self.state))")
            self.finishCurrentSession(reason: .interrupted)
        }
    }

    private func finishSessionIfCurrent(_ sessionID: UUID, reason: OpenAPPVoiceRecognitionEndReason) {
        guard state.sessionID == sessionID else {
            log("finish ignored for stale session=\(shortSessionID(sessionID)) reason=\(describe(reason)) current=\(shortSessionID(state.sessionID))")
            return
        }
        finishCurrentSession(reason: reason)
    }

    private func finishCurrentSession(reason: OpenAPPVoiceRecognitionEndReason) {
        guard let sessionID = state.sessionID else {
            log("finish ignored: already idle reason=\(describe(reason))")
            return
        }
        setState(.stopping(sessionID), reason: "finish reason=\(describe(reason))")

        let text = combinedText
        cleanupAudioResources()
        let endedEvent = OpenAPPVoiceRecognitionEvent.ended(OpenAPPVoiceRecognitionEndContext(
            reason: reason,
            finalText: text,
            timestamp: now
        ))
        log("event \(describe(endedEvent)) session=\(shortSessionID(sessionID))")
        let streamContinuation = continuation
        continuation = nil
        setState(.idle, reason: "finish complete")
        if let streamContinuation = streamContinuation {
            deliverOnMain(endedEvent, continuation: streamContinuation, finish: true)
        }
    }

    private func cleanupAudioResources() {
        log("cleanup audio resources state=\(describe(state))")
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)

        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning {
                engine.stop()
            }
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil
        recognizer = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func emitLoading(_ reason: OpenAPPVoiceRecognitionLoadingReason, sessionID: UUID) {
        emit(.loading(OpenAPPVoiceRecognitionLoadingContext(reason: reason, timestamp: now)), sessionID: sessionID)
    }

    private func emitRecording(sessionID: UUID) {
        emit(
            .recording(OpenAPPVoiceRecognitionRecordingContext(
                partialText: partialText,
                finalText: finalText,
                combinedText: combinedText,
                audioLevel: 0,
                timestamp: now
            )),
            sessionID: sessionID
        )
    }

    private func emit(_ event: OpenAPPVoiceRecognitionEvent, sessionID: UUID) {
        guard state.sessionID == sessionID else {
            log("event dropped \(describe(event)) stale session=\(shortSessionID(sessionID)) current=\(shortSessionID(state.sessionID))")
            return
        }
        log("event \(describe(event)) session=\(shortSessionID(sessionID))")
        if let continuation = continuation {
            deliverOnMain(event, continuation: continuation)
        }
    }

    private func deliverOnMain(
        _ event: OpenAPPVoiceRecognitionEvent,
        continuation: AsyncStream<OpenAPPVoiceRecognitionEvent>.Continuation,
        finish: Bool = false
    ) {
        DispatchQueue.main.async {
            continuation.yield(event)
            if finish {
                continuation.finish()
            }
        }
    }

    private func setState(_ newState: InternalState, reason: String) {
        state = newState
        log("state -> \(describe(newState)) reason=\(reason)")
    }

    private func log(_ message: String) {
        guard isConsoleLoggingEnabled else { return }
        print("[OpenAPPVoiceRecognition] \(message)")
    }

    private func shortSessionID(_ sessionID: UUID?) -> String {
        guard let sessionID = sessionID else { return "none" }
        return String(sessionID.uuidString.prefix(8))
    }

    private func describe(_ state: InternalState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .starting(let id):
            return "starting(\(shortSessionID(id)))"
        case .recording(let id):
            return "recording(\(shortSessionID(id)))"
        case .stopping(let id):
            return "stopping(\(shortSessionID(id)))"
        }
    }

    private func describe(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .notDetermined:
            return "notDetermined"
        case .restricted:
            return "restricted"
        @unknown default:
            return "unknown"
        }
    }

    private func describe(_ permission: AVAudioSession.RecordPermission) -> String {
        switch permission {
        case .granted:
            return "granted"
        case .denied:
            return "denied"
        case .undetermined:
            return "undetermined"
        @unknown default:
            return "unknown"
        }
    }

    private func describe(_ reason: OpenAPPVoiceRecognitionLoadingReason) -> String {
        switch reason {
        case .requestingSpeechPermission:
            return "requestingSpeechPermission"
        case .requestingMicrophonePermission:
            return "requestingMicrophonePermission"
        case .preparingAudioSession:
            return "preparingAudioSession"
        case .waitingForRecognizer:
            return "waitingForRecognizer"
        }
    }

    private func describe(_ reason: OpenAPPVoiceRecognitionEndReason) -> String {
        switch reason {
        case .userStopped:
            return "userStopped"
        case .cancelled:
            return "cancelled"
        case .interrupted:
            return "interrupted"
        case .permissionDenied:
            return "permissionDenied"
        case .recognizerUnavailable:
            return "recognizerUnavailable"
        case .audioSessionUnavailable:
            return "audioSessionUnavailable"
        case .failed(let message):
            return "failed(\(message))"
        }
    }

    private func describe(_ event: OpenAPPVoiceRecognitionEvent) -> String {
        switch event {
        case .loading(let context):
            return "loading(reason=\(describe(context.reason)))"
        case .recording(let context):
            return "recording(textLength=\(context.combinedText.count), preview=\(preview(context.combinedText)))"
        case .ended(let context):
            return "ended(reason=\(describe(context.reason)), finalLength=\(context.finalText.count), preview=\(preview(context.finalText)))"
        }
    }

    private func preview(_ text: String) -> String {
        guard !text.isEmpty else { return "\"\"" }
        let limit = 24
        let prefix = text.prefix(limit)
        let suffix = text.count > limit ? "..." : ""
        return "\"\(prefix)\(suffix)\""
    }

    private var combinedText: String {
        partialText.isEmpty ? finalText : partialText
    }

    private var now: TimeInterval {
        Date.timeIntervalSinceReferenceDate
    }
}

#endif
