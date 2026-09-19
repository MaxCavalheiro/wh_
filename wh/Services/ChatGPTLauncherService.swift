//
//  ChatGPTLauncherService.swift
//  wh
//

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os

enum ChatGPTLauncherError: LocalizedError, Equatable {
    case emptyText
    case invalidURL
    case failedToOpenBrowser
    case pasteFailed

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "There is no transcription to open."
        case .invalidURL:
            return "The ChatGPT URL is invalid."
        case .failedToOpenBrowser:
            return "ChatGPT could not be opened."
        case .pasteFailed:
            return "The transcription was copied, but could not be pasted automatically."
        }
    }
}

/// What happened after ChatGPT was opened.
enum ChatGPTLaunchOutcome: Equatable {
    /// The text was pasted into the composer.
    case pasted
    /// Accessibility permission is missing: the text is on the clipboard, ChatGPT is open,
    /// but the user has to paste manually.
    case copiedWithoutPaste
}

@MainActor
protocol ChatGPTLaunching {
    func openInChatGPT(text: String) async throws -> ChatGPTLaunchOutcome
}

/// Copies the transcription, opens ChatGPT in the default browser and pastes with ⌘V.
/// Never sends the message.
@MainActor
final class ChatGPTLauncherService: ChatGPTLaunching {
    static let chatGPTURL = "https://chatgpt.com/"

    /// Time given to the browser to come to the front and load the composer before pasting.
    private let browserPasteDelay: Duration
    private let clipboard: any ClipboardWriting
    private let logger = AppLogger.app

    init(clipboard: any ClipboardWriting, browserPasteDelay: Duration = .seconds(1.2)) {
        self.clipboard = clipboard
        self.browserPasteDelay = browserPasteDelay
    }

    func openInChatGPT(text: String) async throws -> ChatGPTLaunchOutcome {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ChatGPTLauncherError.emptyText }
        guard let url = URL(string: Self.chatGPTURL) else { throw ChatGPTLauncherError.invalidURL }

        clipboard.copy(text)

        // Prompts the user (once) to enable the app under Privacy & Security › Accessibility.
        let trusted = Self.ensureAccessibilityPermission()
        logger.info("Accessibility permission \(trusted ? "granted" : "missing")")

        guard NSWorkspace.shared.open(url) else {
            throw ChatGPTLauncherError.failedToOpenBrowser
        }
        logger.info("Opened ChatGPT in the default browser")

        guard trusted else { return .copiedWithoutPaste }

        try await Task.sleep(for: browserPasteDelay)
        // If our own panel somehow still has focus, give the browser one more moment.
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
            try await Task.sleep(for: browserPasteDelay)
        }

        guard Self.pasteClipboard() else { throw ChatGPTLauncherError.pasteFailed }
        logger.info("Pasted transcription into ChatGPT")
        return .pasted
    }

    // MARK: - Accessibility

    private static func ensureAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() { return true }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Keyboard simulation

    /// Sends ⌘V to the frontmost application. Returns `false` if the events could not be created.
    private static func pasteClipboard() -> Bool {
        let keyV: CGKeyCode = 9  // kVK_ANSI_V
        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        else { return false }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
