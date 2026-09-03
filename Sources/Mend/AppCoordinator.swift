import AppKit
import ApplicationServices
import Carbon
import SwiftUI

@MainActor
final class AppCoordinator: NSObject, NSMenuDelegate {
    private enum CoordinatorError: LocalizedError {
        case shortcutUnavailable(String)
        case providersFailed([LLMProvider], any Error)

        var errorDescription: String? {
            switch self {
            case .shortcutUnavailable(let action):
                return "The shortcut for “\(action)” is already in use"
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
    private var hotKeys: [UUID: HotKeyManager] = [:]
    private var registeredActions: [RewriteAction] = []
    private var settingsWindow: NSWindow?
    private var activeTask: Task<Void, Never>?

    func start() {
        let isPreviewingOverlay = CommandLine.arguments.contains("--preview-overlay")

        setMenuBarIconVisible(settings.showsMenuBarIcon)

        if let unavailable = registerShortcuts(for: settings.actions) {
            overlay.show(.failure("Shortcut for “\(unavailable.displayName)” unavailable"), autoHideAfter: 5)
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

    private func handleShortcut(for actionID: UUID) {
        guard let action = settings.action(id: actionID) else { return }

        if let activeTask {
            activeTask.cancel()
            self.activeTask = nil
            overlay.show(.message("Cancelled"), autoHideAfter: 1.2)
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

        let providerConfigurations = settings.availableProviderConfigurations(prompt: action.prompt)
        guard !providerConfigurations.isEmpty else {
            openSettings()
            overlay.show(.failure("Add an API key in Settings"), autoHideAfter: 4)
            return
        }

        activeTask = Task { [weak self] in
            guard let self else { return }

            do {
                let selection = try await selectionService.captureSelection()
                try Task.checkCancellation()

                overlay.show(.working(action.workingLabel))

                let result = try await rewrite(
                    selection.text,
                    using: providerConfigurations
                )
                try Task.checkCancellation()

                guard result.trimmingCharacters(in: .whitespacesAndNewlines)
                    != selection.text.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    overlay.show(.message("No changes suggested"), autoHideAfter: 2)
                    activeTask = nil
                    return
                }

                let replacement = try await selectionService.replaceSelection(result, in: selection)
                switch replacement {
                case .verified:
                    overlay.show(.success("Fixed"), autoHideAfter: 1.2)
                case .unverified:
                    overlay.show(.message("Pasted — check the result"), autoHideAfter: 2.5)
                }
            } catch is CancellationError {
                overlay.show(.message("Cancelled"), autoHideAfter: 1.2)
            } catch {
                overlay.show(.failure(error.localizedDescription), autoHideAfter: 5)
            }

            activeTask = nil
        }
    }

    private func rewrite(
        _ text: String,
        using configurations: [ProviderConfiguration]
    ) async throws -> String {
        var attemptedProviders: [LLMProvider] = []
        var lastError: (any Error)?

        for (index, configuration) in configurations.enumerated() {
            try Task.checkCancellation()
            if index > 0 {
                overlay.show(.working("Trying \(configuration.provider.displayName)…"))
            }

            attemptedProviders.append(configuration.provider)
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

    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(
                settings: settings,
                onSave: { [weak self] in
                    try self?.saveSettings()
                },
                onMenuBarVisibilityChange: { [weak self] isVisible in
                    self?.settings.setMenuBarIconVisible(isVisible)
                    self?.setMenuBarIconVisible(isVisible)
                }
            )
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: controller)
            window.title = "Mend Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 520, height: 700))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func saveSettings() throws {
        if let unavailable = registerShortcuts(for: settings.actions) {
            throw CoordinatorError.shortcutUnavailable(unavailable.displayName)
        }
        try settings.save()
    }

    /// Registers a hotkey for every action that has a shortcut. Returns the
    /// first action whose shortcut could not be registered, after restoring
    /// the previous set so the user keeps working shortcuts.
    @discardableResult
    private func registerShortcuts(for actions: [RewriteAction]) -> RewriteAction? {
        if actions == registeredActions, hotKeys.count == actions.filter({ $0.shortcut != nil }).count {
            return nil
        }

        let previousActions = registeredActions
        hotKeys = [:]
        registeredActions = []

        if let unavailable = installHotKeys(for: actions) {
            hotKeys = [:]
            installHotKeys(for: previousActions)
            registeredActions = previousActions
            return unavailable
        }

        registeredActions = actions
        return nil
    }

    @discardableResult
    private func installHotKeys(for actions: [RewriteAction]) -> RewriteAction? {
        for action in actions {
            guard let shortcut = action.shortcut else { continue }
            guard let hotKey = makeHotKey(for: shortcut, actionID: action.id) else {
                return action
            }
            hotKeys[action.id] = hotKey
        }
        return nil
    }

    private func makeHotKey(for shortcut: GlobalShortcut, actionID: UUID) -> HotKeyManager? {
        HotKeyManager(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
            Task { @MainActor in
                self?.handleShortcut(for: actionID)
            }
        }
    }

    @objc private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc private func showTestPill() {
        Task { @MainActor in
            overlay.show(.working("Fixing grammar…"))
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            overlay.show(.success("Fixed"))
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            overlay.show(.message("No changes suggested"))
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            overlay.show(.failure("Couldn’t replace text"), autoHideAfter: 1.8)
        }
    }

    @objc private func checkForUpdates() {
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

            overlay.show(.message("Checked for updates"), autoHideAfter: 0.8)
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
