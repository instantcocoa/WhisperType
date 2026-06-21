# WhisperType

A lightweight native macOS menu bar app for local dictation. By default,
**hold the 🌐 Globe / Fn key** to record; release it to transcribe in-process
with [WhisperKit](https://github.com/argmaxinc/WhisperKit) (CoreML on the Apple
Neural Engine), and the recognized text is pasted straight into whatever text
field currently has focus. The Whisper model is downloaded at build time and
bundled into the app, so everything runs on-device with **no network at
runtime**.

The trigger key and activation style are configurable from the menu bar (see
[Settings](#settings)).

## Project layout

```
WhisperType/
├── Package.swift                 # SwiftPM manifest (depends on WhisperKit)
├── Info.plist                    # LSUIElement (no Dock icon) + microphone usage string
├── README.md
├── scripts/
│   ├── build-app.sh              # swift build → fetch + bundle model → assemble + sign WhisperType.app
│   ├── fetch-model.sh            # downloads the CoreML model + tokenizer for offline bundling
│   └── create-signing-cert.sh    # creates a stable self-signed code-signing identity
└── src/
    ├── main.swift                # App entry, MenuBarExtra UI + settings, event routing
    ├── Settings.swift            # UserDefaults-backed trigger key / activation mode
    ├── AudioRecorder.swift       # AVAudioRecorder → 16 kHz / 16-bit / mono WAV
    ├── WhisperRunner.swift       # WhisperEngine (WhisperKit) + Paster (CGEvent ⌘V)
    └── HotkeyManager.swift       # Global flagsChanged monitor for the trigger key
```

## Building

Requires Xcode (or the Swift toolchain) and macOS 13+.

```bash
# (Optional but recommended) create a stable signing identity so the
# Accessibility permission grant survives rebuilds.
./scripts/create-signing-cert.sh

# Build and assemble a signed WhisperType.app bundle.
./scripts/build-app.sh            # release by default; pass "debug" for a debug build

# Launch.
open build/WhisperType.app
```

The first build resolves and compiles WhisperKit via Swift Package Manager and
downloads the `base.en` CoreML model + tokenizer (~150 MB, cached in
`build/model-cache/`). `build-app.sh` then wraps the executable in
`build/WhisperType.app`, bundles the model into `Contents/Resources/models/`,
copies in `Info.plist`, and code-signs the bundle. The model load happens at
launch; the menu bar shows *Loading model…* until it is ready, then *Model
ready*.

Because the model ships inside the app, there is **no network access at
runtime**. To build a smaller app that downloads the model on first launch
instead, set `WHISPERTYPE_BUNDLE_MODEL=0 ./scripts/build-app.sh` — the app then
fetches the model from Hugging Face the first time it runs and caches it on
disk.

### Stable signing (why it matters)

macOS keys the Accessibility (TCC) permission grant on the app's code
signature. An ad-hoc signature changes hash on every rebuild, so the grant
would reset and macOS would re-prompt each time. `create-signing-cert.sh`
creates a self-signed code-signing identity (`WhisperType Self-Signed`) that
`build-app.sh` automatically detects and signs with, giving a stable Designated
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
