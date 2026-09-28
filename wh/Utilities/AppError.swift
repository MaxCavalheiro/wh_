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
    case noInternetConnection
    case downloadTimedOut
    case notEnoughDiskSpace
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
        case .noInternetConnection:
            return "No internet connection."
        case .downloadTimedOut:
            return "The download timed out."
        case .notEnoughDiskSpace:
            return "Not enough disk space for the speech model."
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
            return "Check your internet connection and try again. The download picks up where it left off."
        case .noInternetConnection:
            return "Reconnect and try again. The download picks up where it left off."
        case .downloadTimedOut:
            return "Your connection stalled — a video call or another big download can do that. Try again; it picks up where it left off."
        case .notEnoughDiskSpace:
            return "The model needs about 1.5 GB free. Free some space and try again."
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
    ///
    /// A failed download deserves the actual reason: "could not be downloaded" on its own
    /// leaves the user with nothing to act on.
    static func from(_ error: Error, fallback: AppError) -> AppError {
        if let appError = error as? AppError { return appError }
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
                return .noInternetConnection
            // The download stops after 10 seconds without data, so a connection that is
            // merely busy times out. Calling that "no internet" sends people looking for
            // a problem they do not have.
            case NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost:
                return .downloadTimedOut
            default:
                break
            }
        }
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileWriteOutOfSpaceError || nsError.code == NSFileWriteVolumeReadOnlyError {
            return .notEnoughDiskSpace
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOSPC) {
            return .notEnoughDiskSpace
        }
        return fallback
    }
}
