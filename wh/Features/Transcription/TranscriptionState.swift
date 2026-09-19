//
//  TranscriptionState.swift
//  wh
//

import Foundation

/// Single source of truth for what the panel and the menu bar icon show.
enum TranscriptionState: Equatable {
    /// Downloading/loading the speech model. `progress` is the download fraction when known.
    case preparingModel(progress: Double?)
    case ready
    case recording
    case transcribing
    case failed(AppError)

    var isPreparingModel: Bool {
        if case .preparingModel = self { return true }
        return false
    }

    var isRecording: Bool { self == .recording }

    var isBusy: Bool {
        switch self {
        case .preparingModel, .transcribing: return true
        default: return false
        }
    }

    /// Short status line shown under the record button; `nil` when the controls speak for themselves.
    var statusText: String? {
        switch self {
        case .preparingModel(let progress):
            if let progress, progress > 0, progress < 1 {
                return "Downloading speech model… \(Int(progress * 100))%"
            }
            return "Preparing speech model…"
        case .ready, .recording:
            return nil
        case .transcribing:
            return "Transcribing…"
        case .failed(let error):
            return error.errorDescription ?? "Something went wrong."
        }
    }

    /// SF Symbol used for the status bar item.
    var menuBarSymbol: String {
        switch self {
        case .preparingModel, .transcribing: return "ellipsis.circle"
        case .ready: return "mic"
        case .recording: return "record.circle.fill"
        case .failed: return "mic.slash"
        }
    }
}
