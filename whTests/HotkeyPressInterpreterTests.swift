//
//  HotkeyPressInterpreterTests.swift
//  whTests
//

import XCTest
@testable import wh

final class HotkeyPressInterpreterTests: XCTestCase {
    private var interpreter: HotkeyPressInterpreter!
    private let t0 = ContinuousClock.now

    override func setUp() {
        super.setUp()
        interpreter = HotkeyPressInterpreter(holdThreshold: .milliseconds(300))
    }

    // MARK: - Hold (push-to-talk)

    func testHoldStartsOnPressAndStopsOnRelease() {
        XCTAssertEqual(interpreter.keyDown(isRecording: false, at: t0), .startRecording)
        XCTAssertEqual(interpreter.keyUp(at: t0 + .milliseconds(800)), .stopRecording)
    }

    func testReleaseExactlyAtThresholdCountsAsHold() {
        _ = interpreter.keyDown(isRecording: false, at: t0)
        XCTAssertEqual(interpreter.keyUp(at: t0 + .milliseconds(300)), .stopRecording)
    }

    // MARK: - Tap (hands-free)

    func testQuickTapStartsAndKeepsRecording() {
        XCTAssertEqual(interpreter.keyDown(isRecording: false, at: t0), .startRecording)
        XCTAssertEqual(interpreter.keyUp(at: t0 + .milliseconds(100)), .none)
    }

    func testSecondTapStopsRecording() {
        _ = interpreter.keyDown(isRecording: false, at: t0)
        _ = interpreter.keyUp(at: t0 + .milliseconds(100))

        XCTAssertEqual(interpreter.keyDown(isRecording: true, at: t0 + .seconds(5)), .stopRecording)
    }

    func testReleasingTheStoppingPressDoesNothingEvenWhenHeld() {
        _ = interpreter.keyDown(isRecording: false, at: t0)
        _ = interpreter.keyUp(at: t0 + .milliseconds(100))
        _ = interpreter.keyDown(isRecording: true, at: t0 + .seconds(5))

        // Holding the key on the second press must not emit a second stop.
        XCTAssertEqual(interpreter.keyUp(at: t0 + .seconds(6)), .none)
    }

    // MARK: - Robustness

    func testRepeatedKeyDownWhileHeldIsIgnored() {
        XCTAssertEqual(interpreter.keyDown(isRecording: false, at: t0), .startRecording)
        XCTAssertEqual(interpreter.keyDown(isRecording: true, at: t0 + .milliseconds(50)), .none)
        XCTAssertEqual(interpreter.keyDown(isRecording: true, at: t0 + .milliseconds(100)), .none)
        // The original press is still tracked, so releasing after the threshold stops.
        XCTAssertEqual(interpreter.keyUp(at: t0 + .milliseconds(500)), .stopRecording)
    }

    func testKeyUpWithoutKeyDownIsIgnored() {
        XCTAssertEqual(interpreter.keyUp(at: t0), .none)
    }

    func testPressAfterHoldStartsAgain() {
        _ = interpreter.keyDown(isRecording: false, at: t0)
        _ = interpreter.keyUp(at: t0 + .seconds(1))

        XCTAssertEqual(interpreter.keyDown(isRecording: false, at: t0 + .seconds(2)), .startRecording)
    }
}
