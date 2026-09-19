//
//  HistoryStore.swift
//  wh
//

import Foundation
import os
import SwiftData

/// Persistent store of every transcription, newest first, read in pages.
@MainActor
protocol HistoryStoring {
    func insert(_ entry: TranscriptionEntry) throws
    /// Returns up to `limit` entries sorted by date descending, skipping the first `offset`.
    func fetch(offset: Int, limit: Int) throws -> [TranscriptionEntry]
}

/// SwiftData-backed history stored in the app's Application Support folder.
@MainActor
final class SwiftDataHistoryStore: HistoryStoring {
    private let container: ModelContainer
    private let logger = AppLogger.app

    private var context: ModelContext { container.mainContext }

    /// - Parameters:
    ///   - url: Database file location. `nil` keeps everything in memory (tests/previews).
    ///   - legacyDefaults: Where the pre-SwiftData history lived; imported once, then removed.
    init(url: URL? = AppConfiguration.databaseURL, legacyDefaults: UserDefaults? = .standard) throws {
        let schema = Schema([TranscriptionRecord.self])
        let configuration: ModelConfiguration
        if let url {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            configuration = ModelConfiguration(schema: schema, url: url)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }
        container = try ModelContainer(for: schema, configurations: [configuration])

        if let legacyDefaults {
            importLegacyHistory(from: legacyDefaults)
        }
    }

    func insert(_ entry: TranscriptionEntry) throws {
        context.insert(TranscriptionRecord(id: entry.id, text: entry.text, date: entry.date))
        try context.save()
    }

    func fetch(offset: Int, limit: Int) throws -> [TranscriptionEntry] {
        var descriptor = FetchDescriptor<TranscriptionRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).map(\.entry)
    }

    // MARK: - Migration

    private static let legacyKey = "transcription.history"

    /// Moves the JSON history kept in UserDefaults by earlier builds into the database.
    private func importLegacyHistory(from defaults: UserDefaults) {
        guard let data = defaults.data(forKey: Self.legacyKey) else { return }
        defer { defaults.removeObject(forKey: Self.legacyKey) }

        guard let entries = try? JSONDecoder().decode([TranscriptionEntry].self, from: data) else { return }
        for entry in entries {
            context.insert(TranscriptionRecord(id: entry.id, text: entry.text, date: entry.date))
        }
        do {
            try context.save()
            logger.info("Imported \(entries.count) legacy history entries")
        } catch {
            logger.error("Legacy history import failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Last-resort store used when no database can be opened at all.
@MainActor
struct EmptyHistoryStore: HistoryStoring {
    func insert(_ entry: TranscriptionEntry) throws {}
    func fetch(offset: Int, limit: Int) throws -> [TranscriptionEntry] { [] }
}
