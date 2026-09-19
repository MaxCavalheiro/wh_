//
//  HistorySectionTests.swift
//  whTests
//

import XCTest
@testable import wh

final class HistorySectionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return calendar
    }

    private func date(_ day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    func testGroupsConsecutiveEntriesByDay() {
        let entries = [
            TranscriptionEntry(text: "c", date: date(19, hour: 15)),
            TranscriptionEntry(text: "b", date: date(19, hour: 9)),
            TranscriptionEntry(text: "a", date: date(18, hour: 23)),
        ]

        let sections = HistorySection.group(entries, calendar: calendar)

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].day, calendar.startOfDay(for: date(19, hour: 0)))
        XCTAssertEqual(sections[0].entries.map(\.text), ["c", "b"])
        XCTAssertEqual(sections[1].entries.map(\.text), ["a"])
    }

    func testEmptyInputProducesNoSections() {
        XCTAssertTrue(HistorySection.group([], calendar: calendar).isEmpty)
    }
}
