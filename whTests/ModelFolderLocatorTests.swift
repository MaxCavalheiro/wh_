//
//  ModelFolderLocatorTests.swift
//  whTests
//

import XCTest
@testable import wh

final class ModelFolderLocatorTests: XCTestCase {
    private var cache: URL!
    private var defaults: UserDefaults!
    private var locator: ModelFolderLocator!
    private let suite = "whTests.ModelFolderLocatorTests"

    override func setUpWithError() throws {
        try super.setUpWithError()
        cache = FileManager.default.temporaryDirectory.appending(path: "locator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
        locator = ModelFolderLocator(cacheDirectory: cache, defaults: defaults)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: cache)
        UserDefaults().removePersistentDomain(forName: suite)
        try super.tearDownWithError()
    }

    /// Mirrors how WhisperKit lays a downloaded model out.
    @discardableResult
    private func makeModel(_ variant: String, complete: Bool = true) throws -> URL {
        let folder = cache.appending(path: "models/argmaxinc/whisperkit-coreml/\(variant)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let parts = complete ? ModelFolderLocator.requiredParts : [ModelFolderLocator.requiredParts[0]]
        for part in parts {
            // .mlmodelc is itself a directory of weights.
            let compiled = folder.appending(path: part)
            try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
            try Data([0]).write(to: compiled.appending(path: "coremldata.bin"))
        }
        return folder
    }

    /// Compares by path: a located directory URL carries a trailing slash the literal does not.
    private func assertLocated(_ expected: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(locator.locate()?.standardizedFileURL.path, expected.standardizedFileURL.path,
                       file: file, line: line)
    }

    func testLocatesNothingWhenTheCacheIsEmpty() {
        XCTAssertNil(locator.locate())
    }

    func testLocatesTheRememberedFolder() throws {
        let folder = try makeModel("openai_whisper-base")
        locator.remember(folder)

        assertLocated(folder)
    }

    /// The bug this type exists for: the preference is lost when the app is killed before
    /// UserDefaults flushes, and the model must not be downloaded all over again.
    func testFindsADownloadedModelWhenThePreferenceIsMissing() throws {
        let folder = try makeModel("openai_whisper-large-v3-v20240930_626MB")

        XCTAssertNil(defaults.string(forKey: "whisper.modelFolder"))
        assertLocated(folder)
    }

    func testFallsBackToDiskWhenTheRememberedFolderIsGone() throws {
        let folder = try makeModel("openai_whisper-base")
        locator.remember(cache.appending(path: "models/deleted-variant"))

        assertLocated(folder)
    }

    func testIgnoresAHalfDownloadedFolder() throws {
        try makeModel("openai_whisper-base", complete: false)

        XCTAssertNil(locator.locate())
    }

    func testRememberAndForget() throws {
        let folder = try makeModel("openai_whisper-base")
        locator.remember(folder)
        XCTAssertEqual(defaults.string(forKey: "whisper.modelFolder"), folder.path)

        locator.forget()
        XCTAssertNil(defaults.string(forKey: "whisper.modelFolder"))
    }
}
