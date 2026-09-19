//
//  AppConfiguration.swift
//  wh
//

import Foundation

enum AppConfiguration {
    /// Whisper model variant to load. `nil` lets WhisperKit pick the recommended
    /// model for this machine (e.g. `openai_whisper-large-v3-v20240930_626MB` on Apple Silicon).
    /// Change to something like `"openai_whisper-base"` for a smaller/faster model.
    static let whisperModel: String? = nil

    /// Folder where downloaded models and tokenizers are cached between launches.
    static var modelCacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "WhisperModels", directoryHint: .isDirectory)
    }

    /// SwiftData database holding every transcription.
    static var databaseURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "Transcriptions.store")
    }

    /// Verbose WhisperKit logging is only useful during development.
    static var verboseWhisperLogging: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
