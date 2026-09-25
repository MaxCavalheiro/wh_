//
//  StatusItemController.swift
//  wh
//

import AppKit
import Combine
import SwiftUI

/// Owns the menu bar icon and the popover that hosts `MenuBarPanelView`.
///
/// Replaces SwiftUI's `MenuBarExtra`, which offers no way to open its panel from code —
/// needed so the panel can appear when a recording starts from the global shortcut or
/// finishes in fast mode.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let viewModel: TranscriptionViewModel
    private let settings: AppSettings
    let statusItem: NSStatusItem  // internal so tests can click it
    let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    /// A transient popover closes with an animation on the click that also reaches the
    /// status button. Showing it again during that animation is a no-op, so the request
    /// is remembered and honoured in `popoverDidClose`.
    private var isClosing = false
    private var showsAgainWhenClosed = false
    /// The panel is opened once when a model download starts, so a first launch does not
    /// spend several minutes downloading with nothing on screen to say so.
    private var hasAnnouncedDownload = false

    init(viewModel: TranscriptionViewModel, settings: AppSettings) {
        self.viewModel = viewModel
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let host = NSHostingController(
            rootView: MenuBarPanelView(viewModel: viewModel).environmentObject(settings)
        )
        // Let the popover follow the SwiftUI layout instead of a fixed content size.
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Local Transcription")
        }

        // `@Published` emits before the property is set. Swapping the icon relayouts the
        // status bar and the popover anchored to it synchronously, which makes SwiftUI
        // re-read the *old* state and then miss the new one (the panel would keep showing
        // "Transcribing…" after the result arrived). Hop to the next run loop turn first.
        viewModel.$state
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateIcon(for: state)
                self?.announceDownloadIfNeeded(state)
            }
            .store(in: &cancellables)

        settings.$isFastModeEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in self?.updateToolTip(fastMode: enabled) }
            .store(in: &cancellables)
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            if isClosing { showsAgainWhenClosed = true }
            return
        }
        // Activate first and make the popover key right away: otherwise the first click
        // inside it only focuses the window, and copying a transcription takes two clicks.
        // Being key is also what makes its shortcuts (Esc, ⌘Q, ⌘,) work.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
    }

    func closePopover() {
        showsAgainWhenClosed = false
        popover.performClose(nil)
    }

    nonisolated func popoverWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { isClosing = true }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            isClosing = false
            if showsAgainWhenClosed {
                showsAgainWhenClosed = false
                showPopover()
            }
        }
    }

    private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    // MARK: - Clicks

    @objc private func statusItemClicked() {
        let click: StatusItemClick = NSApp.currentEvent?.type == .rightMouseUp ? .right : .left

        switch StatusItemClickPolicy.action(for: click, fastMode: settings.isFastModeEnabled, state: viewModel.state) {
        case .togglePanel:
            togglePopover()
        case .startRecording:
            Task { await viewModel.startRecording() }
        case .stopRecording:
            // Open the panel right away so "Transcribing…" and then the result are visible.
            showPopover()
            Task { await viewModel.stopRecording() }
        }
    }

    /// Shows the panel the first time a download reports progress. A model already on
    /// disk never reports progress, so a normal launch is left alone.
    private func announceDownloadIfNeeded(_ state: TranscriptionState) {
        guard !hasAnnouncedDownload,
              case .preparingModel(.downloading(let progress)) = state,
              progress != nil else { return }
        hasAnnouncedDownload = true
        showPopover()
    }

    // MARK: - Icon

    private func updateIcon(for state: TranscriptionState) {
        statusItem.button?.image = state.isRecording ? Self.recordingImage : Self.templateImage(state.menuBarSymbol)
    }

    private static func templateImage(_ symbol: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Local Transcription")
        image?.isTemplate = true
        return image
    }

    /// Red circle with a white stop square, the same stop button the panel shows while
    /// recording. Drawn by hand on a canvas as tall as the status bar button (22pt), so
    /// its centre is the button's centre regardless of AppKit's image alignment, with
    /// every edge on a whole Retina pixel. Not a template image so the red survives.
    private static let recordingImage: NSImage = {
        let side: CGFloat = 22
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5)).fill()  // 19pt circle

            let square: CGFloat = 8
            let squareRect = NSRect(x: (side - square) / 2, y: (side - square) / 2, width: square, height: square)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: squareRect, xRadius: 1.5, yRadius: 1.5).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Recording"
        return image
    }()

    private func updateToolTip(fastMode: Bool) {
        statusItem.button?.toolTip = fastMode
            ? "Click to record, click again to transcribe. Right-click to open."
            : "Local Transcription"
    }
}
