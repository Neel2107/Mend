# Mend

**Fix selected text without leaving the app you are writing in.**

[![Build](https://github.com/Neel2107/Mend/actions/workflows/ci.yml/badge.svg)](https://github.com/Neel2107/Mend/actions/workflows/ci.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Mend is a small macOS menu-bar app that fixes selected text without making you leave the app you are writing in.

1. Select text in any app.
2. Press **Control–Option–G**.
3. Mend sends the selection through your saved instruction.
4. The corrected text replaces the selection in place.

A compact, non-activating status pill appears at the bottom-right of the current screen while Mend works. Press the shortcut again to cancel an in-flight request.

## Requirements

- macOS 13 or later
- An OpenAI-compatible chat-completions endpoint and API key
- Accessibility permission, used only to read and replace the selection

## Privacy

- Your API key is stored in macOS Keychain.
- Mend sends selected text only to the provider endpoint you configure.
- Mend has no analytics, account system, or hosted backend.
- Clipboard contents are restored after selection capture and replacement.

## Build and run

```sh
chmod +x Scripts/*.sh
./Scripts/run.sh
```

Mend appears in the menu bar. Open **Settings…**, enter the API key, and save. The default endpoint is OpenAI and the default model is `gpt-4.1-mini`; both can be changed.

On the first rewrite, macOS asks for Accessibility permission. Enable Mend in **System Settings → Privacy & Security → Accessibility**, then retry the shortcut.

Release builds use a stable designated code-signing requirement so macOS can preserve that Accessibility grant across local rebuilds.

## v0 scope

- Native menu-bar app
- Fixed global shortcut: Control–Option–G
- Accessibility selection capture with clipboard fallback
- OpenAI-compatible provider configuration
- API key stored in macOS Keychain
- Editable saved instruction
- Bottom-screen working, success, and error states
- In-place replacement with clipboard restoration

The v0 uses plain text. Rich-text formatting and configurable shortcuts are intentionally deferred.

## Experiment with the overlay UI

All visual values are grouped in `OverlayDesign` at the top of `Sources/Mend/OverlayController.swift`. Change the panel size, screen margins, spacing, typography, or border opacity there, then rebuild and preview:

```sh
./Scripts/run.sh --preview-overlay
```

Open the Mend menu-bar icon and choose **Preview overlay states** to cycle through working, success, and error appearances without making an API request.

See [`docs/UI_EXPERIMENTS.md`](docs/UI_EXPERIMENTS.md) for suggested directions and the exact files involved.

## License

MIT
