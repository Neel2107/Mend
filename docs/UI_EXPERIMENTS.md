# Overlay UI experiments

The overlay has two separate pieces:

- `OverlayController` owns the macOS panel, screen position, and visibility.
- `OverlayView` owns the SwiftUI layout, material, type, icons, and colors.

Both live in `Sources/Mend/OverlayController.swift`. The values you will change most often are collected in `OverlayDesign` at the top of that file.

## Fast iteration loop

1. Change one or two `OverlayDesign` values.
2. Run `./Scripts/run.sh --preview-overlay` from the repository root.

The app rebuilds and relaunches, then cycles through working, success, and error without using your API key. You can also trigger the same preview from the menu-bar icon: hold **Option** while the menu is open and choose **Preview Overlay States**.

## Useful directions to try

### Minimal status chip

- Width around 190 points
- Hide the shortcut label
- Show only the spinner/checkmark and status

### Compact toast

- Width around 250–280 points
- Keep the current capsule
- Add a short description only for errors

### Review before replacing

- Increase the panel to roughly 420 by 120 points
- Show the corrected sentence
- Add Apply and Cancel buttons
- Allow the panel to receive keyboard input for Return and Escape

### Diff preview

- Show removed words in red and additions in green
- Keep automatic replacement as the default
- Use a second shortcut when a review is wanted

## Position

The capsule sits in the bottom-right corner of the window being edited, read through Accessibility when the shortcut fires, and falls back to the screen corner when the window is unavailable or smaller than `OverlayDesign.minimumAnchorSize`. The frame is computed in `OverlayController.panelFrame(width:height:anchor:within:)`, which the placement tests cover:

```swift
x: container.maxX - width - OverlayDesign.trailingMargin
y: container.minY + OverlayDesign.bottomMargin
```

For bottom-center, use `container.midX - width / 2` for `x`. For bottom-left, use `container.minX + OverlayDesign.trailingMargin`. Setting `overlay.anchorFrame = nil` before `show` forces the screen corner.

Failure states may grow to `OverlayDesign.maximumFailurePanelWidth` so error messages stay readable; other states cap at `maximumPanelWidth`.

Mend intentionally avoids entrance animation because the overlay may appear hundreds of times per day. Immediate feedback feels faster for a keyboard-driven action.

## Timing

Every rewrite writes a one-line breakdown to the unified log: capture, each provider attempt, replace, the connection warm-up that ran alongside capture, and the total. No selected text is logged. Watch it with:

```sh
log stream --predicate 'subsystem == "com.mend.desktop" AND category == "timing"' --level info
```
