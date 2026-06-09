//
//  AudioRecorder.swift
//  WhisperType
//
//  Records microphone input to a temporary WAV file in exactly the format
//  whisper.cpp expects: 16 kHz, 16-bit, mono, little-endian linear PCM.
//

import Foundation
import AVFoundation

final class AudioRecorder: NSObject {

    /// Whisper requires 16 kHz mono 16-bit PCM input.
    private enum Format {
        static let sampleRate: Double = 16_000
        static let channels:   Int    = 1
        static let bitDepth:   Int    = 16
    }

    private var recorder: AVAudioRecorder?

    /// URL of the most recent recording (valid after `start()` is called).
    private(set) var fileURL: URL?

    /// Requests microphone access. Safe to call repeatedly; the system only
    /// prompts the user once.
    func requestPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                NSLog("WhisperType: microphone access was denied.")
            }
        }
    }

    /// Begins recording to a fresh temporary WAV file.
    func start() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whispertype_recording.wav")

        // Remove any stale recording from a previous run.
        try? FileManager.default.removeItem(at: url)

        let settings: [String: Any] = [
            AVFormatIDKey:            Int(kAudioFormatLinearPCM),
            AVSampleRateKey:          Format.sampleRate,
            AVNumberOfChannelsKey:    Format.channels,
            AVLinearPCMBitDepthKey:   Format.bitDepth,
            AVLinearPCMIsFloatKey:    false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        guard recorder.prepareToRecord(), recorder.record() else {
            throw NSError(
                domain: "WhisperType.AudioRecorder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not start the audio recorder."]
            )
        }

        self.recorder = recorder
        self.fileURL  = url
    }

    /// Stops recording and returns the URL of the finished WAV file.
    @discardableResult
    func stop() -> URL? {
        recorder?.stop()
        recorder = nil
        return fileURL
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            NSLog("WhisperType: recording did not finish successfully.")
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error {
            NSLog("WhisperType: audio encode error — \(error.localizedDescription)")
        }
    }
}
