//
//  WhisperTranscriptionService.swift
//  wh
//

import Foundation
import os
import WhisperKit

/// On-device speech-to-text. Implementations must be safe to call from any actor.
protocol SpeechTranscribing: Sendable {
    /// Downloads (if needed) and loads the speech model. `onProgress` receives the
    /// download fraction in `0...1` while a download is in flight.
    func prepare(onProgress: @escaping @Sendable (Double) -> Void) async throws
    /// Transcribes the audio file at `audioURL` and returns the trimmed text.
    func transcribe(audioURL: URL) async throws -> String
}

/// WhisperKit-backed transcription. The loaded `WhisperKit` instance is kept alive
/// for the whole session so the model is never reloaded between transcriptions.
actor WhisperTranscriptionService: SpeechTranscribing {
    private let logger = AppLogger.whisper
    private let modelName: String?
    private let cacheDirectory: URL
    private let defaults: UserDefaults
    private var whisperKit: WhisperKit?

    private static let modelFolderKey = "whisper.modelFolder"

    init(
        modelName: String? = AppConfiguration.whisperModel,
        cacheDirectory: URL = AppConfiguration.modelCacheDirectory,
        defaults: UserDefaults = .standard
    ) {
        self.modelName = modelName
        self.cacheDirectory = cacheDirectory
        self.defaults = defaults
    }

    // MARK: - SpeechTranscribing

    func prepare(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        guard whisperKit == nil else { return }
        logger.info("Whisper model initialization started")

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Fast path: a model downloaded on a previous launch. Loading from the folder
        // directly keeps the app fully offline once the model is cached.
        if let cached = cachedModelFolder {
            do {
                whisperKit = try await load(from: cached)
                logger.info("Whisper model ready (cached)")
                return
            } catch {
                logger.error("Cached model failed to load, re-downloading: \(error.localizedDescription, privacy: .public)")
                defaults.removeObject(forKey: Self.modelFolderKey)
            }
        }

        let folder: URL
        do {
            let variant = try await resolveVariant()
            logger.info("Downloading model \(variant, privacy: .public)")
            folder = try await WhisperKit.download(
                variant: variant,
                downloadBase: cacheDirectory,
                progressCallback: { progress in onProgress(progress.fractionCompleted) }
            )
        } catch {
            logger.error("Model download failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.modelDownloadFailed
        }

        do {
            whisperKit = try await load(from: folder)
        } catch {
            logger.error("Model load failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.modelInitializationFailed
        }

        defaults.set(folder.path, forKey: Self.modelFolderKey)
        logger.info("Whisper model ready")
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let whisperKit else {
            throw AppError.modelNotReady
        }
        logger.info("Transcription started")

        let options = DecodingOptions(
            task: .transcribe,
            language: nil,          // automatic language detection
            usePrefillPrompt: true,
            detectLanguage: true,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            chunkingStrategy: .vad  // required for recordings longer than 30 s
        )

        let results: [TranscriptionResult]
        do {
            results = try await whisperKit.transcribe(audioPath: audioURL.path, decodeOptions: options)
        } catch {
            logger.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.transcriptionFailed
        }

        let text = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            logger.info("Transcription completed with no speech detected")
            throw AppError.emptyTranscription
        }

        logger.info("Transcription completed (\(text.count) characters)")
        return text
    }

    // MARK: - Private

    private var cachedModelFolder: URL? {
        guard let path = defaults.string(forKey: Self.modelFolderKey) else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return url
    }

    private func resolveVariant() async throws -> String {
        if let modelName { return modelName }
        // Falls back to a built-in device table when the remote config is unreachable.
        let support = await WhisperKit.recommendedRemoteModels(downloadBase: cacheDirectory)
        return support.default
    }

    private func load(from folder: URL) async throws -> WhisperKit {
        let config = WhisperKitConfig(
            downloadBase: cacheDirectory,
            modelFolder: folder.path,
            verbose: AppConfiguration.verboseWhisperLogging,
            logLevel: .info,
            prewarm: false,
            load: true,
            download: false
        )
        return try await WhisperKit(config)
    }
}
