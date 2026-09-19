//
//  MockClipboard.swift
//  whTests
//

import Foundation
@testable import wh

@MainActor
final class MockClipboard: ClipboardWriting {
    private(set) var copiedText: String?

    func copy(_ text: String) {
        copiedText = text
    }
}
