# CLAUDE.md

Guidance for working in this repo. Read this before making changes.

## What this is

**WhisperType** — a native macOS menu bar app for local push-to-talk dictation.
Hold a trigger key (default 🌐 Globe/Fn) → record mic audio → on release,
transcribe **in-process with WhisperKit** (CoreML / Apple Neural Engine) →
paste the text into the focused field via a synthetic ⌘V. The Whisper model is
downloaded at build time and bundled into the `.app`, so transcription is fully
on-device with no network access at runtime. Built with Swift Package Manager,
packaged as a standalone `.app`.

See `README.md` for the user-facing description.

## Architecture

| File | Role |
|------|------|
| `Package.swift` | SwiftPM manifest; depends on the `WhisperKit` product from `argmax-oss-swift` |
| `scripts/build-app.sh` | `swift build` → fetch + bundle model → assemble `build/WhisperType.app` (executable + Info.plist + `Resources/models/` + any SwiftPM resource bundles), detect signing identity, code-sign |
| `scripts/fetch-model.sh` | Downloads the CoreML model variant (`argmaxinc/whisperkit-coreml`) + matching tokenizer (`openai/whisper-base.en`) into a cache for offline bundling (curl + python3 only) |
| `Info.plist` | `LSUIElement` (no Dock icon), `NSMicrophoneUsageDescription` |
| `src/main.swift` | Entry point, `MenuBarExtra` UI + settings pickers, `AppDelegate` event routing, recording lifecycle, model prewarm |
| `src/Settings.swift` | `UserDefaults`-backed `Settings` (trigger key + activation mode); `TriggerKey` / `TriggerMode` enums |
| `src/HotkeyManager.swift` | `TriggerMonitor` — mode-agnostic global key watcher (reports down/up) |
| `src/AudioRecorder.swift` | `AVAudioRecorder` → 16 kHz / 16-bit / mono WAV |
| `src/WhisperRunner.swift` | `WhisperEngine` actor (WhisperKit load/transcribe, lazy on-demand model) + `Paster` (pasteboard + `CGEvent` ⌘V) |
| `scripts/create-signing-cert.sh` | Creates the stable self-signed code-signing identity |

**Control flow:** `TriggerMonitor` (flagsChanged observer) → `AppDelegate.handleKeyDown/Up` →
applies hold-vs-toggle logic based on `Settings.triggerMode` → `beginRecording` /
`endRecordingAndTranscribe` → `await WhisperEngine.transcribe(audioPath:)` (off the
main actor) → `Paster.paste` (`@MainActor`). UI state lives in `AppState`
(observable: `status` + `modelState`), rendered by `MenuBarExtra`. The model is
prewarmed in a background `Task` at launch (`AppDelegate.prepareModel`).

## Build & run

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh
open build/WhisperType.app
```

(`./scripts/build-app.sh debug` for a debug build. Plain `swift build` also works
for a quick compile check; the script just adds bundling + signing.)

**Stop a running instance before rebuilding:** `pkill -f "WhisperType.app/Contents/MacOS/WhisperType"`

## Gotchas / non-obvious decisions (READ THESE)

- **`DEVELOPER_DIR` is recommended.** `xcode-select` on this machine points at
  CommandLineTools. Plain `swift build` works against either toolchain, but
  prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` to build
  against the full Xcode toolchain (or run `sudo xcode-select -s /Applications/Xcode.app`).
- **WhisperKit is the `argmax-oss-swift` package.** WhisperKit was folded into
  Argmax's open-source SDK; depend on `https://github.com/argmaxinc/argmax-oss-swift.git`
  and use `.product(name: "WhisperKit", package: "argmax-oss-swift")`. Only the
  `WhisperKit` library is pulled (its server/CLI deps like Vapor are conditional
  and not fetched) — so the resolved graph is just WhisperKit + ArgmaxCore +
  swift-argument-parser.
- **Model is bundled at build time (offline by default).** `build-app.sh` runs
  `fetch-model.sh` to download the CoreML variant + tokenizer into
  `build/model-cache/` (cached across builds) and copies them into
  `Contents/Resources/models/`. At runtime `WhisperEngine.bundledFolders()`
  finds them and constructs `WhisperKitConfig(model:, modelFolder:,
  tokenizerFolder:, download: false)` → loads locally, never touches the network.
  Set `WHISPERTYPE_BUNDLE_MODEL=0 ./scripts/build-app.sh` to skip bundling; then
  `bundledFolders()` returns nil and the config falls back to
  `WhisperKitConfig(model: "base.en")`, which downloads on demand on first use
  and caches on disk. `prepareModel()` loads/prewarms at startup either way.
- **The tokenizer is a separate download.** WhisperKit's CoreML repo
  (`argmaxinc/whisperkit-coreml/openai_whisper-base.en`) does **not** include
  `tokenizer.json`; WhisperKit normally fetches it from the original
  `openai/whisper-base.en` repo. For a truly offline bundle we ship it too, in a
  sibling `…-tokenizer/` folder, and point `tokenizerFolder` there (kept separate
  from the model folder so its `config.json` is the HF model config, not the
  CoreML one). `loadTokenizer` searches `tokenizerFolder` for `tokenizer.json`
  and loads locally; it only hits the Hub if that file is missing.
- **No bundled binaries.** The app's executable is self-contained (WhisperKit is
  statically linked; CoreML is a system framework) — no `whisper-cpp` CLI, no
  `.metal`. The only bundled resources are the model/tokenizer under
  `Resources/models/` (~150 MB → ~146 MB `.app`). `build-app.sh` also copies any
  `*.bundle` SwiftPM resource bundles into `Resources` defensively (currently
  none are produced). `.mlmodelc` dirs are sealed as data resources by the final
  `codesign`; verified with `codesign --verify --deep --strict`.
- **`main.swift` cannot use `@main`.** A file named `main.swift` is a script
  context. We define `struct WhisperTypeApp: App` (no `@main`) and call
  `WhisperTypeApp.main()` as top-level code at the bottom of the file.
- **Concurrency: avoid capturing `self` in `Task`s.** The background `Task`s in
  `AppDelegate` reference `AppState.shared` directly inside `MainActor.run`
  instead of capturing `self`, which would be a hard error under the Swift 6
  language mode. `WhisperEngine` is an `actor`; `Paster.paste` is `@MainActor`.
- **Stable code signing is load-bearing for UX.** macOS keys the Accessibility
  (TCC) grant on the signature. Ad-hoc signatures change hash every rebuild →
  the grant resets and the user gets re-prompted. `scripts/create-signing-cert.sh`
  makes a self-signed identity (`WhisperType Self-Signed`); `build-app.sh`
  auto-detects it and signs with it (falls back to ad-hoc if absent). The cert is
  machine-local — re-run the script on a new machine.
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

**Done & verified:** clean SwiftPM build (WhisperKit resolves + compiles);
`fetch-model.sh` downloads model + tokenizer; `build-app.sh` produces a signed
`.app` with the model bundled (`codesign --verify --deep --strict` passes);
**offline transcription verified end-to-end** — WhisperKit loaded from the
bundled `modelFolder` + `tokenizerFolder` with `download: false` and correctly
transcribed a `say`-generated WAV. Configurable trigger key + hold/toggle modes;
settings menu; blank-audio / decoder-token filtering.

**Not verified headlessly** (needs a GUI session + granted Accessibility +
physical keypress): live trigger key down/up, recording, and paste. The build,
bundling, and WhisperKit inference paths are confirmed; the trigger/paste path
is sound but unexercised in an automated run.

## Future tasks / ideas

- **Distribution:** proper Developer ID signing + notarization (current cert is
  local-only and untrusted; fine for personal use, not for shipping).
- **Model selection in settings:** let the user pick model size
  (tiny/base/small/…). On-demand download already works (WhisperKit); this would
  add a picker + a real download-progress indicator (WhisperKit exposes a
  progress callback) instead of the current binary *Loading model…* state.
- **Feedback:** subtle sound or HUD on record start/stop; surface
  transcription/recorder errors in the UI instead of only `NSLog`.
- **Custom hotkey recording UI:** capture an arbitrary shortcut rather than the
  curated modifier list (would likely need a CGEventTap and Input Monitoring).
- **Left-side modifier options** and/or combos.
- **Long-recording handling:** consider chunking/streaming for very long dictation.
- **Tests:** unit-test `WhisperEngine.clean(...)` and `Settings` persistence.
- **Append-vs-replace pasteboard:** option to preserve/restore the user's prior
  clipboard contents after pasting.
