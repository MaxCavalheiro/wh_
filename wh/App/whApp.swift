//
//  whApp.swift
//  wh
//

import AppKit
import os
import SwiftUI

/// Menu bar only app (no windows, no Dock icon). The status item and popover are managed
/// in `AppDelegate`; this scene exists only because SwiftUI requires one.
@main
struct whApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            // Drop the "Settings…" (⌘,) menu item so it cannot open this empty window;
            // settings live inside the panel.
            .commands { CommandGroup(replacing: .appSettings) {} }
    }
}

/// Everything is wired up here once AppKit has finished launching.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewModel: TranscriptionViewModel?
    private var settings: AppSettings?
    private var statusItem: StatusItemController?
    private var hotkey: RecordingHotkeyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let clipboard = ClipboardService()
        let viewModel = TranscriptionViewModel(
            audioRecorder: AudioRecorder(),
            transcriptionService: WhisperTranscriptionService(),
            clipboard: clipboard,
            historyStore: Self.makeHistoryStore(),
            chatGPTLauncher: ChatGPTLauncherService(clipboard: clipboard)
        )
        let settings = AppSettings()
        let statusItem = StatusItemController(viewModel: viewModel, settings: settings)
        let hotkey = RecordingHotkeyController(viewModel: viewModel) { [weak statusItem] in
            statusItem?.showPopover()
        }

        self.viewModel = viewModel
        self.settings = settings
        self.statusItem = statusItem
        self.hotkey = hotkey

        // Skipped when the app is only hosting XCTest, so tests don't compete with the model
        // download or grab the global shortcut.
        guard !Self.isRunningTests else { return }
        hotkey.start()
        // Load the model as soon as the app launches so the icon is ready before the
        // panel is first opened.
        Task { await viewModel.prepare() }
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

    /// When the app is only acting as the XCTest host, keep it inert.
    private static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }
}
