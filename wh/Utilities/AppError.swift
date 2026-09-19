//
//  AppError.swift
//  wh
//

import Foundation

/// User-facing errors. Low-level framework errors are logged and mapped to one of these
/// so the UI never shows raw AVFoundation / WhisperKit messages.
enum AppError: LocalizedError, Equatable {
    case microphonePermissionDenied
    case microphoneUnavailable
    case recordingFailed
    case audioFileUnavailable
    case modelInitializationFailed
    case modelDownloadFailed
    case modelNotReady
    case transcriptionFailed
    case emptyTranscription

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is required to record audio."
        case .microphoneUnavailable:
            return "No microphone is available."
        case .recordingFailed:
            return "The audio recording could not be completed."
        case .audioFileUnavailable:
            return "The recorded audio file is unavailable."
        case .modelInitializationFailed:
            return "The speech recognition model could not be initialized."
        case .modelDownloadFailed:
            return "The speech recognition model could not be downloaded."
        case .modelNotReady:
            return "The speech recognition model is not ready."
        case .transcriptionFailed:
            return "The audio could not be transcribed."
        case .emptyTranscription:
            return "No speech was detected."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Enable microphone access for this app in System Settings › Privacy & Security › Microphone."
        case .modelDownloadFailed:
            return "Check your internet connection and try again. The model is only downloaded once."
        case .emptyTranscription:
            return "Try recording again and speak closer to the microphone."
        default:
            return nil
        }
    }

    /// Whether the error is fixable by opening the macOS privacy settings.
    var canOpenPrivacySettings: Bool {
        self == .microphonePermissionDenied
    }

    /// Maps any thrown error to an `AppError`, preserving it when it already is one.
    static func from(_ error: Error, fallback: AppError) -> AppError {
        (error as? AppError) ?? fallback
    }
}
