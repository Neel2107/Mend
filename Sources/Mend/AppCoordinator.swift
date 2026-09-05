import AppKit
import ApplicationServices
import Carbon
import SwiftUI

@MainActor
final class AppCoordinator: NSObject, NSMenuDelegate {
    private enum CoordinatorError: LocalizedError {
        case providersFailed([LLMProvider], any Error)

        var errorDescription: String? {
            switch self {
            case .providersFailed(let providers, let lastError):
                let names = providers.map(\.displayName).joined(separator: " and ")
                return "\(names) failed: \(lastError.localizedDescription)"
            }
        }
    }

    private let settings = AppSettings(
        readsAPIKeyFromKeychain: !CommandLine.arguments.contains("--preview-overlay")
    )
    private let overlay = OverlayController()
    private let selectionService = SelectionService()

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var localMenuClickMonitor: Any?
    private var globalMenuClickMonitor: Any?
    private var isStatusMenuOpen = false
    private var hotKeys: [HotKeyManager] = []
    private var registeredActions: [RewriteAction] = []
    private var settingsWindow: NSWindow?
    private var activeTask: Task<Void, Never>?

    func start() {
        let isPreviewingOverlay = CommandLine.arguments.contains("--preview-overlay")
        settings.changeHandler = { [weak self] in self?.applySettings() }

        setMenuBarIconVisible(settings.showsMenuBarIcon)

        if let problem = registerShortcuts(for: settings.actions) {
            overlay.show(.failure(problem), autoHideAfter: 5)
        }

        if !isPreviewingOverlay,
           !settings.hasUsableProvider {
            DispatchQueue.main.async { [weak self] in
                self?.openSettings()
            }
        } else if !isPreviewingOverlay && !settings.showsMenuBarIcon {
            DispatchQueue.main.async { [weak self] in
                self?.openSettings()
            }
        }

        if isPreviewingOverlay {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showTestPill()
            }
        }
    }

    private func configureMenuBar() {
        guard let statusItem else { return }

        if let button = statusItem.button {
            button.image = makeMenuBarIcon()
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "Mend"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Enable Accessibility…", action: #selector(requestAccessibility), keyEquivalent: ""))
        // Hold Option while the menu is open to reveal the overlay preview.
        let previewItem = NSMenuItem(title: "Preview Overlay States", action: #selector(showTestPill), keyEquivalent: "")
        previewItem.keyEquivalentModifierMask = [.option]
        previewItem.isAlternate = true
        menu.addItem(previewItem)
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Hide Menu Bar Icon", action: #selector(hideMenuBarIcon), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Mend", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }
        menu.delegate = self
        statusMenu = menu
        statusItem.menu = menu
        installStatusMenuClickMonitors()
    }

    private func makeMenuBarIcon() -> NSImage? {
        let icon = Bundle.main.url(
            forResource: "MendMenuBarIcon",
            withExtension: "png"
        ).flatMap(NSImage.init(contentsOf:))
            ?? NSImage(
                systemSymbolName: "text.badge.checkmark",
                accessibilityDescription: "Mend"
            )

        icon?.size = NSSize(width: 18, height: 18)
        icon?.isTemplate = true
        icon?.accessibilityDescription = "Mend"
        return icon
    }

    private func setMenuBarIconVisible(_ isVisible: Bool) {
        if isVisible {
            guard statusItem == nil else { return }
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            configureMenuBar()
        } else if let statusItem {
            statusMenu?.cancelTracking()
            statusMenu = nil
            isStatusMenuOpen = false
            removeStatusMenuClickMonitors()
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        isStatusMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        isStatusMenuOpen = false
    }

    private func installStatusMenuClickMonitors() {
        guard localMenuClickMonitor == nil, globalMenuClickMonitor == nil else { return }

        localMenuClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, self.isStatusMenuOpen else { return event }

            let clickedStatusIcon = event.windowNumber
                == self.statusItem?.button?.window?.windowNumber
            let clickedInsideMenu = event.window?.level == .popUpMenu
            guard clickedStatusIcon || !clickedInsideMenu else { return event }

            self.statusMenu?.cancelTracking()
            return clickedStatusIcon ? nil : event
        }

        globalMenuClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak menu = statusMenu] _ in
            // Menu tracking runs its own modal event loop on the main thread.
            // Cancel synchronously so another menu-bar panel cannot open behind it.
            menu?.cancelTracking()
        }
    }

    private func removeStatusMenuClickMonitors() {
        if let localMenuClickMonitor {
            NSEvent.removeMonitor(localMenuClickMonitor)
            self.localMenuClickMonitor = nil
        }
        if let globalMenuClickMonitor {
            NSEvent.removeMonitor(globalMenuClickMonitor)
            self.globalMenuClickMonitor = nil
        }
    }

    @objc private func hideMenuBarIcon() {
        settings.setMenuBarIconVisible(false)
        DispatchQueue.main.async { [weak self] in
            self?.setMenuBarIconVisible(false)
        }
    }

    private func handleShortcut(for actionID: UUID, via shortcut: GlobalShortcut) {
        guard let action = settings.action(id: actionID) else { return }
        overlay.anchorFrame = selectionService.focusedWindowFrame()

        if let activeTask {
            activeTask.cancel()
            self.activeTask = nil
            overlay.show(.message("Cancelled", symbol: "xmark.circle.fill"), autoHideAfter: 1.2)
            return
        }

        // Keep a visible result in place while selection is validated so the
        // next state can transform in the same pill instead of reopening it.
        overlay.keepVisibleForNextState()

        guard AXIsProcessTrusted() else {
            requestAccessibility()
            overlay.show(.failure("Allow Accessibility, then try again"), autoHideAfter: 4)
            return
        }

        if let problem = settings.setupProblem(for: action) {
            openSettings()
            overlay.show(.failure(problem), autoHideAfter: 4)
            return
        }
        let providerConfigurations = settings.availableProviderConfigurations(prompt: action.prompt)

        activeTask = Task { [weak self] in
            guard let self else { return }

            let timeline = RewriteTimeline()
            // Warm the connection while the selection is being read.
            let warmup = LLMClient(configuration: providerConfigurations[0].llm).preconnect()
            defer {
                warmup.cancel()
            }

            do {
                let selection = try await selectionService.captureSelection()
                timeline.mark("capture")
                try Task.checkCancellation()

                overlay.show(.working(action.workingLabel))

                let result = try await rewrite(
                    selection.text,
                    using: providerConfigurations,
                    for: action,
                    via: shortcut,
                    timeline: timeline
                )
                try Task.checkCancellation()

                guard result.trimmingCharacters(in: .whitespacesAndNewlines)
                    != selection.text.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    overlay.show(.message("No changes suggested", symbol: "equal.circle.fill"), autoHideAfter: 2)
                    await finish(timeline, warmup: warmup, outcome: "no changes")
                    return
                }

                let replacement = try await selectionService.replaceSelection(result, in: selection)
                timeline.mark("replace")
                // An unverified paste almost always landed; a paste that
                // clearly failed throws instead. The log keeps the distinction.
                overlay.show(.success("Fixed"), autoHideAfter: 1.2)
                switch replacement {
                case .verified(let method):
                    await finish(timeline, warmup: warmup, outcome: "fixed via \(method.rawValue)")
                case .unverified:
                    await finish(timeline, warmup: warmup, outcome: "pasted unverified")
                }
            } catch is CancellationError {
                overlay.show(.message("Cancelled", symbol: "xmark.circle.fill"), autoHideAfter: 1.2)
                await finish(timeline, warmup: warmup, outcome: "cancelled")
            } catch {
                overlay.show(.failure(error.localizedDescription), autoHideAfter: 5)
                await finish(timeline, warmup: warmup, outcome: "failed: \(error.localizedDescription)")
            }
        }
    }

    /// Writes the timeline once the warm-up has settled, then releases the task slot.
    private func finish(_ timeline: RewriteTimeline, warmup: Task<Duration?, Never>, outcome: String) async {
        activeTask = nil
        warmup.cancel()
        if let duration = await warmup.value {
            timeline.record("preconnect", duration)
        }
        timeline.log(outcome: outcome)
    }

    private func rewrite(
        _ text: String,
        using configurations: [ProviderConfiguration],
        for action: RewriteAction,
        via shortcut: GlobalShortcut,
        timeline: RewriteTimeline
    ) async throws -> String {
        var attemptedProviders: [LLMProvider] = []
        var lastError: (any Error)?

        for (index, configuration) in configurations.enumerated() {
            try Task.checkCancellation()
            let label: String
            if index > 0 {
                label = "Trying \(configuration.provider.displayName)…"
                overlay.show(.working(label))
            } else {
                label = action.workingLabel
            }
            let narrator = narrateWait(label: label, provider: configuration.provider, shortcut: shortcut)
            defer { narrator.cancel() }

            attemptedProviders.append(configuration.provider)
            defer { timeline.mark(configuration.provider.displayName) }
            do {
                let result = try await LLMClient(configuration: configuration.llm).rewrite(text)
                guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw MendError.emptyResponse
                }
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }

        guard let lastError else { throw MendError.invalidResponse }
        if attemptedProviders.count == 1 {
            throw lastError
        }
        throw CoordinatorError.providersFailed(attemptedProviders, lastError)
    }

    /// Keeps a long wait honest. After two seconds the capsule shows how to
    /// cancel, and after five it names the provider it is waiting on.
    private func narrateWait(label: String, provider: LLMProvider, shortcut: GlobalShortcut) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            let hint = " · \(shortcut.displayString) to cancel"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.overlay.show(.working(label + hint))
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.overlay.show(.working("Waiting for \(provider.displayName)…" + hint))
        }
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(
                settings: settings,
                onMenuBarVisibilityChange: { [weak self] isVisible in
                    self?.settings.setMenuBarIconVisible(isVisible)
                    self?.setMenuBarIconVisible(isVisible)
                },
                onCheckForUpdates: { [weak self] in
                    self?.checkForUpdates()
                },
                onError: { [weak self] error in
                    self?.reportSettingsProblem(error.localizedDescription)
                }
            )
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: controller)
            window.title = "Mend Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 520, height: 640))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        // Do not open with the endpoint selected: a stray keystroke would
        // replace it, and edits apply as they are made.
        settingsWindow?.makeFirstResponder(nil)
    }

    /// Persists the settings and re-registers shortcuts. Runs after every
    /// edit settles and once more when the app quits.
    func applySettings() {
        if let problem = registerShortcuts(for: settings.actions) {
            reportSettingsProblem(problem)
        }
        do {
            try settings.save()
        } catch {
            reportSettingsProblem(error.localizedDescription)
        }
    }

    private func reportSettingsProblem(_ message: String) {
        overlay.anchorFrame = settingsWindow?.frame
        overlay.show(.failure(message), autoHideAfter: 5)
    }

    /// Registers a hotkey for every shortcut of every action. A shortcut that
    /// cannot be registered, because another app or an older duplicate holds
    /// it, is skipped so the rest keep working; the message names it.
    private func registerShortcuts(for actions: [RewriteAction]) -> String? {
        if actions == registeredActions { return nil }

        hotKeys = []
        var unavailable: [(action: RewriteAction, shortcut: GlobalShortcut)] = []
        for action in actions {
            for shortcut in action.shortcuts {
                if let hotKey = makeHotKey(for: shortcut, actionID: action.id) {
                    hotKeys.append(hotKey)
                } else {
                    unavailable.append((action, shortcut))
                }
            }
        }

        // Leave the set unremembered while something failed, so the next
        // edit retries the shortcut instead of assuming it is registered.
        registeredActions = unavailable.isEmpty ? actions : []

        switch unavailable.count {
        case 0:
            return nil
        case 1:
            let (action, shortcut) = unavailable[0]
            return "\(shortcut.displayString) for “\(action.displayName)” is already in use"
        default:
            return "\(unavailable.count) shortcuts are already in use"
        }
    }

    private func makeHotKey(for shortcut: GlobalShortcut, actionID: UUID) -> HotKeyManager? {
        HotKeyManager(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
            Task { @MainActor in
                self?.handleShortcut(for: actionID, via: shortcut)
            }
        }
    }

    @objc private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc private func showTestPill() {
        overlay.anchorFrame = nil
        Task { @MainActor in
            overlay.show(.working("Fix grammar…"))
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            overlay.show(.success("Fixed"))
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            overlay.show(.message("No changes suggested"))
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            overlay.show(.failure("Couldn’t replace text"), autoHideAfter: 1.8)
        }
    }

    @objc private func checkForUpdates() {
        overlay.anchorFrame = nil
        Task { @MainActor in
            overlay.show(.working("Checking for updates…"))
            let alert = NSAlert()
            var downloadURL: URL?

            do {
                switch try await UpdateChecker().check() {
                case .upToDate(let version):
                    alert.messageText = "Mend is up to date"
                    alert.informativeText = "Version \(version) is the latest release."
                    alert.addButton(withTitle: "OK")
                case .available(let version, let url):
                    downloadURL = url
                    alert.messageText = "Mend \(version) is available"
                    alert.informativeText = "You have version \(UpdateChecker.currentVersion). Re-run the installer or download the new release from GitHub."
                    alert.addButton(withTitle: "Download")
                    alert.addButton(withTitle: "Not Now")
                }
            } catch {
                alert.messageText = "Couldn’t check for updates"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
            }

            overlay.show(.message("Checked for updates", symbol: "arrow.triangle.2.circlepath.circle.fill"), autoHideAfter: 0.8)
            NSApplication.shared.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn, let downloadURL {
                NSWorkspace.shared.open(downloadURL)
            }
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
