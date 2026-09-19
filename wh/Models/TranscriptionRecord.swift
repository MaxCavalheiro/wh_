//
//  TranscriptionRecord.swift
//  wh
//

import Foundation
import SwiftData

/// SwiftData row for one finished transcription. Only the text and its date are stored;
/// audio is never persisted.
@Model
final class TranscriptionRecord {
    @Attribute(.unique) var id: UUID
    var text: String
    var date: Date

    init(id: UUID = UUID(), text: String, date: Date = .now) {
        self.id = id
        self.text = text
        self.date = date
    }

    var entry: TranscriptionEntry {
        TranscriptionEntry(id: id, text: text, date: date)
    }
}
