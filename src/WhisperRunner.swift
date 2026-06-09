//
//  WhisperRunner.swift
//  WhisperType
//
//  Runs the bundled whisper.cpp CLI against a recorded WAV file, captures the
//  transcription from standard output, and pastes it into the frontmost app
//  via the pasteboard + a synthetic Cmd+V keystroke.
//

import Foundation
import AppKit
import CoreGraphics

final class WhisperRunner {

    /// The bundled CLI binary (whisper.cpp's `whisper-cli`, copied in as `whisper-cpp`).
    private var binaryURL: URL? {
        Bundle.main.url(forResource: "whisper-cpp", withExtension: nil)
    }

    /// The bundled model weights.
    private var modelURL: URL? {
        Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin")
    }

    // MARK: - Transcription

    /// Synchronously transcribes `wavURL`. Returns the recognized text, or nil
    /// on failure. Must be called off the main thread (it blocks on the process).
    func transcribe(wavURL: URL) -> String? {
        guard let binaryURL else {
            NSLog("WhisperType: bundled whisper-cpp binary not found.")
            return nil
        }
        guard let modelURL else {
            NSLog("WhisperType: bundled model (ggml-base.en.bin) not found.")
            return nil
        }

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = [
            "-m",  modelURL.path,   // model path
            "-f",  wavURL.path,     // input WAV
            "-l",  "en",            // language
            "-nt",                  // no timestamps in output
            "-np",                  // no progress / system prints
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError  = stderrPipe

        do {
            try process.run()
        } catch {
            NSLog("WhisperType: failed to launch whisper-cpp — \(error.localizedDescription)")
            return nil
        }

        // Drain stdout before waiting to avoid deadlocking on a full pipe buffer.
        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData  = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let err = String(data: errorData, encoding: .utf8) ?? "<unreadable>"
            NSLog("WhisperType: whisper-cpp exited with status \(process.terminationStatus): \(err)")
            return nil
        }

        guard let raw = String(data: outputData, encoding: .utf8) else { return nil }
        return clean(raw)
    }

    /// Strips whisper's bracketed non-speech annotations (e.g. "[BLANK_AUDIO]",
    /// "[Music]") and collapses surrounding whitespace, so a silent or empty
    /// recording yields an empty string rather than a stray marker.
    private func clean(_ text: String) -> String {
        let withoutMarkers = text.replacingOccurrences(
            of: #"\[[^\]]*\]"#,
            with: "",
            options: .regularExpression
        )
        return withoutMarkers
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Pasting

    /// Places `text` on the general pasteboard and simulates a Cmd+V keystroke
    /// so it lands in whatever text field currently has focus.
    /// Must be called on the main thread.
    func paste(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Give the pasteboard a brief moment to settle before pasting.
        usleep(50_000) // 50 ms

        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 0x09 // ANSI 'V'

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
            let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else {
            NSLog("WhisperType: failed to create paste keystroke events.")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags   = .maskCommand

        let tap = CGEventTapLocation.cghidEventTap
        keyDown.post(tap: tap)
        keyUp.post(tap: tap)
    }
}
