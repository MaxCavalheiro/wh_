//
//  MockChatGPTLauncher.swift
//  whTests
//

import Foundation
@testable import wh

@MainActor
final class MockChatGPTLauncher: ChatGPTLaunching {
    var outcome: ChatGPTLaunchOutcome = .pasted
    var error: Error?
    private(set) var receivedTexts: [String] = []

    func openInChatGPT(text: String) async throws -> ChatGPTLaunchOutcome {
        receivedTexts.append(text)
        if let error { throw error }
        return outcome
    }
}
