//
//  DurationFormatterTests.swift
//  whTests
//

import XCTest
@testable import wh

final class DurationFormatterTests: XCTestCase {
    func testFormatsMinutesAndSeconds() {
        XCTAssertEqual(DurationFormatter.string(from: 0), "00:00")
        XCTAssertEqual(DurationFormatter.string(from: 4.9), "00:04")
        XCTAssertEqual(DurationFormatter.string(from: 92), "01:32")
        XCTAssertEqual(DurationFormatter.string(from: 3599), "59:59")
    }

    func testNegativeDurationsClampToZero() {
        XCTAssertEqual(DurationFormatter.string(from: -5), "00:00")
    }
}
