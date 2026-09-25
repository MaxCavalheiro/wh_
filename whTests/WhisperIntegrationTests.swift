//
//  WhisperIntegrationTests.swift
//  whTests
//
//  Runs the real WhisperKit pipeline on a bundled Portuguese WAV file.
//  Slow (downloads the model on first run), so it is skipped unless
//  RUN_WHISPER_INTEGRATION=1 is set in the test environment.
//

import XCTest
@testable import wh

final class WhisperIntegrationTests: XCTestCase {
    func testTranscribesBundledPortugueseSample() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_WHISPER_INTEGRATION"] == "1",
            "Set RUN_WHISPER_INTEGRATION=1 to run the real WhisperKit integration test"
        )

        let bundle = Bundle(for: Self.self)
        let audioURL = try XCTUnwrap(
            bundle.url(forResource: "test-portuguese", withExtension: "wav"),
            "test-portuguese.wav missing from test bundle"
        )

        let service = WhisperTranscriptionService()
        try await service.prepare { phase in
            switch phase {
            case .downloading(let progress):
                print("model download: \(progress.map { "\(Int($0 * 100))%" } ?? "starting")")
            case .optimizing:
                print("compiling the model for this Mac…")
            }
        }

        let text = try await service.transcribe(audioURL: audioURL)
        print("Transcription: \(text)")

        // Spoken text: "Olá, este é um teste de transcrição usando WhisperKit."
        let normalized = text.lowercased()
        XCTAssertTrue(normalized.contains("teste"), "expected 'teste' in: \(text)")
        XCTAssertTrue(normalized.contains("transcrição") || normalized.contains("transcricao"), "expected 'transcrição' in: \(text)")
    }
}
