//
//  ModelFolderLocator.swift
//  wh
//

import Foundation
import os

/// Finds the downloaded speech model on disk.
///
/// The path is remembered in `UserDefaults`, but that preference can go missing while the
/// files are still there — it is lost whenever the app is killed before `UserDefaults`
/// flushes, which is easy during the minutes-long model preparation. Re-downloading
/// hundreds of megabytes that are already on disk is far worse than scanning a directory,
/// so a missing preference falls back to a search.
struct ModelFolderLocator {
    /// Files every WhisperKit model folder contains once it is fully downloaded.
    static let requiredParts = ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"]

    private static let defaultsKey = "whisper.modelFolder"

    let cacheDirectory: URL
    let defaults: UserDefaults
    private let fileManager = FileManager.default

    func locate() -> URL? {
        if let path = defaults.string(forKey: Self.defaultsKey) {
            let remembered = URL(fileURLWithPath: path, isDirectory: true)
            if isComplete(remembered) { return remembered }
        }
        return discover()
    }

    func remember(_ url: URL) {
        defaults.set(url.path, forKey: Self.defaultsKey)
    }

    func forget() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    func isComplete(_ url: URL) -> Bool {
        Self.requiredParts.allSatisfy { fileManager.fileExists(atPath: url.appending(path: $0).path) }
    }

    /// Looks for a complete model folder anywhere under the cache directory.
    func discover() -> URL? {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let walker = fileManager.enumerator(
            at: cacheDirectory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: Set(keys)))?.isDirectory == true else { continue }
            // Never descend into a compiled model's own contents.
            if url.pathExtension == "mlmodelc" {
                walker.skipDescendants()
                continue
            }
            if isComplete(url) { return url }
        }
        return nil
    }
}
