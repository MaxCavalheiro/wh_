//
//  AppErrorTests.swift
//  whTests
//

import XCTest
@testable import wh

final class AppErrorTests: XCTestCase {
    func testEveryErrorHasAUserFacingDescription() {
        let all: [AppError] = [
            .microphonePermissionDenied, .microphoneUnavailable, .recordingFailed,
            .audioFileUnavailable, .modelInitializationFailed, .modelDownloadFailed,
            .modelNotReady, .transcriptionFailed, .emptyTranscription,
        ]
        for error in all {
            XCTAssertFalse(error.localizedDescription.isEmpty, "\(error) has no description")
        }
    }

    func testFromPreservesAppErrors() {
        XCTAssertEqual(AppError.from(AppError.emptyTranscription, fallback: .transcriptionFailed), .emptyTranscription)
    }

    func testFromMapsForeignErrorsToFallback() {
        let foreign = NSError(domain: "x", code: 1)
        XCTAssertEqual(AppError.from(foreign, fallback: .transcriptionFailed), .transcriptionFailed)
    }

    func testOnlyPermissionErrorOpensPrivacySettings() {
        XCTAssertTrue(AppError.microphonePermissionDenied.canOpenPrivacySettings)
        XCTAssertFalse(AppError.transcriptionFailed.canOpenPrivacySettings)
    }
}
