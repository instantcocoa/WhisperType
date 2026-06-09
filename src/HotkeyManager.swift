//
//  HotkeyManager.swift
//  WhisperType
//
//  Watches a single configurable modifier-style key (the Globe/Fn key or a
//  right-side modifier) and reports its press / release transitions. The
//  AppDelegate decides what those transitions mean based on the activation mode
//  (hold-to-talk vs. press-to-toggle), so this type stays mode-agnostic.
//
//  These keys cannot be captured with Carbon's RegisterEventHotKey, so we watch
//  global `flagsChanged` events instead. Each modifier key emits a
//  `flagsChanged` event with its own keyCode whose modifier flag turns on
//  (press) and off (release). Regular keys that also carry these flags arrive as
//  `keyDown` events, not `flagsChanged`, so they never reach us.
//
//  Global keyboard monitoring is gated by the Accessibility permission, which
//  the app already requests (it is also needed to post the paste keystroke).
//

import AppKit

final class TriggerMonitor {

    private var globalMonitor: Any?
    private var localMonitor:  Any?

    private let key: TriggerKey
    private let onKeyDown: () -> Void
    private let onKeyUp:   () -> Void

    /// Tracks the last known state so we only fire on real transitions.
    private var isKeyDown = false

    init(key: TriggerKey, onKeyDown: @escaping () -> Void, onKeyUp: @escaping () -> Void) {
        self.key       = key
        self.onKeyDown = onKeyDown
        self.onKeyUp   = onKeyUp
        start()
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor  { NSEvent.removeMonitor(localMonitor) }
    }

    // MARK: - Monitoring

    private func start() {
        // Global monitor: events headed to *other* applications.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }

        // Local monitor: events headed to us (e.g. while the menu is open).
        // Returning the event leaves normal handling intact.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }

        if globalMonitor == nil {
            NSLog("WhisperType: failed to install global key monitor — "
                + "grant Accessibility access in System Settings, then relaunch.")
        }
    }

    private func handle(_ event: NSEvent) {
        // React only to the configured physical key.
        guard event.keyCode == key.keyCode else { return }

        let down = event.modifierFlags.contains(key.flag)
        guard down != isKeyDown else { return }   // ignore key-repeat / duplicates
        isKeyDown = down

        if down {
            onKeyDown()
        } else {
            onKeyUp()
        }
    }
}
