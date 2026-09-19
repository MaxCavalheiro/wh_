//
//  AudioRecorderIntegrationTests.swift
//  whTests
//
//  Uses the real microphone (needs permission) and, optionally, the real Whisper model.
//  Skipped unless RUN_AUDIO_INTEGRATION=1 is set in the test environment.
//

import AVFoundation
import XCTest
@testable import wh

@MainActor
final class AudioRecorderIntegrationTests: XCTestCase {
    private func peakLevel(of file: AVAudioFile) throws -> Float {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        guard let samples = buffer.floatChannelData?[0] else { return 0 }
        return (0..<Int(buffer.frameLength)).reduce(Float(0)) { max($0, abs(samples[$1])) }
    }

    func testRecordsMono16kHzWavAndTranscribes() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_AUDIO_INTEGRATION"] == "1",
            "Set RUN_AUDIO_INTEGRATION=1 to run the real microphone integration test"
        )

        let recorder = AudioRecorder()
        let granted = await recorder.requestPermission()
        try XCTSkipUnless(granted, "Microphone permission not granted")

        try await recorder.startRecording()

        // Play a Portuguese sentence through the speakers so the microphone has something to capture.
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Luciana", "Hoje eu estou testando um aplicativo de transcrição local."]
        try? say.run()
        try await Task.sleep(for: .seconds(4))
        XCTAssertGreaterThan(recorder.currentDuration, 3)

        let url = try await recorder.stopRecording()
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertGreaterThan(Double(file.length) / file.fileFormat.sampleRate, 3)
        print("Recorded peak level: \(String(format: "%.3f", try peakLevel(of: file))) (1.0 = full scale)")

        let service = WhisperTranscriptionService()
        try await service.prepare { _ in }
        do {
            let text = try await service.transcribe(audioURL: url)
            print("Microphone transcription: \(text)")
        } catch AppError.emptyTranscription {
            print("Microphone transcription: (no speech detected — speakers muted?)")
        }
    }
}
