# Install Mend on another Apple silicon Mac

Mend currently ships as an Apple-silicon-only app for M-series Macs.

1. Download `Mend-<version>-apple-silicon.dmg` from the GitHub Releases page.
2. Open the disk image and drag **Mend** into **Applications**.
3. Open Mend from Applications.
4. If macOS blocks the first launch, open **System Settings → Privacy & Security**, scroll to **Security**, and choose **Open Anyway** for Mend. Confirm by clicking **Open**.
5. Use the Mend menu-bar icon to open **Settings**, choose a provider, and add its API key. The endpoint and model presets remain editable.
6. Choose **Enable Accessibility** from the Mend menu and allow Mend in **System Settings → Privacy & Security → Accessibility**.

Because Mend is installed in Applications, macOS indexes it as an application. You can launch it by searching for **Mend** in Spotlight or Raycast. Mend stays in the menu bar after launch and does not add a Dock icon.

The extra approval in step 4 is needed because this small private build is ad-hoc signed. A Developer ID-signed and Apple-notarized release removes that warning.

## Create a release

Update the version in `Resources/Info.plist`, commit the change, and push a matching tag:

```sh
git tag v0.1.1
git push origin v0.1.1
```

The release workflow builds an ARM64 DMG and attaches it to a new GitHub release.

To build the same package locally without publishing it:

```sh
VERSION=0.1.1 ./Scripts/package-dmg.sh
```

The DMG is written to `dist/`.
