//
//  whApp.swift
//  wh
//
//  Created by Max Cavalheiro on 18/09/26.
//

import os
import SwiftUI

@main
struct whApp: App {
    @StateObject private var viewModel: TranscriptionViewModel

    init() {
        let clipboard = ClipboardService()
        let viewModel = TranscriptionViewModel(
            audioRecorder: AudioRecorder(),
            transcriptionService: WhisperTranscriptionService(),
            clipboard: clipboard,
            historyStore: Self.makeHistoryStore(),
            chatGPTLauncher: ChatGPTLauncherService(clipboard: clipboard)
        )
        _viewModel = StateObject(wrappedValue: viewModel)

        // Load the model as soon as the app launches so the icon is ready before the
        // panel is first opened. Skipped when the app is only hosting XCTest.
        if !Self.isRunningTests {
            Task { await viewModel.prepare() }
        }
    }

    /// Opens the on-disk database, falling back to an in-memory one so the app still
    /// works (without persistence) if the file cannot be opened.
    private static func makeHistoryStore() -> any HistoryStoring {
        do {
            return try SwiftDataHistoryStore()
        } catch {
            AppLogger.app.error("Could not open history database: \(error.localizedDescription, privacy: .public)")
            return (try? SwiftDataHistoryStore(url: nil, legacyDefaults: nil)) ?? EmptyHistoryStore()
        }
    }

    /// When the app is only acting as the XCTest host, keep it inert so it does not
    /// download/load the model concurrently with the tests.
    private static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanelView(viewModel: viewModel)
        } label: {
            Image(systemName: viewModel.state.menuBarSymbol)
                .accessibilityLabel("Local Transcription")
        }
        .menuBarExtraStyle(.window)
    }
}
