//
//  TranscriptionState.swift
//  wh
//

import Foundation

/// What model preparation is doing. The two phases look identical from outside but
/// behave very differently, so the panel has to name them apart.
enum ModelPreparation: Equatable {
    /// Fetching the model files. `progress` is the download fraction when known.
    case downloading(progress: Double?)
    /// CoreML compiling the model for this Mac's Neural Engine. It runs once after a
    /// download, can take several minutes and uses almost no CPU while it waits on the
    /// ANE, so without a message of its own it looks like the app froze.
    case optimizing
}

/// Single source of truth for what the panel and the menu bar icon show.
enum TranscriptionState: Equatable {
    /// Downloading or loading the speech model.
    case preparingModel(ModelPreparation)
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
        case .preparingModel(.downloading(let progress)):
            if let progress, progress > 0, progress < 1 {
                return "Downloading speech model… \(Int(progress * 100))%\nAbout 600 MB, downloaded once."
            }
            return "Downloading speech model…\nAbout 600 MB, downloaded once."
        case .preparingModel(.optimizing):
            return "Optimizing the model for your Mac.\nThis happens once and can take a few minutes."
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
