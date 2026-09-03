# Mend

<p align="center">
  <img src="Resources/AppIcon.png" alt="Mend app icon" width="144">
</p>

<p align="center"><strong>Correct selected text anywhere on macOS with one shortcut.</strong></p>

<p align="center">
  <a href="https://github.com/Neel2107/Mend/actions/workflows/ci.yml"><img src="https://github.com/Neel2107/Mend/actions/workflows/ci.yml/badge.svg" alt="Build status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
</p>

Mend is a lightweight macOS writing assistant. Select text in any application, press a global shortcut, and Mend replaces it with a corrected version using your preferred AI provider.

## Features

- Corrects grammar, spelling, punctuation, and phrasing in place
- Works across macOS applications through a configurable global shortcut
- Uses existing Codex and Claude Code subscriptions through their local CLIs
- Supports OpenAI, Gemini, and custom OpenAI-compatible API fallbacks
- Falls back through enabled subscription and API providers when a request fails
- Stores API keys in macOS Keychain
- Lets you customize the editing instruction, endpoint, and model
- Shows compact progress and result notifications without interrupting your workflow
- Restores clipboard contents after capturing and replacing text
- Runs from the Dock, menu bar, Spotlight, or Raycast

## Requirements

- Apple silicon Mac
- macOS 13 or later
- A signed-in Codex or Claude Code CLI, or an API key for a supported provider
- Accessibility permission for reading and replacing selected text

## Installation

Install from Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/Neel2107/Mend/main/Scripts/install-app.sh | sh
```

The installer verifies the release checksum and installs Mend into `/Applications`. Launch it with `open /Applications/Mend.app`.

To install manually:

1. Download the latest Apple silicon DMG from [GitHub Releases](https://github.com/Neel2107/Mend/releases/latest).
2. Open the DMG and drag **Mend** into **Applications**.
3. Launch Mend from Applications, Spotlight, or Raycast.
4. If macOS blocks the first launch, allow Mend under **System Settings → Privacy & Security → Open Anyway**.

For Gatekeeper, permissions, and release details, see the [installation guide](docs/INSTALL.md).

## Setup

1. Open **Mend Settings** from the app or menu-bar icon.
2. Enable the installed Codex and Claude Code subscription providers you want Mend to try.
3. Optionally configure OpenAI, Gemini, or Custom as an API fallback.
4. Allow Mend under **System Settings → Privacy & Security → Accessibility**.
5. Configure the rewrite shortcut if you do not want the default, **Control–Option–G**.

Mend uses subscription providers through their installed CLIs and stores a separate Keychain entry for each API provider.

## Usage

1. Select text in any application.
2. Press the configured shortcut.
3. Mend tries enabled local subscription providers first, followed by configured API providers.
4. The corrected text replaces the selection in place.

Press the shortcut again while a request is running to cancel it. You can hide the menu-bar icon from Settings without disabling the global shortcut.

## Build from source

Xcode Command Line Tools and Swift 5.10 or later are required.

```sh
git clone https://github.com/Neel2107/Mend.git
cd Mend
chmod +x Scripts/*.sh
./Scripts/run.sh
```

Create an Apple silicon DMG locally with:

```sh
./Scripts/package-dmg.sh
```

## Privacy

- API keys are stored locally in macOS Keychain.
- Selected text is sent to each enabled provider Mend attempts until one succeeds.
- Subscription credentials remain managed by the Codex and Claude Code CLIs; Mend does not read or store them.
- Mend does not include analytics, user accounts, or a hosted backend.
- Clipboard contents are restored after each operation.

## License

Mend is available under the [MIT License](LICENSE).
