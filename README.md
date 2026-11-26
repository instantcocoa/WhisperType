# WhisperType

Hold a key, talk, let go — your words are typed into whatever app you're using.

WhisperType is a small menu bar app for Mac that turns your voice into text,
anywhere you can type. It runs entirely on your Mac: **your audio never leaves
your computer**, and it works with no internet connection.

## Install

1. Download the latest `WhisperType-<version>.dmg` from the
   [Releases page](https://github.com/instantcocoa/WhisperType/releases).
2. Open it and drag **WhisperType** into **Applications**.
3. Launch WhisperType. A microphone icon appears in your menu bar (there's no Dock icon).

Requires macOS 13 or later. Works on Apple silicon Macs.

**Updates:** WhisperType checks for new versions daily and installs them
automatically. You can check right away from the menu bar icon ▸ **Check for
Updates…**, or turn off **Update Automatically** there.

## First-time setup

macOS will ask for two permissions. Both are required.

1. **Microphone** — so WhisperType can hear you. Click *Allow* when prompted.
2. **Accessibility** — so WhisperType can notice your trigger key and paste the
   result for you. Open **System Settings ▸ Privacy & Security ▸ Accessibility**,
   switch WhisperType on, then quit and reopen the app.

**If you use the 🌐 Globe / Fn key** (the default): set **System Settings ▸
Keyboard ▸ "Press 🌐 key to" → Do Nothing**. Otherwise macOS will also open the
emoji picker or start its own dictation while you talk.

## How to use it

1. Click into any text field — a document, a chat, a browser, a terminal.
2. **Hold** the trigger key (🌐 by default) and speak. The menu bar icon shows
   *Recording…*.
3. **Let go.** The icon shows *Transcribing…*, then your text appears at the cursor.

Prefer not to hold a key? Switch to **Press to toggle** (see below): press once
to start, press again to stop.

## Settings

Click the menu bar icon to change:

- **Trigger Key** — 🌐 Globe / Fn, Right Option ⌥, Right Command ⌘,
  Right Control ⌃, or Right Shift ⇧. These never get in the way of normal typing.
- **Activation**
  - **Hold to talk** — records while the key is held.
  - **Press to toggle** — first press starts, second press stops.

Changes apply immediately and are remembered.

## Privacy

- Speech is transcribed on your Mac using OpenAI's Whisper model, bundled inside
  the app.
- No account, no cloud service, no network access needed.
- Audio is recorded only while you hold (or have toggled on) the trigger key.

## Troubleshooting

**Nothing happens when I press the key.**
Check that WhisperType is enabled under System Settings ▸ Privacy & Security ▸
Accessibility, then quit and reopen it. After updating the app you may need to
toggle it off and on again.

**It says "Loading model…" for a while after launch.**
The speech model loads when the app starts. Wait for *Model ready* in the menu.

**The text didn't appear.**
Make sure a text field has focus when you release the key. WhisperType pastes
with ⌘V, so it only works where pasting works.

**Emoji picker or Apple dictation pops up when I use 🌐.**
Set System Settings ▸ Keyboard ▸ "Press 🌐 key to" → Do Nothing, or choose a
different trigger key in WhisperType.

**It records silence / returns nothing.**
Check your input device in System Settings ▸ Sound ▸ Input, and that the
Microphone permission is granted to WhisperType.

## Building from source

Requires Xcode and macOS 13+.

```bash
./scripts/build-app.sh      # → build/WhisperType.app (model is downloaded and bundled)
open build/WhisperType.app
```
