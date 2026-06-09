# WhisperType

A lightweight, fully self-contained native macOS menu bar app for local
dictation. By default, **hold the 🌐 Globe / Fn key** to record; release it to
transcribe with an embedded [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
binary + model, and the recognized text is pasted straight into whatever text
field currently has focus. Everything runs locally — no network at runtime.

The trigger key and activation style are configurable from the menu bar (see
[Settings](#settings)).

## Project layout

```
WhisperType/
├── CMakeLists.txt                # FetchContent whisper.cpp, model download, signing, bundling
├── Info.plist                    # LSUIElement (no Dock icon) + microphone usage string
├── README.md
├── scripts/
│   └── create-signing-cert.sh    # creates a stable self-signed code-signing identity
└── src/
    ├── main.swift                # App entry, MenuBarExtra UI + settings, event routing
    ├── Settings.swift            # UserDefaults-backed trigger key / activation mode
    ├── AudioRecorder.swift       # AVAudioRecorder → 16 kHz / 16-bit / mono WAV
    ├── WhisperRunner.swift       # Runs bundled CLI via Process, pastes via CGEvent
    └── HotkeyManager.swift       # Global flagsChanged monitor for the trigger key
```

## Building

Requires CMake ≥ 3.26, Xcode, and the command line tools.

```bash
# (Optional but recommended) create a stable signing identity so the
# Accessibility permission grant survives rebuilds.
./scripts/create-signing-cert.sh

# Configure (fetches whisper.cpp and downloads the ggml-base.en model).
cmake -G Xcode -B build

# Build a Release bundle.
cmake --build build --config Release

# Launch.
open build/Release/WhisperType.app
```

The first configure step clones whisper.cpp (tag `v1.8.6`) and downloads
`ggml-base.en.bin` (~142 MB) from Hugging Face into `build/models/`. Both are
cached, so subsequent configures are fast. The post-build step copies the
compiled `whisper-cli` (renamed to `whisper-cpp`) and the model into
`WhisperType.app/Contents/Resources/` and code-signs the bundle.

### Stable signing (why it matters)

macOS keys the Accessibility (TCC) permission grant on the app's code
signature. An ad-hoc signature changes hash on every rebuild, so the grant
would reset and macOS would re-prompt each time. `create-signing-cert.sh`
creates a self-signed code-signing identity (`WhisperType Self-Signed`) that
CMake automatically detects and signs with, giving a stable Designated
Requirement. If the identity is absent, the build falls back to ad-hoc signing.

## Required permissions

On first launch macOS will prompt for two permissions — both are mandatory:

1. **Microphone** — to record your speech (prompted automatically).
2. **Accessibility** — required both to observe the global trigger key and to
   post the synthetic ⌘V paste keystroke. Grant it in **System Settings ▸
   Privacy & Security ▸ Accessibility**, then restart the app.

### If you use the 🌐 Globe / Fn key as the trigger

macOS has its own action bound to the Globe key. To stop it from also opening
the emoji picker or starting Apple's dictation while you dictate, set
**System Settings ▸ Keyboard ▸ "Press 🌐 key to" → Do Nothing**.

## Settings

Click the menu bar icon to configure:

- **Trigger Key** — 🌐 Globe / Fn, Right Option ⌥, Right Command ⌘,
  Right Control ⌃, or Right Shift ⇧. (These modifier-style keys never interfere
  with normal typing.)
- **Activation**
  - **Hold to talk** — record while the key is held, transcribe on release.
  - **Press to toggle** — first press starts recording, second press stops and
    transcribes.

Choices are saved and applied immediately.

## Usage

1. Click into any text field in any application.
2. **Hold** your trigger key (default 🌐) — the menu bar icon switches to
   *Recording…*.
3. Speak, then **release** it — the icon switches to *Transcribing…*.
4. The transcribed text is pasted at the cursor and the icon returns to *Ready*.

(In *Press to toggle* mode, press once to start and again to stop instead of
holding.) Click the menu bar icon to see the current status, change settings,
or quit.
