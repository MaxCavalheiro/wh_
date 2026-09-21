//
//  StatusItemClickPolicy.swift
//  wh
//

import Foundation

enum StatusItemClick: Equatable {
    case left
    case right
}

enum StatusItemAction: Equatable {
    case togglePanel
    case startRecording
    case stopRecording
}

/// Decides what a click on the menu bar icon does.
///
/// Normally any click toggles the panel. In fast mode a left click records directly —
/// start when idle, stop (and transcribe) while recording — and the right click is the
/// way into the panel. States that need the user's attention (errors, model loading,
/// transcribing) always open the panel so the feedback is visible.
enum StatusItemClickPolicy {
    static func action(for click: StatusItemClick, fastMode: Bool, state: TranscriptionState) -> StatusItemAction {
        guard fastMode, click == .left else { return .togglePanel }
        switch state {
        case .ready: return .startRecording
        case .recording: return .stopRecording
        case .preparingModel, .transcribing, .failed: return .togglePanel
        }
    }
}
