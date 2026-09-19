//
//  AudioRecorder.swift
//  wh
//

import AVFoundation
import Foundation
import os

/// Microphone capture. Knows nothing about transcription.
@MainActor
protocol AudioRecording {
    /// Requests microphone access (prompting the user the first time). Returns `true` when granted.
    func requestPermission() async -> Bool
    /// Starts a new recording into a temporary file.
    func startRecording() async throws
    /// Stops the active recording and returns the URL of the finished audio file.
    func stopRecording() async throws -> URL
    /// Stops the active recording and discards its audio file. No-op when idle.
    func cancelRecording()
    /// Elapsed time of the active recording, or `0` when idle.
    var currentDuration: TimeInterval { get }
}

/// File-based recorder producing mono 16 kHz Linear PCM WAV files, which is the
/// format Whisper models expect natively.
@MainActor
final class AudioRecorder: NSObject, AudioRecording {
    private static let filePrefix = "localwhisper-recording-"

    private let logger = AppLogger.audio
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?

    var currentDuration: TimeInterval {
        recorder?.currentTime ?? 0
    }

    override init() {
        super.init()
        removeStaleRecordings()
    }

    /// Deletes recordings left behind by a previous run that was terminated mid-session,
    /// so temporary files never accumulate.
    private func removeStaleRecordings() {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
        guard let items = try? fileManager.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil) else { return }
        for item in items where item.lastPathComponent.hasPrefix(Self.filePrefix) {
            try? fileManager.removeItem(at: item)
            logger.info("Removed stale recording \(item.lastPathComponent, privacy: .public)")
        }
    }

    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            logger.info("Microphone permission \(granted ? "granted" : "denied")")
            return granted
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func startRecording() async throws {
        guard recorder == nil else {
            // Only one recording session may be active at a time.
            throw AppError.recordingFailed
        }
        guard await requestPermission() else {
            throw AppError.microphonePermissionDenied
        }
        guard AVCaptureDevice.default(for: .audio) != nil else {
            logger.error("No audio capture device available")
            throw AppError.microphoneUnavailable
        }

        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(Self.filePrefix)\(UUID().uuidString).wav")
        logger.info("Audio path generated: \(url.lastPathComponent, privacy: .public)")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        let newRecorder: AVAudioRecorder
        do {
            newRecorder = try AVAudioRecorder(url: url, settings: settings)
        } catch {
            logger.error("AVAudioRecorder init failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.recordingFailed
        }
        newRecorder.delegate = self

        guard newRecorder.prepareToRecord(), newRecorder.record() else {
            logger.error("AVAudioRecorder could not start recording")
            try? FileManager.default.removeItem(at: url)
            throw AppError.recordingFailed
        }

        recorder = newRecorder
        outputURL = url
        logger.info("Recording started")
    }

    func cancelRecording() {
        guard let recorder else { return }
        recorder.stop()
        recorder.deleteRecording()
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        self.recorder = nil
        self.outputURL = nil
        logger.info("Recording cancelled")
    }

    func stopRecording() async throws -> URL {
        guard let recorder, let outputURL else {
            throw AppError.recordingFailed
        }
        recorder.stop()
        self.recorder = nil
        self.outputURL = nil
        logger.info("Recording stopped")

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            logger.error("Recorded file missing at \(outputURL.path, privacy: .public)")
            throw AppError.audioFileUnavailable
        }
        return outputURL
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        AppLogger.audio.error("Encode error: \(error?.localizedDescription ?? "unknown", privacy: .public)")
    }
}
