# Install Mend on another Apple silicon Mac

Mend currently ships as an Apple-silicon-only app for M-series Macs.

## Install from Terminal

```sh
curl -fsSL https://raw.githubusercontent.com/Neel2107/Mend/main/Scripts/install-app.sh | sh
```

The installer downloads the latest release archive, verifies it against the published SHA-256 checksum, and installs Mend into `/Applications`. It can also update an existing installation.

## Install by hand

1. Download `Mend-app-aarch64-apple-darwin.tar.gz` from the GitHub Releases page.
2. Extract it and move **Mend** into **Applications**.
3. Open Mend from Applications.
4. If macOS blocks the first launch, open **System Settings → Privacy & Security**, scroll to **Security**, and choose **Open Anyway** for Mend. Confirm by clicking **Open**.
5. Use the Mend menu-bar icon to open **Settings**, choose a provider, and add its API key. The endpoint and model presets remain editable.
   When macOS asks whether Mend may use the Keychain item, choose **Always Allow**; plain **Allow** lasts one launch and the question returns after every update.
6. Choose **Enable Accessibility** from the Mend menu and allow Mend in **System Settings → Privacy & Security → Accessibility**.

Because Mend is installed in Applications, macOS indexes it as an application. Launch it from Applications or search for **Mend** in Spotlight or Raycast. Mend then runs in the background without appearing in the Dock or Cmd-Tab.

You can hide Mend's menu-bar icon from its menu or from Settings. The rewrite shortcut remains active. Search for Mend in Spotlight or Raycast to reopen Settings and turn the icon back on.

The additional approval in step 4 is required because releases are ad-hoc signed. Developer ID signing and Apple notarization would remove this warning.

## Create a release

Update the version and build number in `Resources/Info.plist`, commit the change, and push a matching tag:

```sh
VERSION="<version>"
git tag "v$VERSION"
git push origin "v$VERSION"
```

The release workflow builds the Apple silicon app, packages it as `Mend-app-aarch64-apple-darwin.tar.gz` with a `SHA256SUMS` file, and attaches both to a new GitHub release. The terminal installer downloads that archive.

To build the same app locally without publishing it:

```sh
VERSION="<version>" BUILD_NUMBER="<build-number>" TARGET_TRIPLE="arm64-apple-macosx13.0" ./Scripts/build-app.sh
```

The app bundle is written to `dist/Mend.app`.
