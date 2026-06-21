//
//  main.swift
//  WhisperType
//
//  App entry point, menu bar UI (status + settings), and event routing between
//  the trigger key, the audio recorder, and the whisper transcription/paste
//  pipeline.
//

import SwiftUI
import AppKit
import ApplicationServices

// MARK: - Shared application state

/// Observable state shared between the AppDelegate (which drives the logic)
/// and the SwiftUI MenuBarExtra (which renders the current status).
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Status: String {
        case ready        = "Ready"
        case recording    = "Recording…"
        case transcribing = "Transcribing…"
    }

    /// Load state of the WhisperKit model (downloaded on demand on first run).
    enum ModelState {
        case loading        // downloading and/or loading into memory
        case ready
        case failed(String)

        var label: String {
            switch self {
            case .loading:          return "Loading model…"
            case .ready:            return "Model ready"
            case .failed(let why):  return "Model error: \(why)"
            }
        }
    }

    @Published var status: Status = .ready
    @Published var modelState: ModelState = .loading

    /// SF Symbol shown in the menu bar for the current status.
    var symbolName: String {
        switch status {
        case .ready:
            if case .loading = modelState { return "arrow.down.circle" }
            return "mic"
        case .recording:    return "mic.fill"
        case .transcribing: return "waveform"
        }
    }

    private init() {}
}

// MARK: - Application delegate / event routing

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let recorder = AudioRecorder()
    private let engine   = WhisperEngine()
    private var monitor:  TriggerMonitor?

    private var state:    AppState { AppState.shared }
    private var settings: Settings { Settings.shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ask for microphone access up front.
        recorder.requestPermission()

        // Ask for Accessibility access — required both to observe the global
        // trigger key and to post the synthetic Cmd+V paste keystroke.
        requestAccessibilityPermission()

        // Re-arm the key monitor whenever the trigger key changes.
        settings.onChange = { [weak self] in self?.rearmMonitor() }
        rearmMonitor()

        // Warm up the model in the background so the first dictation is fast.
        // This is what downloads the weights on first ever launch.
        prepareModel()
    }

    /// Kicks off loading (and, on first run, downloading) the Whisper model.
    private func prepareModel() {
        state.modelState = .loading
        Task { [engine] in
            do {
                try await engine.prepare()
                await MainActor.run { AppState.shared.modelState = .ready }
            } catch {
                NSLog("WhisperType: failed to load model — \(error.localizedDescription)")
                await MainActor.run {
                    AppState.shared.modelState = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: Trigger handling

    /// Rebuilds the key monitor for the currently configured trigger key.
    private func rearmMonitor() {
        monitor = nil   // tear down the previous monitor (removes its observers)
        monitor = TriggerMonitor(
            key: settings.triggerKey,
            onKeyDown: { [weak self] in self?.handleKeyDown() },
            onKeyUp:   { [weak self] in self?.handleKeyUp() }
        )
    }

    private func handleKeyDown() {
        switch settings.triggerMode {
        case .pushToTalk:
            beginRecording()
        case .toggle:
            switch state.status {
            case .ready:        beginRecording()
            case .recording:    endRecordingAndTranscribe()
            case .transcribing: break   // ignore while busy
            }
        }
    }

    private func handleKeyUp() {
        // Only the hold-to-talk mode cares about release.
        if settings.triggerMode == .pushToTalk {
            endRecordingAndTranscribe()
        }
    }

    // MARK: Recording lifecycle

    private func beginRecording() {
        guard state.status == .ready else { return }
        do {
            try recorder.start()
            state.status = .recording
        } catch {
            NSLog("WhisperType: failed to start recording — \(error.localizedDescription)")
            state.status = .ready
        }
    }

    private func endRecordingAndTranscribe() {
        guard state.status == .recording else { return }
        guard let wavURL = recorder.stop() else {
            state.status = .ready
            return
        }

        state.status = .transcribing

        // Transcribe off the main actor (WhisperKit is async); hop back to the
        // main actor to paste and reset state. The first call may block while
        // the model finishes downloading/loading.
        Task { [engine] in
            let text = try? await engine.transcribe(audioPath: wavURL.path)
            await MainActor.run {
                if let text, !text.isEmpty {
                    Paster.paste(text: text)
                }
                AppState.shared.status = .ready
            }
        }
    }

    // MARK: Permissions

    private func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            NSLog("WhisperType: Accessibility permission not yet granted; "
                + "grant it in System Settings ▸ Privacy & Security ▸ Accessibility.")
        }
    }
}

// MARK: - SwiftUI app / menu bar UI

struct WhisperTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var state    = AppState.shared
    @ObservedObject private var settings = Settings.shared

    var body: some Scene {
        MenuBarExtra("WhisperType", systemImage: state.symbolName) {
            Text("WhisperType")
                .font(.headline)

            Divider()

            Text("Status: \(state.status.rawValue)")
            Text(state.modelState.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(settings.hint)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Picker("Trigger Key", selection: $settings.triggerKey) {
                ForEach(TriggerKey.allCases) { key in
                    Text(key.displayName).tag(key)
                }
            }

            Picker("Activation", selection: $settings.triggerMode) {
                ForEach(TriggerMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            Divider()

            Button("Quit WhisperType") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

// MARK: - Entry point
//
// The file is named `main.swift`, which is treated as a script context and
// therefore cannot carry the `@main` attribute. Instead we explicitly invoke
// the SwiftUI `App.main()` entry point as top-level code.
WhisperTypeApp.main()
