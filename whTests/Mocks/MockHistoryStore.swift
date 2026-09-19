//
//  MockHistoryStore.swift
//  whTests
//

import Foundation
@testable import wh

@MainActor
final class MockHistoryStore: HistoryStoring {
    /// Newest first, mirroring what the real store returns.
    var stored: [TranscriptionEntry] = []
    var fetchError: Error?
    private(set) var insertCallCount = 0
    private(set) var fetchCalls: [(offset: Int, limit: Int)] = []

    func insert(_ entry: TranscriptionEntry) throws {
        insertCallCount += 1
        stored.insert(entry, at: 0)
    }

    func fetch(offset: Int, limit: Int) throws -> [TranscriptionEntry] {
        fetchCalls.append((offset, limit))
        if let fetchError { throw fetchError }
        guard offset < stored.count else { return [] }
        return Array(stored[offset..<min(offset + limit, stored.count)])
    }
}
