//
//  MockAudioRecorder.swift
//  whTests
//

import Foundation
@testable import wh

@MainActor
final class MockAudioRecorder: AudioRecording {
    var permissionGranted = true
    var startError: Error?
    var stopError: Error?
    var stopURL = URL(fileURLWithPath: "/tmp/mock-recording.wav")
    var currentDuration: TimeInterval = 0

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var cancelCallCount = 0

    func requestPermission() async -> Bool {
        permissionGranted
    }

    func startRecording() async throws {
        startCallCount += 1
        if let startError { throw startError }
    }

    func cancelRecording() {
        cancelCallCount += 1
    }

    func stopRecording() async throws -> URL {
        stopCallCount += 1
        if let stopError { throw stopError }
        return stopURL
    }
}
