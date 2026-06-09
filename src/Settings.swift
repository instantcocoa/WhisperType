//
//  Settings.swift
//  WhisperType
//
//  User-configurable, UserDefaults-backed settings: which key triggers
//  dictation and whether it works as hold-to-talk or press-to-toggle.
//

import AppKit
import Carbon.HIToolbox

// MARK: - Activation mode

enum TriggerMode: String, CaseIterable, Identifiable {
    case pushToTalk   // record while the key is held, transcribe on release
    case toggle       // first press starts, second press stops + transcribes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pushToTalk: return "Hold to talk"
        case .toggle:     return "Press to toggle"
        }
    }
}

// MARK: - Trigger key

/// Modifier-style keys that can be observed via `flagsChanged`. Restricting the
/// choices to these means a single detection path works for every option and
/// none of them interfere with ordinary typing.
enum TriggerKey: String, CaseIterable, Identifiable {
    case fn
    case rightOption
    case rightCommand
    case rightControl
    case rightShift

    var id: String { rawValue }

    /// The `flagsChanged` keyCode emitted by the physical key.
    var keyCode: UInt16 {
        switch self {
        case .fn:           return UInt16(kVK_Function)      // 63
        case .rightOption:  return UInt16(kVK_RightOption)   // 61
        case .rightCommand: return UInt16(kVK_RightCommand)  // 54
        case .rightControl: return UInt16(kVK_RightControl)  // 62
        case .rightShift:   return UInt16(kVK_RightShift)    // 60
        }
    }

    /// The device-independent modifier flag that is set while the key is down.
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .fn:           return .function
        case .rightOption:  return .option
        case .rightCommand: return .command
        case .rightControl: return .control
        case .rightShift:   return .shift
        }
    }

    var displayName: String {
        switch self {
        case .fn:           return "🌐 Globe / Fn"
        case .rightOption:  return "Right Option ⌥"
        case .rightCommand: return "Right Command ⌘"
        case .rightControl: return "Right Control ⌃"
        case .rightShift:   return "Right Shift ⇧"
        }
    }
}

// MARK: - Settings store

final class Settings: ObservableObject {
    static let shared = Settings()

    private enum Keys {
        static let triggerMode = "triggerMode"
        static let triggerKey  = "triggerKey"
    }

    private let defaults = UserDefaults.standard

    /// Invoked whenever a setting changes so the app can re-arm its monitor.
    var onChange: (() -> Void)?

    @Published var triggerMode: TriggerMode {
        didSet {
            defaults.set(triggerMode.rawValue, forKey: Keys.triggerMode)
            onChange?()
        }
    }

    @Published var triggerKey: TriggerKey {
        didSet {
            defaults.set(triggerKey.rawValue, forKey: Keys.triggerKey)
            onChange?()
        }
    }

    private init() {
        // didSet does not fire for assignments inside init, so loading defaults
        // here does not spuriously trigger onChange.
        let modeRaw = defaults.string(forKey: Keys.triggerMode) ?? TriggerMode.pushToTalk.rawValue
        let keyRaw  = defaults.string(forKey: Keys.triggerKey)  ?? TriggerKey.fn.rawValue
        triggerMode = TriggerMode(rawValue: modeRaw) ?? .pushToTalk
        triggerKey  = TriggerKey(rawValue: keyRaw)  ?? .fn
    }

    /// A short human-readable description of the current trigger, e.g.
    /// "Hold 🌐 Globe / Fn to dictate".
    var hint: String {
        switch triggerMode {
        case .pushToTalk: return "Hold \(triggerKey.displayName) to dictate"
        case .toggle:     return "Press \(triggerKey.displayName) to start / stop"
        }
    }
}
