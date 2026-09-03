# Install Mend on another Apple silicon Mac

Mend currently ships as an Apple-silicon-only app for M-series Macs.

1. Download `Mend-<version>-apple-silicon.dmg` from the GitHub Releases page.
2. Open the disk image and drag **Mend** into **Applications**.
3. Open Mend from Applications.
4. If macOS blocks the first launch, open **System Settings → Privacy & Security**, scroll to **Security**, and choose **Open Anyway** for Mend. Confirm by clicking **Open**.
5. Use the Mend menu-bar icon to open **Settings**, choose a provider, and add its API key. The endpoint and model presets remain editable.
6. Choose **Enable Accessibility** from the Mend menu and allow Mend in **System Settings → Privacy & Security → Accessibility**.

Because Mend is installed in Applications, macOS indexes it as an application. You can launch it from the Dock or by searching for **Mend** in Spotlight or Raycast.

You can hide Mend's menu-bar icon from its menu or from Settings. The rewrite shortcut remains active. Search for Mend in Spotlight or Raycast to reopen Settings and turn the icon back on.

The additional approval in step 4 is required because releases are ad-hoc signed. Developer ID signing and Apple notarization would remove this warning.

## Create a release

Update the version and build number in `Resources/Info.plist`, commit the change, and push a matching tag:

```sh
VERSION="<version>"
git tag "v$VERSION"
git push origin "v$VERSION"
```

The release workflow builds an ARM64 DMG and attaches it to a new GitHub release.

To build the same package locally without publishing it:

```sh
VERSION="<version>" BUILD_NUMBER="<build-number>" ./Scripts/package-dmg.sh
```

The DMG is written to `dist/`.
