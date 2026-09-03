# Mend

<p align="center">
  <img src="Resources/AppIcon.png" alt="Mend app icon" width="144">
</p>

<p align="center"><strong>Correct selected text anywhere on macOS with one shortcut.</strong></p>

<p align="center">
  <a href="https://mend.itsneel.com">Website</a> ·
  <a href="https://github.com/Neel2107/Mend/releases/latest">Download</a>
</p>

<p align="center">
  <a href="https://github.com/Neel2107/Mend/actions/workflows/ci.yml"><img src="https://github.com/Neel2107/Mend/actions/workflows/ci.yml/badge.svg" alt="Build status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
</p>

Mend is a lightweight macOS writing assistant. Select text in any application, press a global shortcut, and Mend replaces it with a corrected version using your preferred AI provider.

## Features

- Corrects grammar, spelling, punctuation, and phrasing in place
- Works across macOS applications through a configurable global shortcut
- Supports OpenAI, Gemini, and custom OpenAI-compatible endpoints
- Falls back to another configured provider when a request fails
- Stores API keys in macOS Keychain
- Lets you save several actions, each with its own instruction and one or more shortcuts: fix grammar, tighten, translate
- Lets you customize the endpoint and model
- Shows compact progress and result notifications without interrupting your workflow
- Restores clipboard contents after capturing and replacing text
- Runs quietly in the background and stays accessible from the menu bar, Spotlight, or Raycast

## Requirements

- Apple silicon Mac
- macOS 13 or later
- An API key for OpenAI, Gemini, or an OpenAI-compatible provider
- Accessibility permission for reading and replacing selected text

## Installation

Install from Terminal:

```sh
curl -fsSL https://mend.itsneel.com/install | sh
```

The installer verifies the release checksum and installs Mend into `/Applications`. Launch it with `open /Applications/Mend.app`.

Run the same command again to update. To install by hand instead, download `Mend-app-aarch64-apple-darwin.tar.gz` from [GitHub Releases](https://github.com/Neel2107/Mend/releases/latest), extract it, and move **Mend** into **Applications**. If macOS blocks the first launch, allow Mend under **System Settings → Privacy & Security → Open Anyway**.

For Gatekeeper, permissions, and release details, see the [installation guide](docs/INSTALL.md).

## Setup

1. Open **Mend Settings** from the app or menu-bar icon.
2. Choose OpenAI, Gemini, or Custom.
3. Enter the API key, confirm the endpoint and model, and select **Save**. A custom endpoint can be saved without a key for local servers such as Ollama or LM Studio.
4. Allow Mend under **System Settings → Privacy & Security → Accessibility**.
5. Configure the shortcut for **Fix grammar** if you do not want the default, **Control–Option–G**.
6. Add more actions under **Actions**, each with its own instruction. An action can have several shortcuts.

Mend stores a separate Keychain entry for each provider. Turn on **Open Mend at login** in Settings to keep it running after a restart.

## Usage

1. Select text in any application.
2. Press the shortcut of the action you want.
3. Mend sends the selection and that action's instruction to the selected provider. If that request fails, it tries another provider with a saved API key.
4. The corrected text replaces the selection in place.

Press the shortcut again while a request is running to cancel it. You can hide the menu-bar icon from Settings without disabling the global shortcut.

Mend replaces the selection through Accessibility when the app supports it and falls back to pasting otherwise. The pasted text is plain, so in rich-text editors such as Notes or Pages the corrected selection loses bold, italics, and links.

Choose **Check for Updates…** from the menu-bar icon to compare your version with the latest GitHub release.

Closing Settings leaves Mend running in the background. Mend stays out of the Dock and Cmd-Tab while its global shortcut remains active.

## Build from source

Xcode Command Line Tools and Swift 5.10 or later are required.

```sh
git clone https://github.com/Neel2107/Mend.git
cd Mend
chmod +x Scripts/*.sh
./Scripts/run.sh
```

Build a signed app bundle in `dist/` with:

```sh
./Scripts/build-app.sh
```

## Privacy

- API keys are stored locally in macOS Keychain.
- Selected text is sent to the selected provider and, after a failed request, any configured fallback provider that Mend tries.
- Mend does not include analytics, user accounts, or a hosted backend.
- Clipboard contents are restored after each operation.

## License

Mend is available under the [MIT License](LICENSE).
