//
//  TranscriptionEntry.swift
//  wh
//

import Foundation

/// One finished transcription shown in the menu bar panel history.
struct TranscriptionEntry: Identifiable, Equatable, Codable {
    let id: UUID
    let text: String
    let date: Date

    init(id: UUID = UUID(), text: String, date: Date = .now) {
        self.id = id
        self.text = text
        self.date = date
    }
}
