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

    // MARK: - Mapping real framework errors

    func testMapsOfflineErrorsToNoInternetConnection() {
        for code in [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
                     NSURLErrorTimedOut, NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed] {
            let error = NSError(domain: NSURLErrorDomain, code: code)
            XCTAssertEqual(AppError.from(error, fallback: .modelDownloadFailed), .noInternetConnection, "code \(code)")
        }
    }

    func testMapsOutOfSpaceErrorsToNotEnoughDiskSpace() {
        let cocoa = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        XCTAssertEqual(AppError.from(cocoa, fallback: .modelDownloadFailed), .notEnoughDiskSpace)

        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        XCTAssertEqual(AppError.from(posix, fallback: .modelDownloadFailed), .notEnoughDiskSpace)
    }

    func testKeepsTheFallbackForAnUnrecognisedError() {
        let error = NSError(domain: "SomeFramework", code: 42)
        XCTAssertEqual(AppError.from(error, fallback: .modelDownloadFailed), .modelDownloadFailed)
    }

    func testDownloadFailuresExplainWhatToDo() {
        for error: AppError in [.modelDownloadFailed, .noInternetConnection, .notEnoughDiskSpace] {
            XCTAssertNotNil(error.recoverySuggestion, "\(error) must tell the user what to do")
        }
    }
}
