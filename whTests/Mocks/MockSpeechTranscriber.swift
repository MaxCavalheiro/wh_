//
//  MockSpeechTranscriber.swift
//  whTests
//

import Foundation
@testable import wh

/// Thread-safe mock so it can satisfy the `Sendable` requirement of `SpeechTranscribing`.
final class MockSpeechTranscriber: SpeechTranscribing, @unchecked Sendable {
    private let lock = NSLock()

    private var _prepareError: Error?
    private var _transcribeError: Error?
    private var _transcriptionText = "mock transcription"
    private var _progressUpdates: [Double] = []
    private var _prepareCallCount = 0
    private var _transcribeCallCount = 0
    private var _lastAudioURL: URL?

    var prepareError: Error? {
        get { lock.withLock { _prepareError } }
        set { lock.withLock { _prepareError = newValue } }
    }
    var transcribeError: Error? {
        get { lock.withLock { _transcribeError } }
        set { lock.withLock { _transcribeError = newValue } }
    }
    var transcriptionText: String {
        get { lock.withLock { _transcriptionText } }
        set { lock.withLock { _transcriptionText = newValue } }
    }
    /// Progress values the mock will emit during `prepare`.
    var progressUpdates: [Double] {
        get { lock.withLock { _progressUpdates } }
        set { lock.withLock { _progressUpdates = newValue } }
    }
    var prepareCallCount: Int { lock.withLock { _prepareCallCount } }
    var transcribeCallCount: Int { lock.withLock { _transcribeCallCount } }
    var lastAudioURL: URL? { lock.withLock { _lastAudioURL } }

    func prepare(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        lock.withLock { _prepareCallCount += 1 }
        for value in progressUpdates {
            onProgress(value)
            await Task.yield()
        }
        if let prepareError { throw prepareError }
    }

    func transcribe(audioURL: URL) async throws -> String {
        lock.withLock {
            _transcribeCallCount += 1
            _lastAudioURL = audioURL
        }
        if let transcribeError { throw transcribeError }
        return transcriptionText
    }
}
