# CLAUDE.md

Guidance for working in this repo. Read this before making changes.

## What this is

**WhisperType** — a self-contained native macOS menu bar app for local
push-to-talk dictation. Hold a trigger key (default 🌐 Globe/Fn) → record mic
audio → on release, transcribe with an embedded `whisper.cpp` CLI + model →
paste the text into the focused field via a synthetic ⌘V. Everything runs
locally; no network at runtime. Built with CMake (Swift/C/C++), packaged as a
standalone `.app`.

See `README.md` for the user-facing description.

## Architecture

| File | Role |
|------|------|
| `CMakeLists.txt` | FetchContent whisper.cpp, download model, build bundle, detect signing identity, copy assets + re-sign as post-build |
| `Info.plist` | `LSUIElement` (no Dock icon), `NSMicrophoneUsageDescription` |
| `src/main.swift` | Entry point, `MenuBarExtra` UI + settings pickers, `AppDelegate` event routing & recording lifecycle |
| `src/Settings.swift` | `UserDefaults`-backed `Settings` (trigger key + activation mode); `TriggerKey` / `TriggerMode` enums |
| `src/HotkeyManager.swift` | `TriggerMonitor` — mode-agnostic global key watcher (reports down/up) |
| `src/AudioRecorder.swift` | `AVAudioRecorder` → 16 kHz / 16-bit / mono WAV |
| `src/WhisperRunner.swift` | Runs bundled CLI via `Process`, cleans output, pastes via `CGEvent` |
| `scripts/create-signing-cert.sh` | Creates the stable self-signed code-signing identity |

**Control flow:** `TriggerMonitor` (flagsChanged observer) → `AppDelegate.handleKeyDown/Up` →
applies hold-vs-toggle logic based on `Settings.triggerMode` → `beginRecording` /
`endRecordingAndTranscribe` → `WhisperRunner.transcribe` (off main thread) →
`WhisperRunner.paste` (main thread). UI state lives in `AppState` (observable),
rendered by `MenuBarExtra`.

## Build & run

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer cmake -G Xcode -B build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer cmake --build build --config Release
open build/Release/WhisperType.app
```

**Stop a running instance before rebuilding:** `pkill -f "WhisperType.app/Contents/MacOS/WhisperType"`

## Gotchas / non-obvious decisions (READ THESE)

- **`DEVELOPER_DIR` is required.** `xcode-select` on this machine points at
  CommandLineTools, but the CMake Xcode generator needs full `xcodebuild`.
  Prefix cmake commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
  (or run `sudo xcode-select -s /Applications/Xcode.app`).
- **whisper.cpp tag is `v1.8.6`.** The originally-requested `v1.11.0` does not
  exist. `v1.8.6` is the latest stable as of this writing. The CLI target is
  `whisper-cli`; we copy it into the bundle renamed to `whisper-cpp`.
- **Static linking.** `BUILD_SHARED_LIBS=OFF` + `GGML_METAL_EMBED_LIBRARY=ON`
  so the copied CLI is self-contained (no loose dylibs / `.metal` file).
- **`main.swift` cannot use `@main`.** A file named `main.swift` is a script
  context. We define `struct WhisperTypeApp: App` (no `@main`) and call
  `WhisperTypeApp.main()` as top-level code at the bottom of the file.
- **Stable code signing is load-bearing for UX.** macOS keys the Accessibility
  (TCC) grant on the signature. Ad-hoc signatures change hash every rebuild →
  the grant resets and the user gets re-prompted. `scripts/create-signing-cert.sh`
  makes a self-signed identity (`WhisperType Self-Signed`); CMake auto-detects
  it and signs with it (falls back to ad-hoc if absent). The cert is
  machine-local — re-run the script on a new machine.
- **Xcode signs AFTER our post-build script.** So `XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY`
  must be set to the stable identity — otherwise Xcode's own CodeSign phase
  clobbers our signature back to ad-hoc. (The post-build `codesign` calls remain
  for non-Xcode generators.) The nested `whisper-cpp` is signed in post-build
  since Xcode doesn't re-sign resources.
- **Trigger detection uses `NSEvent.addGlobalMonitorForEvents(.flagsChanged)`,
  not Carbon hotkeys or a CGEventTap.** The Fn/Globe key isn't a registerable
  hotkey. Global key monitors are gated by **Accessibility** (already granted);
  a CGEventTap would additionally require Input Monitoring. We match on the
  specific `keyCode` + modifier `flag` per `TriggerKey`. Regular keys carrying
  these flags arrive as `keyDown` (not `flagsChanged`) so they don't trip it.
- **Trigger options are modifier-style keys only** (Fn + right-side modifiers)
  by design: one detection path, works for both hold & toggle, never clashes
  with typing.
- **PKCS#12 needs `-legacy`** in the signing script — OpenSSL 3.x defaults to
  PBE algorithms macOS `security import` can't read.

## Permissions (runtime)

- **Microphone** — prompted automatically on first record.
- **Accessibility** — needed for BOTH the global key monitor AND the ⌘V paste.
  Grant in System Settings ▸ Privacy & Security ▸ Accessibility, then relaunch.
- **Globe key users:** set System Settings ▸ Keyboard ▸ "Press 🌐 key to →
  Do Nothing" so it doesn't also open the emoji picker / Apple dictation.

## Status

**Done & verified:** clean CMake build; whisper.cpp fetch; model download;
bundle assembly; static self-contained CLI; transcription verified end-to-end
(jfk.wav → correct text); stable signing; configurable trigger key +
hold/toggle modes; settings menu; blank-audio marker filtering.

**Not verified headlessly** (needs a GUI session + granted Accessibility +
physical keypress): live trigger key down/up, recording, and paste. The build
and transcription paths are confirmed; the trigger/paste path is sound but
unexercised in an automated run.

## Future tasks / ideas

- **Distribution:** proper Developer ID signing + notarization (current cert is
  local-only and untrusted; fine for personal use, not for shipping).
- **Model selection in settings:** let the user pick model size
  (tiny/base/small/…); download on demand; show download progress.
- **Feedback:** subtle sound or HUD on record start/stop; surface
  transcription/recorder errors in the UI instead of only `NSLog`.
- **Custom hotkey recording UI:** capture an arbitrary shortcut rather than the
  curated modifier list (would likely need a CGEventTap and Input Monitoring).
- **Left-side modifier options** and/or combos.
- **Long-recording handling:** consider chunking/streaming for very long dictation.
- **Tests:** unit-test `WhisperRunner.clean(...)` and `Settings` persistence.
- **Append-vs-replace pasteboard:** option to preserve/restore the user's prior
  clipboard contents after pasting.
