//
//  StatusItemClickPolicyTests.swift
//  whTests
//

import XCTest
@testable import wh

final class StatusItemClickPolicyTests: XCTestCase {
    func testAnyClickTogglesPanelWhenFastModeIsOff() {
        for state: TranscriptionState in [.ready, .recording, .transcribing, .preparingModel(progress: nil), .failed(.recordingFailed)] {
            XCTAssertEqual(StatusItemClickPolicy.action(for: .left, fastMode: false, state: state), .togglePanel, "\(state)")
            XCTAssertEqual(StatusItemClickPolicy.action(for: .right, fastMode: false, state: state), .togglePanel, "\(state)")
        }
    }

    func testFastModeLeftClickStartsWhenReady() {
        XCTAssertEqual(StatusItemClickPolicy.action(for: .left, fastMode: true, state: .ready), .startRecording)
    }

    func testFastModeLeftClickStopsWhileRecording() {
        XCTAssertEqual(StatusItemClickPolicy.action(for: .left, fastMode: true, state: .recording), .stopRecording)
    }

    func testFastModeLeftClickOpensPanelWhenAttentionIsNeeded() {
        for state: TranscriptionState in [.transcribing, .preparingModel(progress: 0.5), .failed(.microphonePermissionDenied)] {
            XCTAssertEqual(StatusItemClickPolicy.action(for: .left, fastMode: true, state: state), .togglePanel, "\(state)")
        }
    }

    func testFastModeRightClickAlwaysTogglesPanel() {
        XCTAssertEqual(StatusItemClickPolicy.action(for: .right, fastMode: true, state: .ready), .togglePanel)
        XCTAssertEqual(StatusItemClickPolicy.action(for: .right, fastMode: true, state: .recording), .togglePanel)
    }
}
