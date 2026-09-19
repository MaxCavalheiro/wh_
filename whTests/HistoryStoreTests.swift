//
//  HistoryStoreTests.swift
//  whTests
//

import XCTest
@testable import wh

@MainActor
final class HistoryStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "whTests.history"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeStore() throws -> SwiftDataHistoryStore {
        try SwiftDataHistoryStore(url: nil, legacyDefaults: nil)
    }

    func testFetchIsEmptyWhenNothingStored() throws {
        XCTAssertTrue(try makeStore().fetch(offset: 0, limit: 6).isEmpty)
    }

    func testFetchReturnsNewestFirstInPages() throws {
        let store = try makeStore()
        let base = Date(timeIntervalSince1970: 1_000_000)
        for i in 0..<8 {
            try store.insert(TranscriptionEntry(text: "entry \(i)", date: base.addingTimeInterval(Double(i) * 60)))
        }

        let firstPage = try store.fetch(offset: 0, limit: 6)
        let secondPage = try store.fetch(offset: 6, limit: 6)
        let thirdPage = try store.fetch(offset: 12, limit: 6)

        XCTAssertEqual(firstPage.map(\.text), ["entry 7", "entry 6", "entry 5", "entry 4", "entry 3", "entry 2"])
        XCTAssertEqual(secondPage.map(\.text), ["entry 1", "entry 0"])
        XCTAssertTrue(thirdPage.isEmpty)
    }

    func testRoundTripPreservesFields() throws {
        let store = try makeStore()
        let entry = TranscriptionEntry(text: "Olá", date: Date(timeIntervalSince1970: 1_700_000_000))

        try store.insert(entry)

        XCTAssertEqual(try store.fetch(offset: 0, limit: 1), [entry])
    }

    func testImportsLegacyUserDefaultsHistoryOnce() throws {
        let legacy = [
            TranscriptionEntry(text: "newer", date: Date(timeIntervalSince1970: 2_000)),
            TranscriptionEntry(text: "older", date: Date(timeIntervalSince1970: 1_000)),
        ]
        defaults.set(try JSONEncoder().encode(legacy), forKey: "transcription.history")

        let store = try SwiftDataHistoryStore(url: nil, legacyDefaults: defaults)

        XCTAssertEqual(try store.fetch(offset: 0, limit: 10), legacy)
        XCTAssertNil(defaults.data(forKey: "transcription.history"), "legacy data is removed after import")
    }
}
