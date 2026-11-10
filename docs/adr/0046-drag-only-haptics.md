# ADR-0046: Haptics only for drags, not clicks

## Status

Accepted

## Context

`HapticService` played an `NSHapticFeedbackManager` pattern on nearly every
button: player controls, sidebar selection, like/dislike, subscribe, library
add/remove, and search submit. Some calls ran in the button action and others
on press, through the shared button styles.

On a Force Touch trackpad the click itself is haptic: the system plays one
pulse on press and another on release. The app's pattern landed on top of
those, so each click felt like two or three ticks instead of one. Apple's
Human Interface Guidelines limit Mac haptics to drag interactions: alignment,
snapping, and crossing a level. Clicks already get the trackpad's own feedback.

## Decision

- Remove app haptics from every click-triggered action and from the
  `hapticFeedback` option of `InteractiveCardStyle`, `InteractiveRowStyle`, and
  `PressableButtonStyle`.
- Keep one case: `.levelChange` when a dragged volume or seek slider reaches
  0% or 100% (`HapticService.sliderBoundary()`).
- Keep the "Haptic Feedback" setting and the Reduce Motion check; they now
  control only the slider-boundary feedback.

## Consequences

- Clicks feel like clicks in any other Mac app.
- Success and failure no longer have a haptic; visible UI state and alerts
  already report them.
- New haptics should come from drags (snapping, reordering, or a value crossing
  a threshold), never from button actions.
