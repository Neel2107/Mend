import SwiftUI

/// A compact dotted globe with a sweeping meridian for active search/work states.
/// Motion direction inspired by Thinking Orbs' `searching` state (MIT):
/// https://github.com/Jakubantalik/thinking-orbs
struct SearchingOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                drawOrb(
                    in: context,
                    size: size,
                    time: reduceMotion ? 0.7 : timeline.date.timeIntervalSinceReferenceDate
                )
            }
        }
        .accessibilityHidden(true)
    }

    private func drawOrb(in context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let sphereRadius = min(size.width, size.height) * 0.43
        let spin = time * 0.72
        let scan = time * 3.1
        let tilt = 0.34

        var dots: [OrbDot] = []

        for latitudeIndex in -2...2 {
            let latitude = Double(latitudeIndex) * 0.48
            let longitudeCount = latitudeIndex == 0 ? 12 : (abs(latitudeIndex) == 1 ? 10 : 7)

            for longitudeIndex in 0..<longitudeCount {
                let longitude = (Double(longitudeIndex) / Double(longitudeCount)) * .pi * 2
                let cosLatitude = cos(latitude)
                let x = cosLatitude * cos(longitude)
                let y = sin(latitude)
                let z = cosLatitude * sin(longitude)

                let rotatedX = x * cos(spin) - z * sin(spin)
                let rotatedZ = x * sin(spin) + z * cos(spin)
                let projectedY = y * cos(tilt) - rotatedZ * sin(tilt)
                let depthZ = y * sin(tilt) + rotatedZ * cos(tilt)
                let depth = (depthZ + 1) / 2

                let scanDistance = wrappedAngle(longitude + spin - scan)
                let scanStrength = exp(-(scanDistance * scanDistance) / 0.11)
                    * max(0, depthZ)

                dots.append(
                    OrbDot(
                        center: CGPoint(
                            x: center.x + rotatedX * sphereRadius,
                            y: center.y - projectedY * sphereRadius
                        ),
                        depth: depthZ,
                        radius: 0.34 + (0.42 * depth) + (0.48 * scanStrength),
                        opacity: 0.16 + (0.34 * depth) + (0.46 * scanStrength)
                    )
                )
            }
        }

        for dot in dots.sorted(by: { $0.depth < $1.depth }) {
            let rect = CGRect(
                x: dot.center.x - dot.radius,
                y: dot.center.y - dot.radius,
                width: dot.radius * 2,
                height: dot.radius * 2
            )
            var dotContext = context
            dotContext.opacity = min(dot.opacity, 0.96)
            dotContext.fill(Path(ellipseIn: rect), with: .foreground)
        }
    }

    private func wrappedAngle(_ angle: Double) -> Double {
        atan2(sin(angle), cos(angle))
    }
}

private struct OrbDot {
    let center: CGPoint
    let depth: Double
    let radius: CGFloat
    let opacity: Double
}
