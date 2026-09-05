# Changelog

Each release publishes its section here as the GitHub release notes.

## 0.3.4 — 2026-09-05

- Every shortcut works. Before, only the most recently added shortcut across all actions responded.
- Shortcuts wrap onto new rows in Settings instead of pushing the window wider than the screen.
- A shortcut can belong to only one action. Recording one that is taken is refused with a beep.
- ⌘C and ⌘V cannot be shortcuts, since Mend uses them to read and replace the selection. Having one made every press in apps like Codex show "Cancelled".
- Pressing a shortcut with no prompt, model, endpoint or key opens Settings and names the missing one.
- Only a shortcut that another app already holds is skipped, instead of all of them.
- Recording a shortcut stops when you click elsewhere or leave the window.
- Long prompts scroll inside the editor instead of stretching the window.

## 0.3.3 — 2026-09-04

- Settings apply as you change them. The Save button is gone.
- Each provider keeps its own endpoint and model.
- Settings shows the version and can check for updates.

## 0.3.2 — 2026-09-04

- Launching Mend quits other running copies, so a shortcut is answered once.

## 0.3.1 — 2026-09-04

- The provider connection is warmed on each shortcut, and rewrite timings are logged.
- Provider keys live in one Keychain item.
- The installer skips download hosts that do not answer.
