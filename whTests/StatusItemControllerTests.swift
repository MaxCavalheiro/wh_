//
//  StatusItemControllerTests.swift
//  whTests
//
//  Drives the real status item and popover. Regression tests for the panel keeping a
//  stale "Transcribing…" spinner after a fast mode recording finished.
//

import AppKit
import XCTest
@testable import wh

@MainActor
final class StatusItemControllerTests: XCTestCase {
    private var controller: StatusItemController!
    private var viewModel: TranscriptionViewModel!
    private var transcriber: MockSpeechTranscriber!
    private var hostView: NSView!
    private var button: NSStatusBarButton!
    private let suite = "whTests.StatusItemControllerTests"

    override func setUp() async throws {
        try await super.setUp()
        transcriber = MockSpeechTranscriber()
        transcriber.transcribeDelay = .seconds(1.5)
        viewModel = TranscriptionViewModel(
            audioRecorder: MockAudioRecorder(),
            transcriptionService: transcriber,
            clipboard: MockClipboard(),
            historyStore: MockHistoryStore(),
            chatGPTLauncher: MockChatGPTLauncher()
        )
        UserDefaults().removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.isFastModeEnabled = true

        // The real app builds the status item before preparing the model; preparing first
        // would leave a notice animating into a panel that has no window yet.
        controller = StatusItemController(viewModel: viewModel, settings: settings)
        await viewModel.prepare()
        button = try XCTUnwrap(controller.statusItem.button)
        hostView = try XCTUnwrap(controller.popover.contentViewController?.view)
        await settle()
    }

    override func tearDown() async throws {
        controller.popover.close()
        NSStatusBar.system.removeStatusItem(controller.statusItem)
        UserDefaults().removePersistentDomain(forName: suite)
        controller = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Lets AppKit animate and SwiftUI render.
    private func settle(_ seconds: TimeInterval = 0.4) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// SwiftUI's `ProgressView` is an `NSProgressIndicator` underneath, so the busy
    /// spinner can be found in the AppKit hierarchy.
    private func spinnerCount(in view: NSView) -> Int {
        (view is NSProgressIndicator ? 1 : 0) + view.subviews.reduce(0) { $0 + spinnerCount(in: $1) }
    }

    /// The settings page is the only one with a shortcut recorder (an `NSSearchField`).
    private func isOnSettingsPage() -> Bool {
        func contains(_ view: NSView) -> Bool {
            view is NSSearchField || view.subviews.contains(where: contains)
        }
        return contains(hostView)
    }

    private func sendKey(_ keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = []) throws {
        let window = try XCTUnwrap(hostView.window)
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        ))
        window.sendEvent(event)
    }

    // MARK: - Tests

    func testPanelReopensOnTheMainPageAfterLeavingItOnSettings() async throws {
        controller.showPopover()
        await settle()
        try sendKey(43, characters: ",", modifiers: [.command])
        await settle()
        XCTAssertTrue(isOnSettingsPage())

        controller.popover.performClose(nil)
        await settle()
        controller.showPopover()
        await settle()

        XCTAssertFalse(isOnSettingsPage())
    }

    func testFastModeClicksRecordThenTranscribeAndOpenThePanel() async {
        controller.showPopover()
        await settle()
        controller.popover.performClose(nil)
        await settle()

        button.performClick(nil)
        await settle()
        XCTAssertEqual(viewModel.state, .recording)
        XCTAssertFalse(controller.popover.isShown)

        button.performClick(nil)
        await settle()
        XCTAssertEqual(viewModel.state, .transcribing)
        XCTAssertTrue(controller.popover.isShown)
        XCTAssertEqual(spinnerCount(in: hostView), 1)

        await settle(1.5)
        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(viewModel.history.count, 1)
        XCTAssertEqual(spinnerCount(in: hostView), 0, "spinner must go away once the result is in")
    }

    func testSpinnerClearsWhenStopIsTriggeredFromTheSettingsPage() async throws {
        controller.showPopover()
        await settle()
        try sendKey(43, characters: ",", modifiers: [.command])  // ⌘, → settings page
        await settle()

        // Start: the click closes the transient popover and records.
        controller.popover.performClose(nil)
        button.performClick(nil)
        await settle()
        XCTAssertEqual(viewModel.state, .recording)

        // Stop: the panel reopens (still on settings) while transcribing.
        button.performClick(nil)
        await settle()
        XCTAssertEqual(viewModel.state, .transcribing)
        XCTAssertTrue(controller.popover.isShown)

        try sendKey(53, characters: "\u{1B}")  // Esc → back to the main page
        await settle()
        XCTAssertEqual(spinnerCount(in: hostView), 1)

        await settle(1.5)
        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(spinnerCount(in: hostView), 0)
    }
}
