//
//  HotkeyPressInterpreter.swift
//  wh
//

import Foundation

/// Turns raw key down/up events of the record shortcut into recording actions.
///
/// Two gestures share one shortcut, with no mode to configure:
/// - **Hold**: press starts recording; releasing after `holdThreshold` stops it (push-to-talk).
/// - **Tap**: press starts recording; releasing quickly keeps it going. The next tap stops it.
struct HotkeyPressInterpreter {
    enum Action: Equatable {
        case startRecording
        case stopRecording
        case none
    }

    /// Presses at least this long count as "hold", so releasing stops the recording.
    let holdThreshold: Duration

    init(holdThreshold: Duration = .milliseconds(300)) {
        self.holdThreshold = holdThreshold
    }

    private var pressedAt: ContinuousClock.Instant?
    /// Whether the current press is the one that started the recording. Only that press
    /// can turn into a hold; the press that stops a recording does nothing on release.
    private var pressStartedRecording = false

    mutating func keyDown(isRecording: Bool, at now: ContinuousClock.Instant = .now) -> Action {
        // Ignore key repeat and duplicate events while the key is still down.
        guard pressedAt == nil else { return .none }
        pressedAt = now
        pressStartedRecording = !isRecording
        return isRecording ? .stopRecording : .startRecording
    }

    mutating func keyUp(at now: ContinuousClock.Instant = .now) -> Action {
        guard let pressedAt else { return .none }
        self.pressedAt = nil
        guard pressStartedRecording, now - pressedAt >= holdThreshold else { return .none }
        return .stopRecording
    }
}
