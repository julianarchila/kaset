import Foundation
import os

/// Centralized logging for the Kaset app.
enum DiagnosticsLogger {
    /// Unified-logging subsystem for every category below.
    private static let subsystem = "com.julianarchila.KasetFork"

    /// Logger for authentication-related events.
    static let auth = Logger(subsystem: Self.subsystem, category: "Auth")

    /// Logger for API-related events.
    static let api = Logger(subsystem: Self.subsystem, category: "API")

    /// Logger for WebKit-related events.
    static let webKit = Logger(subsystem: Self.subsystem, category: "WebKit")

    /// Logger for player-related events.
    static let player = Logger(subsystem: Self.subsystem, category: "Player")

    /// Logger for UI-related events.
    static let ui = Logger(subsystem: Self.subsystem, category: "UI")

    /// Logger for notification-related events.
    static let notification = Logger(subsystem: Self.subsystem, category: "Notification")

    /// Logger for AI/Foundation Models-related events.
    static let ai = Logger(subsystem: Self.subsystem, category: "AI")

    /// Logger for haptic feedback-related events.
    static let haptic = Logger(subsystem: Self.subsystem, category: "Haptic")

    /// Logger for network connectivity-related events.
    static let network = Logger(subsystem: Self.subsystem, category: "Network")

    /// Logger for app lifecycle and URL handling events.
    static let app = Logger(subsystem: Self.subsystem, category: "App")

    /// Logger for AppleScript scripting events.
    static let scripting = Logger(subsystem: Self.subsystem, category: "Scripting")

    /// Logger for App Intents (Shortcuts, Siri, Spotlight) events.
    static let appIntents = Logger(subsystem: Self.subsystem, category: "AppIntents")

    /// Logger for AirPlay-related events.
    static let airplay = Logger(subsystem: Self.subsystem, category: "AirPlay")

    /// Logger for scrobbling-related events (Last.fm, etc.).
    static let scrobbling = Logger(subsystem: Self.subsystem, category: "Scrobbling")

    /// Logger for web extension management events.
    static let extensions = Logger(subsystem: Self.subsystem, category: "Extensions")

    /// Logger for listening history-related events.
    static let history = Logger(subsystem: Self.subsystem, category: "History")

    /// Logger for the equalizer subsystem (process tap, HAL I/O, DSP).
    static let equalizer = Logger(subsystem: Self.subsystem, category: "Equalizer")
}
