import AppKit
import ApplicationServices
import Carbon
import SwiftUI

@MainActor
final class AppCoordinator: NSObject {
    private enum CoordinatorError: LocalizedError {
        case shortcutUnavailable

        var errorDescription: String? {
            "That shortcut is already being used by another app"
        }
    }

    private let settings = AppSettings()
    private let overlay = OverlayController()
    private let selectionService = SelectionService()

    private var statusItem: NSStatusItem?
    private var hotKey: HotKeyManager?
    private var registeredShortcut: GlobalShortcut?
    private var settingsWindow: NSWindow?
    private var activeTask: Task<Void, Never>?

    func start() {
        setMenuBarIconVisible(settings.showsMenuBarIcon)

        registerShortcut(settings.shortcut)
        overlay.updateShortcutLabel(settings.shortcut.displayString)

        if hotKey == nil {
            overlay.show(.failure("Shortcut unavailable"))
        }

        if settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.openSettings()
            }
        } else if !settings.showsMenuBarIcon {
            DispatchQueue.main.async { [weak self] in
                self?.openSettings()
            }
        }

        if CommandLine.arguments.contains("--preview-overlay") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showTestPill()
            }
        }
    }

    private func configureMenuBar() {
        guard let statusItem else { return }

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "text.badge.checkmark", accessibilityDescription: "Mend")
            button.toolTip = "Mend"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Enable Accessibility…", action: #selector(requestAccessibility), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Preview overlay states", action: #selector(showTestPill), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Hide Menu Bar Icon", action: #selector(hideMenuBarIcon), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Mend", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func setMenuBarIconVisible(_ isVisible: Bool) {
        if isVisible {
            guard statusItem == nil else { return }
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            configureMenuBar()
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    @objc private func hideMenuBarIcon() {
        settings.setMenuBarIconVisible(false)
        DispatchQueue.main.async { [weak self] in
            self?.setMenuBarIconVisible(false)
        }
    }

    private func handleRewriteShortcut() {
        if let activeTask {
            activeTask.cancel()
            self.activeTask = nil
            overlay.show(.message("Cancelled"), autoHideAfter: 1.2)
            return
        }

        guard AXIsProcessTrusted() else {
            requestAccessibility()
            overlay.show(.failure("Allow Accessibility, then try again"), autoHideAfter: 4)
            return
        }

        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            openSettings()
            overlay.show(.failure("Add an API key in Settings"), autoHideAfter: 4)
            return
        }

        activeTask = Task { [weak self] in
            guard let self else { return }

            do {
                let selection = try await selectionService.captureSelection()
                try Task.checkCancellation()

                overlay.show(.working("Fixing grammar…"))

                let configuration = settings.configuration
                let result = try await LLMClient(configuration: configuration).rewrite(selection.text)
                try Task.checkCancellation()

                guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw MendError.emptyResponse
                }

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
        guard registerShortcut(settings.shortcut) else {
            throw CoordinatorError.shortcutUnavailable
        }
        try settings.save()
        overlay.updateShortcutLabel(settings.shortcut.displayString)
    }

    @discardableResult
    private func registerShortcut(_ shortcut: GlobalShortcut) -> Bool {
        if registeredShortcut == shortcut, hotKey != nil {
            return true
        }

        let previousShortcut = registeredShortcut
        hotKey = nil
        registeredShortcut = nil

        if let newHotKey = makeHotKey(for: shortcut) {
            hotKey = newHotKey
            registeredShortcut = shortcut
            return true
        }

        if let previousShortcut,
           let restoredHotKey = makeHotKey(for: previousShortcut) {
            hotKey = restoredHotKey
            registeredShortcut = previousShortcut
        }
        return false
    }

    private func makeHotKey(for shortcut: GlobalShortcut) -> HotKeyManager? {
        HotKeyManager(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
            Task { @MainActor in
                self?.handleRewriteShortcut()
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
            overlay.show(.failure("Couldn’t replace text"), autoHideAfter: 1.8)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
