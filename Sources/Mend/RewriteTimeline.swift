import Foundation
import os

/// Wall-clock breakdown of one rewrite, written to the unified log so slow
/// steps can be found without a debugger:
///
///     log stream --predicate 'subsystem == "com.mend.desktop" AND category == "timing"' --level info
///
/// No selected text is ever logged, only step names and durations.
final class RewriteTimeline {
    static let logger = Logger(subsystem: "com.mend.desktop", category: "timing")

    private let clock = ContinuousClock()
    private let start: ContinuousClock.Instant
    private var lastMark: ContinuousClock.Instant
    private(set) var entries: [(label: String, duration: Duration)] = []

    init() {
        start = clock.now
        lastMark = start
    }

    /// Records the time since the previous mark under `label`.
    func mark(_ label: String) {
        let now = clock.now
        entries.append((label, lastMark.duration(to: now)))
        lastMark = now
    }

    /// Records work that ran alongside other steps, so it is not part of the sequence.
    func record(_ label: String, _ duration: Duration) {
        entries.append((label, duration))
    }

    var total: Duration {
        start.duration(to: clock.now)
    }

    func log(outcome: String) {
        let summary = Self.format(entries, total: total)
        Self.logger.info("\(outcome, privacy: .public) — \(summary, privacy: .public)")
    }

    static func format(_ entries: [(label: String, duration: Duration)], total: Duration) -> String {
        let steps = entries.map { "\($0.label) \(milliseconds($0.duration))" }
        return (steps + ["total \(milliseconds(total))"]).joined(separator: ", ")
    }

    static func milliseconds(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds)
        let fraction = Double(duration.components.attoseconds) / 1e18
        return "\(Int(((seconds + fraction) * 1000).rounded())) ms"
    }
}
