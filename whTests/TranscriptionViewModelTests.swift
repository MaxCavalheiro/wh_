//
//  TranscriptionViewModelTests.swift
//  whTests
//

import Combine
import XCTest
@testable import wh

@MainActor
final class TranscriptionViewModelTests: XCTestCase {
    private var recorder: MockAudioRecorder!
    private var transcriber: MockSpeechTranscriber!
    private var clipboard: MockClipboard!
    private var historyStore: MockHistoryStore!
    private var chatGPTLauncher: MockChatGPTLauncher!
    private var viewModel: TranscriptionViewModel!

    override func setUp() {
        super.setUp()
        recorder = MockAudioRecorder()
        transcriber = MockSpeechTranscriber()
        clipboard = MockClipboard()
        historyStore = MockHistoryStore()
        chatGPTLauncher = MockChatGPTLauncher()
        viewModel = makeViewModel()
    }

    override func tearDown() {
        viewModel = nil
        chatGPTLauncher = nil
        historyStore = nil
        clipboard = nil
        transcriber = nil
        recorder = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeViewModel() -> TranscriptionViewModel {
        TranscriptionViewModel(
            audioRecorder: recorder,
            transcriptionService: transcriber,
            clipboard: clipboard,
            historyStore: historyStore,
            chatGPTLauncher: chatGPTLauncher
        )
    }

    /// Creates a real temporary file so the view model's cleanup can be observed.
    private func makeTemporaryAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "test-recording-\(UUID().uuidString).wav")
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: url)
        return url
    }

    private func prepareAndStart() async {
        await viewModel.prepare()
        await viewModel.startRecording()
    }

    private func recordAndTranscribe(_ text: String) async {
        transcriber.transcriptionText = text
        await viewModel.startRecording()
        await viewModel.stopRecording()
    }

    // MARK: - Initial state

    func testInitialState() {
        XCTAssertEqual(viewModel.state, .preparingModel(progress: nil))
        XCTAssertTrue(viewModel.history.isEmpty)
        XCTAssertEqual(viewModel.recordingDuration, 0)
        XCTAssertEqual(viewModel.formattedDuration, "00:00")
    }

    func testLoadsFirstHistoryPageOnInit() {
        historyStore = MockHistoryStore()
        historyStore.stored = (1...10).map { TranscriptionEntry(text: "entry \($0)") }

        viewModel = makeViewModel()

        XCTAssertEqual(viewModel.history.map(\.text), (1...6).map { "entry \($0)" })
        XCTAssertTrue(viewModel.hasMoreHistory)
        XCTAssertEqual(historyStore.fetchCalls.count, 1)
        XCTAssertEqual(historyStore.fetchCalls[0].offset, 0)
        XCTAssertEqual(historyStore.fetchCalls[0].limit, 6)
    }

    func testShortHistoryHasNoMorePages() {
        historyStore.stored = [TranscriptionEntry(text: "only")]

        viewModel = makeViewModel()

        XCTAssertEqual(viewModel.history.count, 1)
        XCTAssertFalse(viewModel.hasMoreHistory)
    }

    func testScrollingNearTheEndLoadsNextPage() {
        historyStore.stored = (1...14).map { TranscriptionEntry(text: "entry \($0)") }
        viewModel = makeViewModel()

        // Rows far from the end must not trigger a fetch.
        viewModel.loadMoreHistoryIfNeeded(after: viewModel.history[0])
        XCTAssertEqual(viewModel.history.count, 6)

        viewModel.loadMoreHistoryIfNeeded(after: viewModel.history[4])
        XCTAssertEqual(viewModel.history.count, 12)
        XCTAssertEqual(historyStore.fetchCalls.last?.offset, 6)
        XCTAssertTrue(viewModel.hasMoreHistory)

        viewModel.loadMoreHistoryIfNeeded(after: viewModel.history[11])
        XCTAssertEqual(viewModel.history.count, 14)
        XCTAssertFalse(viewModel.hasMoreHistory)

        // Nothing left: no further fetches.
        let calls = historyStore.fetchCalls.count
        viewModel.loadMoreHistoryIfNeeded(after: viewModel.history[13])
        XCTAssertEqual(historyStore.fetchCalls.count, calls)
    }

    func testHistoryFetchFailureStopsPaging() {
        historyStore.fetchError = NSError(domain: "db", code: 1)

        viewModel = makeViewModel()

        XCTAssertTrue(viewModel.history.isEmpty)
        XCTAssertFalse(viewModel.hasMoreHistory)
    }

    func testNewTranscriptionKeepsPagingOffsetsConsistent() async {
        historyStore.stored = (1...8).map { TranscriptionEntry(text: "entry \($0)") }
        viewModel = makeViewModel()
        await viewModel.prepare()

        await recordAndTranscribe("new")
        XCTAssertEqual(viewModel.history.first?.text, "new")
        XCTAssertEqual(viewModel.history.count, 7)

        viewModel.loadMoreHistoryIfNeeded(after: viewModel.history[6])

        // Offset 7 skips "new" + the 6 already shown, so entry 7 and 8 come next without duplicates.
        XCTAssertEqual(historyStore.fetchCalls.last?.offset, 7)
        XCTAssertEqual(viewModel.history.map(\.text), ["new"] + (1...8).map { "entry \($0)" })
    }

    // MARK: - Model preparation

    func testPrepareSuccessMovesToReady() async {
        await viewModel.prepare()

        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(transcriber.prepareCallCount, 1)
    }

    func testPrepareReportsDownloadProgress() async {
        transcriber.progressUpdates = [0.25, 0.5]
        var observed: [TranscriptionState] = []
        let cancellable = viewModel.$state.sink { observed.append($0) }
        defer { cancellable.cancel() }

        await viewModel.prepare()
        await Task.yield()

        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertTrue(observed.contains(.preparingModel(progress: 0.25)))
        XCTAssertTrue(observed.contains(.preparingModel(progress: 0.5)))
    }

    func testPrepareFailureShowsError() async {
        transcriber.prepareError = AppError.modelDownloadFailed

        await viewModel.prepare()

        XCTAssertEqual(viewModel.state, .failed(.modelDownloadFailed))
    }

    func testPrepareMapsUnknownErrorsToInitializationFailure() async {
        transcriber.prepareError = NSError(domain: "test", code: 1)

        await viewModel.prepare()

        XCTAssertEqual(viewModel.state, .failed(.modelInitializationFailed))
    }

    func testPrepareIsIdempotentOnceReady() async {
        await viewModel.prepare()
        await viewModel.prepare()

        XCTAssertEqual(transcriber.prepareCallCount, 1)
    }

    // MARK: - Start recording

    func testStartRecordingSuccess() async {
        await prepareAndStart()

        XCTAssertEqual(viewModel.state, .recording)
        XCTAssertEqual(recorder.startCallCount, 1)
    }

    func testStartRecordingIgnoredWhileModelNotReady() async {
        await viewModel.startRecording()

        XCTAssertEqual(viewModel.state, .preparingModel(progress: nil))
        XCTAssertEqual(recorder.startCallCount, 0)
    }

    func testStartRecordingPermissionDenied() async {
        recorder.startError = AppError.microphonePermissionDenied

        await prepareAndStart()

        XCTAssertEqual(viewModel.state, .failed(.microphonePermissionDenied))
    }

    func testStartRecordingGenericFailureMapsToRecordingFailed() async {
        recorder.startError = NSError(domain: "avfoundation", code: -1)

        await prepareAndStart()

        XCTAssertEqual(viewModel.state, .failed(.recordingFailed))
    }

    func testStartRecordingDoesNotStartTwice() async {
        await prepareAndStart()
        await viewModel.startRecording()

        XCTAssertEqual(recorder.startCallCount, 1)
    }

    /// A second click while the first start is still spinning up the audio system must
    /// not open another session (which would fail and surface an error).
    func testStartRecordingWhileStartingIsIgnored() async {
        await viewModel.prepare()
        recorder.startDelay = .milliseconds(100)

        async let first: Void = viewModel.startRecording()
        async let second: Void = viewModel.startRecording()
        _ = await (first, second)

        XCTAssertEqual(recorder.startCallCount, 1)
        XCTAssertEqual(viewModel.state, .recording)
    }

    // MARK: - Toggle

    func testToggleStartsThenStopsRecording() async throws {
        recorder.stopURL = try makeTemporaryAudioFile()
        await viewModel.prepare()

        await viewModel.toggleRecording()
        XCTAssertEqual(viewModel.state, .recording)

        await viewModel.toggleRecording()
        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(viewModel.history.count, 1)
    }

    func testToggleRecoversFromError() async {
        recorder.startError = AppError.recordingFailed
        await prepareAndStart()
        XCTAssertEqual(viewModel.state, .failed(.recordingFailed))

        await viewModel.toggleRecording()

        XCTAssertEqual(viewModel.state, .ready)
    }

    func testToggleIgnoredWhileBusy() async {
        await viewModel.toggleRecording()

        XCTAssertEqual(recorder.startCallCount, 0)
        XCTAssertEqual(viewModel.state, .preparingModel(progress: nil))
    }

    // MARK: - Stop recording + transcription

    func testStopRecordingTranscribesAndAddsToHistory() async throws {
        let url = try makeTemporaryAudioFile()
        recorder.stopURL = url
        transcriber.transcriptionText = "Olá, mundo."

        await prepareAndStart()
        await viewModel.stopRecording()

        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(viewModel.history.map(\.text), ["Olá, mundo."])
        XCTAssertEqual(historyStore.stored.map(\.text), ["Olá, mundo."])
        XCTAssertEqual(clipboard.copiedText, "Olá, mundo.", "finished transcription is copied automatically")
        XCTAssertEqual(transcriber.lastAudioURL, url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "temporary audio should be deleted")
    }

    func testEveryTranscriptionIsPersistedNewestFirst() async {
        await viewModel.prepare()

        for text in ["one", "two", "three", "four"] {
            await recordAndTranscribe(text)
        }

        XCTAssertEqual(viewModel.history.map(\.text), ["four", "three", "two", "one"])
        XCTAssertEqual(historyStore.stored.map(\.text), ["four", "three", "two", "one"])
        XCTAssertEqual(historyStore.insertCallCount, 4)
    }

    // MARK: - Cancel

    func testCancelDiscardsRecordingWithoutTranscribing() async {
        await prepareAndStart()

        viewModel.cancelRecording()

        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(recorder.cancelCallCount, 1)
        XCTAssertEqual(recorder.stopCallCount, 0)
        XCTAssertEqual(transcriber.transcribeCallCount, 0)
        XCTAssertTrue(viewModel.history.isEmpty)
        XCTAssertNil(clipboard.copiedText)
        XCTAssertEqual(viewModel.recordingDuration, 0)
    }

    func testCancelIgnoredWhenNotRecording() async {
        await viewModel.prepare()

        viewModel.cancelRecording()

        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(recorder.cancelCallCount, 0)
    }

    func testCanRecordAgainAfterCancel() async throws {
        recorder.stopURL = try makeTemporaryAudioFile()
        await prepareAndStart()
        viewModel.cancelRecording()

        await recordAndTranscribe("after cancel")

        XCTAssertEqual(viewModel.history.map(\.text), ["after cancel"])
    }

    func testStopDiscardsRecordingsThatAreTooShort() async {
        await prepareAndStart()
        recorder.currentDuration = 0.2

        await viewModel.stopRecording()

        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(recorder.cancelCallCount, 1)
        XCTAssertEqual(recorder.stopCallCount, 0)
        XCTAssertEqual(transcriber.transcribeCallCount, 0)
        XCTAssertTrue(viewModel.history.isEmpty)
        XCTAssertEqual(viewModel.notice, "Recording too short. Hold on a little longer.")
    }

    func testStopRecordingIgnoredWhenNotRecording() async {
        await viewModel.prepare()

        await viewModel.stopRecording()

        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(recorder.stopCallCount, 0)
    }

    func testStopRecordingFailure() async {
        recorder.stopError = AppError.audioFileUnavailable

        await prepareAndStart()
        await viewModel.stopRecording()

        XCTAssertEqual(viewModel.state, .failed(.audioFileUnavailable))
        XCTAssertEqual(transcriber.transcribeCallCount, 0)
    }

    func testTranscriptionFailureDeletesFileAndKeepsHistory() async throws {
        let url = try makeTemporaryAudioFile()
        recorder.stopURL = url
        transcriber.transcribeError = AppError.transcriptionFailed

        await prepareAndStart()
        await viewModel.stopRecording()

        XCTAssertEqual(viewModel.state, .failed(.transcriptionFailed))
        XCTAssertTrue(viewModel.history.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testEmptyTranscription() async {
        transcriber.transcribeError = AppError.emptyTranscription

        await prepareAndStart()
        await viewModel.stopRecording()

        XCTAssertEqual(viewModel.state, .failed(.emptyTranscription))
    }

    // MARK: - Copy

    func testCopyEntryWritesToClipboard() async {
        await viewModel.prepare()
        await recordAndTranscribe("older")
        await recordAndTranscribe("newer")
        XCTAssertEqual(clipboard.copiedText, "newer")

        viewModel.copy(viewModel.history[1])

        XCTAssertEqual(clipboard.copiedText, "older")
    }

    func testFailedTranscriptionDoesNotTouchClipboard() async {
        transcriber.transcribeError = AppError.emptyTranscription

        await prepareAndStart()
        await viewModel.stopRecording()

        XCTAssertNil(clipboard.copiedText)
    }

    // MARK: - Open in ChatGPT

    func testOpenInChatGPTPassesEntryTextAndClearsNoticeWhenPasted() async {
        let entry = TranscriptionEntry(text: "Crie uma função Swift")

        await viewModel.openInChatGPT(entry)

        XCTAssertEqual(chatGPTLauncher.receivedTexts, ["Crie uma função Swift"])
        XCTAssertNil(viewModel.notice)
    }

    func testOpenInChatGPTShowsFallbackNoticeWithoutAccessibility() async {
        chatGPTLauncher.outcome = .copiedWithoutPaste

        await viewModel.openInChatGPT(TranscriptionEntry(text: "x"))

        XCTAssertEqual(viewModel.notice, "Copied. Enable Accessibility to paste automatically.")
    }

    func testOpenInChatGPTShowsErrorNotice() async {
        chatGPTLauncher.error = ChatGPTLauncherError.failedToOpenBrowser

        await viewModel.openInChatGPT(TranscriptionEntry(text: "x"))

        XCTAssertEqual(viewModel.notice, "ChatGPT could not be opened.")
    }

    // MARK: - Reset

    func testResetAfterRecordingErrorReturnsToReady() async {
        recorder.startError = AppError.recordingFailed
        await prepareAndStart()
        XCTAssertEqual(viewModel.state, .failed(.recordingFailed))

        viewModel.reset()

        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(viewModel.recordingDuration, 0)
    }

    func testResetAfterModelFailureRetriesPreparation() async {
        transcriber.prepareError = AppError.modelDownloadFailed
        await viewModel.prepare()
        XCTAssertEqual(viewModel.state, .failed(.modelDownloadFailed))

        transcriber.prepareError = nil
        viewModel.reset()

        for _ in 0..<50 where viewModel.state != .ready {
            await Task.yield()
        }
        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(transcriber.prepareCallCount, 2)
    }
}
