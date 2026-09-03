import AppKit
import ApplicationServices
import Carbon
import SwiftUI

@MainActor
final class AppCoordinator: NSObject {
    private let settings = AppSettings()
    private let overlay = OverlayController()
    private let selectionService = SelectionService()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private var hotKey: HotKeyManager?
    private var settingsWindow: NSWindow?
    private var activeTask: Task<Void, Never>?

    func start() {
        configureMenuBar()

        hotKey = HotKeyManager(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            Task { @MainActor in
                self?.handleRewriteShortcut()
            }
        }

        if hotKey == nil {
            overlay.show(.failure("Shortcut unavailable"))
        }

        if settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "text.badge.checkmark", accessibilityDescription: "Mend")
            button.toolTip = "Mend"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Enable Accessibility…", action: #selector(requestAccessibility), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Preview overlay states", action: #selector(showTestPill), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Mend", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
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

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings)
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: controller)
            window.title = "Mend Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 520, height: 510))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
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
