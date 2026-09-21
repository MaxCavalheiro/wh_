//
//  AppSettingsTests.swift
//  whTests
//

import XCTest
@testable import wh

@MainActor
final class AppSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "whTests.AppSettingsTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testQuickActionsAreHiddenByDefault() {
        XCTAssertFalse(AppSettings(defaults: defaults).showsQuickActions)
    }

    func testQuickActionsPreferencePersists() {
        AppSettings(defaults: defaults).showsQuickActions = true

        XCTAssertTrue(AppSettings(defaults: defaults).showsQuickActions)
    }
}
