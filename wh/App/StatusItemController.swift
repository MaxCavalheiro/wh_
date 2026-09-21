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
/// needed so the panel can appear when a recording starts from the global shortcut.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: TranscriptionViewModel, settings: AppSettings) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let host = NSHostingController(
            rootView: MenuBarPanelView(viewModel: viewModel).environmentObject(settings)
        )
        // Let the popover follow the SwiftUI layout instead of a fixed content size.
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("Local Transcription")
        }

        viewModel.$state
            .map(\.menuBarSymbol)
            .removeDuplicates()
            .sink { [weak self] symbol in self?.updateIcon(symbol) }
            .store(in: &cancellables)
    }

    func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // The popover must be key for its keyboard shortcuts (Esc, ⌘Q, ⌘,) to work.
        NSApp.activate()
    }

    func closePopover() {
        popover.performClose(nil)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func updateIcon(_ symbol: String) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Local Transcription")
        image?.isTemplate = true
        statusItem.button?.image = image
    }
}
