//
//  ChatGPTLauncherServiceTests.swift
//  whTests
//

import XCTest
@testable import wh

@MainActor
final class ChatGPTLauncherServiceTests: XCTestCase {
    func testEmptyTextDoesNotTouchClipboardOrBrowser() async {
        let clipboard = MockClipboard()
        let service = ChatGPTLauncherService(clipboard: clipboard)

        do {
            _ = try await service.openInChatGPT(text: "   \n")
            XCTFail("expected emptyText error")
        } catch let error as ChatGPTLauncherError {
            XCTAssertEqual(error, .emptyText)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertNil(clipboard.copiedText)
    }

    func testChatGPTURLIsValid() {
        XCTAssertEqual(URL(string: ChatGPTLauncherService.chatGPTURL)?.host, "chatgpt.com")
    }
}
