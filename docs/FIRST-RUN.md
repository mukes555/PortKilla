# First run on an unsigned app

PortNanny is open source and built by its release workflow, but it is not
notarized: that needs a paid Apple Developer account, which this project
does not have. macOS therefore warns the first time you open it. This page
is the one place that explains what to do; the README, the release notes,
and the Homebrew cask all point here.

## Homebrew (recommended)

```bash
brew install --cask portnanny
```

The cask clears the quarantine flag for you. No dialog, nothing else to do.
Later: `brew upgrade --cask portnanny` to update (the cask is pinned to
each release, so `brew upgrade` on its own sees new versions too).

## DMG download

Drag PortNanny to Applications, then:

- **macOS 15 (Sequoia) or newer:** open PortNanny once. The dialog offers
  only "Done" and "Move to Trash". Choose Done, then open **System Settings
  → Privacy & Security**, scroll to the security section, and click **Open
  Anyway** next to PortNanny. Confirm with your password. Once.
- **macOS 13 and 14:** Control-click PortNanny.app → **Open** → **Open**.
  Once.
- **Either version, from a terminal:**
  ```bash
  xattr -dr com.apple.quarantine /Applications/PortNanny.app
  ```

## Why it is safe to do this

The app is ad-hoc signed by the build (`codesign --sign -`), so the binary
cannot be silently modified after download without the signature breaking,
and every release publishes `SHA256SUMS` next to the assets. You can also
build it yourself in about a minute: see CONTRIBUTING.md.

## Upgrading from PortKilla

PortNanny was called PortKilla until 2.1: the old name said "killer" for
an app that mostly keeps servers alive and attributed, and it sat one
letter from a much larger project. Same app, same author, new name and
bundle id.

- **Homebrew:** `brew upgrade --cask portnanny` (the tap records the
  rename, so `brew upgrade` on its own finds it too). It removes
  PortKilla.app, installs PortNanny.app, and links a `portkilla` command
  next to `portnanny`. Homebrew trusts third-party casks by name, so if it
  refuses to load the renamed cask, run `brew trust mukes555/tap` once
  and upgrade again.
- **DMG:** quit PortKilla, drag PortNanny to Applications, then delete
  PortKilla.app.
- **Settings, watched ports, guards, history, refusals, and leases** are
  copied into the new app's preferences on its first launch (the CLI does
  the same). Nothing is deleted; `defaults delete com.mukes555.PortKilla`
  removes the old copy once you are done with it.
- **macOS asks again** for notifications and for Launch at login, because
  it keys both to the bundle id.
- **Scripts keep working:** `portkilla`, `PORTKILLA_OWNER`,
  `PORTKILLA_SESSION`, `portkilla://kill/3000`, and
  github.com/mukes555/PortKilla (it redirects). Rule files written by
  `portkilla agent-docs` need no change; `portnanny setup` rewrites them
  with the new names whenever you like. The Claude Code plugin is now
  `portnanny@portnanny`; remove `portkilla@portkilla` and install it again.

## Login item after an update

Replacing the bundle (a Homebrew upgrade does this) can make macOS ask
you to re-approve PortNanny under **System Settings → General → Login
Items**. Settings → General in PortNanny shows a button for that when it
applies.

## Uninstall

```bash
brew uninstall --zap portnanny   # Homebrew: app, CLI link, preferences, login item
```

Or drag PortNanny.app to the Trash, then `defaults delete
com.mukes555.PortNanny` for its preferences (this includes the kill history)
and remove it from Login Items if it is listed.
