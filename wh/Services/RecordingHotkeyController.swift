//
//  RecordingHotkeyController.swift
//  wh
//

import AppKit
import Foundation
import KeyboardShortcuts
import os

extension KeyboardShortcuts.Name {
    /// Global shortcut that starts/stops recording from any app. Default: ⌥ Space.
    static let toggleRecording = Self("toggleRecording", default: .init(.space, modifiers: [.option]))
}

/// Listens for the global record shortcut and drives the view model with it.
///
/// Registered through Carbon hot keys (via KeyboardShortcuts), which work inside the App
/// Sandbox without Accessibility permission.
@MainActor
final class RecordingHotkeyController {
    private let viewModel: TranscriptionViewModel
    /// Called when a recording starts from the shortcut, so the user can see it happening.
    private let showPanel: () -> Void
    private let logger = AppLogger.app

    private var interpreter = HotkeyPressInterpreter()
    private var eventsTask: Task<Void, Never>?

    init(viewModel: TranscriptionViewModel, showPanel: @escaping () -> Void) {
        self.viewModel = viewModel
        self.showPanel = showPanel
    }

    deinit {
        eventsTask?.cancel()
    }

    func start() {
        guard eventsTask == nil else { return }
        eventsTask = Task { [weak self] in
            for await event in KeyboardShortcuts.events(for: .toggleRecording) {
                guard let self else { return }
                switch event {
                case .keyDown: handleKeyDown()
                case .keyUp: handleKeyUp()
                }
            }
        }
    }

    private func handleKeyDown() {
        switch viewModel.state {
        case .failed:
            viewModel.reset()
            return
        case .preparingModel, .transcribing:
            return
        case .ready, .recording:
            break
        }

        // Start/stop run detached so a quick release is still timed against the press,
        // not against however long the recorder took to spin up.
        switch interpreter.keyDown(isRecording: viewModel.state.isRecording) {
        case .startRecording:
            logger.info("Shortcut pressed: starting recording")
            showPanel()
            Task { await viewModel.startRecording() }
        case .stopRecording:
            logger.info("Shortcut tapped again: stopping recording")
            Task { await viewModel.stopRecording() }
        case .none:
            break
        }
    }

    private func handleKeyUp() {
        if interpreter.keyUp() == .stopRecording {
            logger.info("Shortcut released after hold: stopping recording")
            Task { await viewModel.stopRecording() }
        }
    }
}
