import AppKit

/// Haptic feedback for drag interactions on Force Touch trackpads.
///
/// macOS haptics belong to drags: alignment, snapping, and crossing a level.
/// Clicks already produce the trackpad's own press and release feedback, so
/// adding a pattern to a button action stacks an extra pulse on every click.
/// Don't call this from button actions. See ADR-0046.
@MainActor
enum HapticService {
    /// Whether haptic feedback is currently enabled.
    /// Checks both user preference and system accessibility settings.
    private static var isEnabled: Bool {
        guard SettingsManager.shared.hapticFeedbackEnabled else {
            return false
        }

        // Respect system accessibility setting for reduced motion
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return false
        }

        return true
    }

    /// Performs haptic feedback when a dragged slider reaches its boundary (0% or 100%).
    static func sliderBoundary() {
        guard self.isEnabled else {
            DiagnosticsLogger.haptic.debug("Haptic feedback disabled, skipping slider boundary")
            return
        }

        DiagnosticsLogger.haptic.debug("Performing slider boundary haptic feedback")
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
