import AppKit
import os

/// Only one copy of Mend may own the shortcuts. When a second copy launches,
/// say an installed build next to a development build, every shortcut is
/// handled twice and the rewritten text lands twice in the target app. The
/// copy that launched last wins, since that is the one the user just opened.
enum InstanceGuard {
    private static let logger = Logger(subsystem: "com.mend.desktop", category: "lifecycle")

    /// Asks every other running copy of this app to quit. Returns how many were found.
    @discardableResult
    static func terminateOtherInstances(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> Int {
        guard let bundleIdentifier else { return 0 }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentProcessIdentifier }

        for other in others {
            let path = other.bundleURL?.path ?? "unknown path"
            logger.notice("Quitting another copy of Mend, pid \(other.processIdentifier) at \(path, privacy: .public)")
            if !other.terminate() {
                other.forceTerminate()
            }
        }
        return others.count
    }
}
