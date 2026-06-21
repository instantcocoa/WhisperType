//
//  WhisperRunner.swift
//  WhisperType
//
//  In-process speech-to-text via WhisperKit (CoreML / Apple Neural Engine).
//  The model is loaded lazily — downloaded from Hugging Face on first use and
//  cached on disk by WhisperKit — so there is no bundled model and no
//  whisper.cpp subprocess. Recognized text is pasted into the frontmost app via
//  the pasteboard + a synthetic Cmd+V keystroke.
//

import Foundation
import AppKit
import CoreGraphics
import WhisperKit

/// Owns the WhisperKit instance and serializes access to it. Loading (and the
/// first-run download) happens lazily and is cached for the process lifetime.
actor WhisperEngine {

    /// WhisperKit model name. WhisperKit fuzzy-matches this against the
    /// `whisperkit-coreml` repo. Used only when no model is bundled.
    private let modelName: String

    /// The on-disk variant folder name WhisperKit uses, e.g.
    /// `models/openai_whisper-base.en` inside the app's Resources.
    private let bundledVariant: String

    private var whisperKit: WhisperKit?

    init(modelName: String = "base.en", bundledVariant: String = "openai_whisper-base.en") {
        self.modelName = modelName
        self.bundledVariant = bundledVariant
    }

    /// Loads the model if it isn't loaded yet. Prefers the model bundled into the
    /// app (fully offline); if none is bundled, falls back to downloading from
    /// Hugging Face on first use (network required once, then cached on disk).
    /// Safe to call repeatedly.
    func prepare() async throws {
        guard whisperKit == nil else { return }

        let config: WhisperKitConfig
        if let bundle = bundledFolders() {
            // Load the shipped model + tokenizer directly; never touch the network.
            config = WhisperKitConfig(
                model: modelName,
                modelFolder: bundle.model.path,
                tokenizerFolder: bundle.tokenizer,
                download: false
            )
        } else {
            // No bundled model — download the variant on demand and cache it.
            config = WhisperKitConfig(model: modelName)
        }
        whisperKit = try await WhisperKit(config)
    }

    /// Locates the model + tokenizer folders bundled in the app, if present.
    /// WhisperKit fetches the tokenizer from the original OpenAI repo separately,
    /// so it is shipped (and pointed at via `tokenizerFolder`) in its own folder.
    private func bundledFolders() -> (model: URL, tokenizer: URL)? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let models = resources.appendingPathComponent("models", isDirectory: true)
        let model = models.appendingPathComponent(bundledVariant, isDirectory: true)
        let tokenizer = models.appendingPathComponent("\(bundledVariant)-tokenizer", isDirectory: true)

        let fm = FileManager.default
        guard fm.fileExists(atPath: model.appendingPathComponent("config.json").path),
              fm.fileExists(atPath: tokenizer.appendingPathComponent("tokenizer.json").path)
        else { return nil }

        return (model, tokenizer)
    }

    /// Transcribes the audio file at `audioPath`. Returns cleaned text (possibly
    /// empty for silence). Lazily prepares the model if needed.
    func transcribe(audioPath: String) async throws -> String {
        try await prepare()
        guard let whisperKit else { return "" }

        let results = try await whisperKit.transcribe(audioPath: audioPath)
        let raw = results.map(\.text).joined(separator: " ")
        return WhisperEngine.clean(raw)
    }

    /// Strips whisper's bracketed non-speech annotations (e.g. "[BLANK_AUDIO]",
    /// "[Music]"), the special `<|...|>` decoder tokens WhisperKit can emit, and
    /// collapses surrounding whitespace — so a silent recording yields an empty
    /// string rather than a stray marker.
    static func clean(_ text: String) -> String {
        let withoutTokens = text.replacingOccurrences(
            of: #"<\|[^|]*\|>"#,
            with: "",
            options: .regularExpression
        )
        let withoutMarkers = withoutTokens.replacingOccurrences(
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
}

// MARK: - Pasting

/// Pastes text into whatever text field currently has focus.
enum Paster {

    /// Places `text` on the general pasteboard and simulates a Cmd+V keystroke
    /// so it lands in the focused field. Must be called on the main thread.
    @MainActor
    static func paste(text: String) {
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
