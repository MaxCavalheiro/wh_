//
//  WhisperTranscriptionService.swift
//  wh
//

import Foundation
import os
import WhisperKit

/// On-device speech-to-text. Implementations must be safe to call from any actor.
protocol SpeechTranscribing: Sendable {
    /// Downloads (if needed) and loads the speech model, reporting which phase it is in.
    func prepare(onPhase: @escaping @Sendable (ModelPreparation) -> Void) async throws
    /// Transcribes the audio file at `audioURL` and returns the trimmed text.
    func transcribe(audioURL: URL) async throws -> String
}

/// WhisperKit-backed transcription. The loaded `WhisperKit` instance is kept alive
/// for the whole session so the model is never reloaded between transcriptions.
actor WhisperTranscriptionService: SpeechTranscribing {
    private let logger = AppLogger.whisper
    private let modelName: String?
    private let cacheDirectory: URL
    private let locator: ModelFolderLocator
    private var whisperKit: WhisperKit?

    init(
        modelName: String? = AppConfiguration.whisperModel,
        cacheDirectory: URL = AppConfiguration.modelCacheDirectory,
        defaults: UserDefaults = .standard
    ) {
        self.modelName = modelName
        self.cacheDirectory = cacheDirectory
        self.locator = ModelFolderLocator(cacheDirectory: cacheDirectory, defaults: defaults)
    }

    // MARK: - SpeechTranscribing

    func prepare(onPhase: @escaping @Sendable (ModelPreparation) -> Void) async throws {
        guard whisperKit == nil else { return }
        logger.info("Whisper model initialization started")

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Fast path: a model from a previous launch. Loading the folder directly keeps
        // the app fully offline once the model is cached.
        if let cached = locator.locate() {
            onPhase(.optimizing)
            do {
                whisperKit = try await load(from: cached)
                locator.remember(cached)
                logger.info("Whisper model ready (cached)")
                return
            } catch {
                logger.error("Cached model failed to load, re-downloading: \(error.localizedDescription, privacy: .public)")
                locator.forget()
            }
        }

        try checkThereIsRoomForTheModel()

        let folder: URL
        do {
            folder = try await downloadWithRetries(onPhase: onPhase)
        } catch {
            let nsError = error as NSError
            logger.error("Model download failed: \(error.localizedDescription, privacy: .public) [\(nsError.domain, privacy: .public) \(nsError.code)]")
            throw AppError.from(error, fallback: .modelDownloadFailed)
        }

        // Record the folder before the slow load: if the app is killed while CoreML is
        // compiling, the next launch finds these files instead of downloading them again.
        locator.remember(folder)

        onPhase(.optimizing)
        do {
            whisperKit = try await load(from: folder)
        } catch {
            logger.error("Model load failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.modelInitializationFailed
        }

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

    /// How many times a download is retried before giving up. Files already fetched are
    /// kept, so each attempt resumes rather than starting the ~600 MB over.
    private static let downloadAttempts = 3

    /// Retries a download that failed for a reason that may pass, such as a dropped
    /// connection. Losing a long download to one network blip is worth avoiding; a full
    /// disk or a missing model is not worth retrying.
    private func downloadWithRetries(onPhase: @escaping @Sendable (ModelPreparation) -> Void) async throws -> URL {
        let variant = try await resolveVariant()
        var lastError: Error?

        for attempt in 1...Self.downloadAttempts {
            do {
                onPhase(.downloading(progress: nil))
                logger.info("Downloading model \(variant, privacy: .public) (attempt \(attempt))")
                return try await WhisperKit.download(
                    variant: variant,
                    downloadBase: cacheDirectory,
                    progressCallback: { progress in onPhase(.downloading(progress: progress.fractionCompleted)) }
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                guard AppError.from(error, fallback: .modelDownloadFailed) != .notEnoughDiskSpace,
                      attempt < Self.downloadAttempts else { break }
                logger.error("Download attempt \(attempt) failed, retrying: \(error.localizedDescription, privacy: .public)")
                try await Task.sleep(for: .seconds(2 * attempt))
            }
        }
        throw lastError ?? AppError.modelDownloadFailed
    }

    /// The model needs roughly 600 MB, plus room for the files being written. Refusing up
    /// front beats failing at 90% and throwing away the whole download.
    private static let requiredFreeBytes = 1_500_000_000

    private func checkThereIsRoomForTheModel() throws {
        let values = try? cacheDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values?.volumeAvailableCapacityForImportantUsage else { return }
        guard available < Int64(Self.requiredFreeBytes) else { return }
        logger.error("Only \(available / 1_000_000) MB free, need \(Self.requiredFreeBytes / 1_000_000) MB")
        throw AppError.notEnoughDiskSpace
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
