# Overlay UI experiments

The overlay has two separate pieces:

- `OverlayController` owns the macOS panel, screen position, and visibility.
- `OverlayView` owns the SwiftUI layout, material, type, icons, and colors.

Both live in `Sources/Mend/OverlayController.swift`. The values you will change most often are collected in `OverlayDesign` at the top of that file.

## Fast iteration loop

1. Change one or two `OverlayDesign` values.
2. Run `./Scripts/run.sh --preview-overlay` from the repository root.

The app rebuilds and relaunches, then cycles through working, success, and error without using your API key. You can also trigger the same preview from **Mend menu-bar icon → Preview overlay states**.

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

The bottom-right position is calculated in `positionPanel()`:

```swift
x: frame.maxX - panel.frame.width - OverlayDesign.trailingMargin
y: frame.minY + OverlayDesign.bottomMargin
```

For bottom-center, use `frame.midX - panel.frame.width / 2` for `x`. For bottom-left, use `frame.minX + OverlayDesign.trailingMargin`.

Mend intentionally avoids entrance animation because the overlay may appear hundreds of times per day. Immediate feedback feels faster for a keyboard-driven action.
