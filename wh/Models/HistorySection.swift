//
//  HistorySection.swift
//  wh
//

import Foundation

/// Transcriptions of a single calendar day, newest first.
struct HistorySection: Identifiable, Equatable {
    /// Start of the day in the current calendar.
    let day: Date
    var entries: [TranscriptionEntry]

    var id: Date { day }

    /// Groups already-sorted (newest first) entries into consecutive day sections.
    static func group(_ entries: [TranscriptionEntry], calendar: Calendar = .current) -> [HistorySection] {
        var sections: [HistorySection] = []
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            if sections.last?.day == day {
                sections[sections.count - 1].entries.append(entry)
            } else {
                sections.append(HistorySection(day: day, entries: [entry]))
            }
        }
        return sections
    }
}
