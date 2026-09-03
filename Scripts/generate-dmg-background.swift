#!/usr/bin/env swift

import AppKit

let canvasSize = NSSize(width: 700, height: 430)
let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/DMGBackground.png")

let image = NSImage(size: canvasSize)
image.lockFocus()

let bounds = NSRect(origin: .zero, size: canvasSize)
let background = NSGradient(colorsAndLocations:
    (NSColor(srgbRed: 0.973, green: 0.965, blue: 0.996, alpha: 1), 0),
    (NSColor(srgbRed: 0.937, green: 0.957, blue: 1, alpha: 1), 0.52),
    (NSColor(srgbRed: 0.979, green: 0.976, blue: 0.992, alpha: 1), 1)
)!
background.draw(in: bounds, angle: -24)

let glow = NSGradient(colorsAndLocations:
    (NSColor(srgbRed: 0.42, green: 0.30, blue: 1, alpha: 0.12), 0),
    (NSColor(srgbRed: 0.18, green: 0.51, blue: 1, alpha: 0.07), 0.46),
    (NSColor.clear, 1)
)!
glow.draw(in: bounds, relativeCenterPosition: NSPoint(x: -1, y: 1))

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 286, y: 220))
arrow.curve(
    to: NSPoint(x: 414, y: 220),
    controlPoint1: NSPoint(x: 326, y: 178),
    controlPoint2: NSPoint(x: 374, y: 178)
)
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.setLineDash([7, 8], count: 2, phase: 0)
NSColor(white: 0, alpha: 0.18).setStroke()
arrow.stroke()

let arrowhead = NSBezierPath()
arrowhead.move(to: NSPoint(x: 399, y: 216))
arrowhead.line(to: NSPoint(x: 415, y: 220))
arrowhead.line(to: NSPoint(x: 410, y: 204))
arrowhead.lineWidth = 3
arrowhead.lineCapStyle = .round
arrowhead.lineJoinStyle = .round
NSColor(srgbRed: 0.32, green: 0.57, blue: 1, alpha: 0.78).setStroke()
arrowhead.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not render DMG background.\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL)
