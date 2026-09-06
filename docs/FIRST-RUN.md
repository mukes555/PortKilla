# First run on an unsigned app

PortKilla is open source and built by its release workflow, but it is not
notarized: that needs a paid Apple Developer account, which this project
does not have. macOS therefore warns the first time you open it. This page
is the one place that explains what to do; the README, the release notes,
and the Homebrew cask all point here.

## Homebrew (recommended)

```bash
brew install --cask portkilla
```

The cask clears the quarantine flag for you. No dialog, nothing else to do.
Later: `brew reinstall --cask portkilla` to update (the cask tracks the
latest release, so a plain `brew upgrade` does not see new versions).

## DMG download

Drag PortKilla to Applications, then:

- **macOS 15 (Sequoia) or newer:** open PortKilla once. The dialog offers
  only "Done" and "Move to Trash". Choose Done, then open **System Settings
  → Privacy & Security**, scroll to the security section, and click **Open
  Anyway** next to PortKilla. Confirm with your password. Once.
- **macOS 13 and 14:** Control-click PortKilla.app → **Open** → **Open**.
  Once.
- **Either version, from a terminal:**
  ```bash
  xattr -dr com.apple.quarantine /Applications/PortKilla.app
  ```

## Why it is safe to do this

The app is ad-hoc signed by the build (`codesign --sign -`), so the binary
cannot be silently modified after download without the signature breaking,
and every release publishes `SHA256SUMS` next to the assets. You can also
build it yourself in about a minute: see CONTRIBUTING.md.

## Login item after an update

Replacing the bundle (a Homebrew reinstall does this) can make macOS ask
you to re-approve PortKilla under **System Settings → General → Login
Items**. Settings → General in PortKilla shows a button for that when it
applies.

## Uninstall

```bash
brew uninstall --zap portkilla   # Homebrew: app, CLI link, preferences, login item
```

Or drag PortKilla.app to the Trash, then `defaults delete
com.mukes555.PortKilla` for its preferences (this includes the kill history)
and remove it from Login Items if it is listed.
