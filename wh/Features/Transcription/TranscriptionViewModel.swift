//
//  TranscriptionViewModel.swift
//  wh
//

import AppKit
import Combine
import Foundation
import os

@MainActor
final class TranscriptionViewModel: ObservableObject {
    /// Entries fetched per page while scrolling the history.
    static let historyPageSize = 6
    /// Anything shorter is an accidental click, not speech; it is discarded instead of
    /// producing a "no speech detected" error.
    static let minimumRecordingDuration: TimeInterval = 0.5

    @Published private(set) var state: TranscriptionState = .preparingModel(progress: nil)
    /// Newest first. Grows page by page via `loadMoreHistoryIfNeeded(after:)`.
    @Published private(set) var history: [TranscriptionEntry] = []
    @Published private(set) var hasMoreHistory = true
    @Published private(set) var recordingDuration: TimeInterval = 0
    /// Transient, non-blocking feedback line (e.g. the ChatGPT hand-off status).
    @Published private(set) var notice: String?

    private let audioRecorder: any AudioRecording
    private let transcriptionService: any SpeechTranscribing
    private let clipboard: any ClipboardWriting
    private let historyStore: any HistoryStoring
    private let chatGPTLauncher: any ChatGPTLaunching
    private let logger = AppLogger.viewModel

    private var isModelReady = false
    private var isStartingRecording = false
    private var isLoadingHistory = false
    private var durationTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    init(
        audioRecorder: any AudioRecording,
        transcriptionService: any SpeechTranscribing,
        clipboard: any ClipboardWriting,
        historyStore: any HistoryStoring,
        chatGPTLauncher: any ChatGPTLaunching
    ) {
        self.audioRecorder = audioRecorder
        self.transcriptionService = transcriptionService
        self.clipboard = clipboard
        self.historyStore = historyStore
        self.chatGPTLauncher = chatGPTLauncher
        loadMoreHistory()
    }

    var formattedDuration: String {
        DurationFormatter.string(from: recordingDuration)
    }

    /// `history` grouped by calendar day for the sectioned list.
    var historySections: [HistorySection] {
        HistorySection.group(history)
    }

    // MARK: - Actions

    /// Loads the speech model. Safe to call more than once; it is a no-op once ready.
    func prepare() async {
        guard !isModelReady else { return }
        state = .preparingModel(progress: nil)

        do {
            try await transcriptionService.prepare { [weak self] progress in
                Task { @MainActor in
                    guard let self, self.state.isPreparingModel else { return }
                    self.state = .preparingModel(progress: progress)
                }
            }
            isModelReady = true
            state = .ready
        } catch {
            logger.error("Model preparation failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(AppError.from(error, fallback: .modelInitializationFailed))
        }
    }

    /// Single entry point for the record button: start, stop, or recover from an error.
    func toggleRecording() async {
        switch state {
        case .ready: await startRecording()
        case .recording: await stopRecording()
        case .failed: reset()
        case .preparingModel, .transcribing: break
        }
    }

    func startRecording() async {
        // The first start in a process can take a moment while audio spins up; a second
        // click in that window must not try to open another session on top of it.
        guard isModelReady, state == .ready, !isStartingRecording else { return }
        isStartingRecording = true
        defer { isStartingRecording = false }
        recordingDuration = 0

        do {
            try await audioRecorder.startRecording()
            state = .recording
            startDurationTimer()
        } catch {
            logger.error("Start recording failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(AppError.from(error, fallback: .recordingFailed))
        }
    }

    /// Stops capture and transcribes immediately; the result lands at the top of `history`
    /// and is copied to the clipboard right away.
    func stopRecording() async {
        guard state == .recording else { return }
        stopDurationTimer()

        if audioRecorder.currentDuration < Self.minimumRecordingDuration {
            logger.info("Recording too short, discarding")
            cancelRecording()
            showNotice("Recording too short. Hold on a little longer.")
            return
        }
        state = .transcribing

        var audioURL: URL?
        defer { removeTemporaryFile(audioURL) }

        do {
            let url = try await audioRecorder.stopRecording()
            audioURL = url
            let text = try await transcriptionService.transcribe(audioURL: url)
            append(TranscriptionEntry(text: text))
            clipboard.copy(text)
            state = .ready
        } catch AppError.emptyTranscription {
            // Silence is not a failure worth a retry button: drop it and stay ready.
            logger.info("No speech detected, discarding")
            showNotice("No speech detected. Try again a little closer to the mic.")
            state = .ready
        } catch {
            logger.error("Stop/transcribe failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(AppError.from(error, fallback: .transcriptionFailed))
        }
    }

    /// Discards the in-progress recording without transcribing it.
    func cancelRecording() {
        guard state == .recording else { return }
        stopDurationTimer()
        audioRecorder.cancelRecording()
        recordingDuration = 0
        state = .ready
    }

    func copy(_ entry: TranscriptionEntry) {
        clipboard.copy(entry.text)
    }

    /// Copies the entry, opens ChatGPT and pastes it into the composer (never sends).
    func openInChatGPT(_ entry: TranscriptionEntry) async {
        showNotice("Opening ChatGPT…", autoDismiss: false)
        do {
            switch try await chatGPTLauncher.openInChatGPT(text: entry.text) {
            case .pasted:
                clearNotice()
            case .copiedWithoutPaste:
                showNotice("Copied. Enable Accessibility to paste automatically.")
            }
        } catch {
            logger.error("Open in ChatGPT failed: \(error.localizedDescription, privacy: .public)")
            showNotice(error.localizedDescription)
        }
    }

    /// Returns to the idle state after an error. If the model never loaded, retries preparation.
    func reset() {
        guard !state.isBusy else { return }
        stopDurationTimer()
        recordingDuration = 0

        if isModelReady {
            state = .ready
        } else {
            Task { await prepare() }
        }
    }

    func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Notice

    private func showNotice(_ text: String, autoDismiss: Bool = true) {
        noticeTask?.cancel()
        notice = text
        guard autoDismiss else { return }
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    private func clearNotice() {
        noticeTask?.cancel()
        notice = nil
    }

    // MARK: - History

    /// Fetches the next page once the list is scrolled near `entry`.
    func loadMoreHistoryIfNeeded(after entry: TranscriptionEntry) {
        guard let index = history.firstIndex(of: entry), index >= history.count - 2 else { return }
        loadMoreHistory()
    }

    private func loadMoreHistory() {
        guard hasMoreHistory, !isLoadingHistory else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        do {
            let page = try historyStore.fetch(offset: history.count, limit: Self.historyPageSize)
            history.append(contentsOf: page)
            hasMoreHistory = page.count == Self.historyPageSize
        } catch {
            logger.error("History fetch failed: \(error.localizedDescription, privacy: .public)")
            hasMoreHistory = false
        }
    }

    private func append(_ entry: TranscriptionEntry) {
        history.insert(entry, at: 0)
        do {
            try historyStore.insert(entry)
        } catch {
            logger.error("History insert failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Duration tracking

    private func startDurationTimer() {
        durationTask?.cancel()
        durationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                recordingDuration = audioRecorder.currentDuration
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stopDurationTimer() {
        durationTask?.cancel()
        durationTask = nil
    }

    // MARK: - Temporary files

    private func removeTemporaryFile(_ url: URL?) {
        guard let url else { return }
        do {
            try FileManager.default.removeItem(at: url)
            logger.info("Temporary audio deleted")
        } catch {
            logger.error("Could not delete temporary audio: \(error.localizedDescription, privacy: .public)")
        }
    }
}
