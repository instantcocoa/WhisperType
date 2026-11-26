//
//  Updater.swift
//  WhisperType
//
//  Thin SwiftUI wrapper around Sparkle's standard updater. The feed URL and
//  EdDSA public key live in Info.plist (SUFeedURL / SUPublicEDKey).
//

import Foundation
import Sparkle

@MainActor
final class Updater: ObservableObject {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    @Published private(set) var canCheckForUpdates = false

    /// When on, Sparkle checks daily and installs updates without prompting.
    var automaticallyUpdates: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
            controller.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    private var observation: NSKeyValueObservation?

    init() {
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
            [weak self] updater, _ in
            let can = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheckForUpdates = can }
        }
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}
