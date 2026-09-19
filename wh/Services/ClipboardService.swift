//
//  ClipboardService.swift
//  wh
//

import AppKit

@MainActor
protocol ClipboardWriting {
    func copy(_ text: String)
}

@MainActor
final class ClipboardService: ClipboardWriting {
    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
