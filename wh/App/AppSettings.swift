//
//  AppSettings.swift
//  wh
//

import Combine
import Foundation

/// User preferences shown in the panel's settings page, persisted in `UserDefaults`.
@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let showsQuickActions = "showsQuickActions"
        static let isFastModeEnabled = "isFastModeEnabled"
    }

    /// Whether the small action buttons next to each transcription's time (e.g. Open in
    /// ChatGPT) are visible. Off by default; it is an opt-in extra.
    @Published var showsQuickActions: Bool {
        didSet { defaults.set(showsQuickActions, forKey: Key.showsQuickActions) }
    }

    /// Fast mode: a left click on the menu bar icon starts/stops recording directly, without
    /// opening the panel; a right click opens it. See `StatusItemClickPolicy`.
    @Published var isFastModeEnabled: Bool {
        didSet { defaults.set(isFastModeEnabled, forKey: Key.isFastModeEnabled) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsQuickActions = defaults.object(forKey: Key.showsQuickActions) as? Bool ?? false
        isFastModeEnabled = defaults.object(forKey: Key.isFastModeEnabled) as? Bool ?? false
    }
}
