//
//  DurationFormatter.swift
//  wh
//

import Foundation

enum DurationFormatter {
    /// Formats a duration as `MM:SS` (e.g. `00:04`, `01:32`).
    static func string(from duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
