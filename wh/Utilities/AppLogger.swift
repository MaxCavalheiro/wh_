//
//  AppLogger.swift
//  wh
//

import Foundation
import os

/// Lifecycle loggers, one per layer. Never log the full transcription in production.
enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "wh"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let whisper = Logger(subsystem: subsystem, category: "whisper")
    static let viewModel = Logger(subsystem: subsystem, category: "viewmodel")
}
