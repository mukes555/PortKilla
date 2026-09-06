# typed: strict
# frozen_string_literal: true

# Homebrew cask for PortKilla.
#
# To publish: create a GitHub repo named `homebrew-tap` under your account,
# copy this file to `Casks/portkilla.rb` in it, then users install with:
#
#   brew tap mukes555/tap
#   brew install --cask portkilla
#
# `version :latest` + `sha256 :no_check` means the cask always pulls the
# newest GitHub release (the release workflow uploads PortKilla.app.zip with
# a stable name), so the tap never needs updating per release.
cask "portkilla" do
  version :latest
  sha256 :no_check

  url "https://github.com/mukes555/PortKilla/releases/latest/download/PortKilla.app.zip"
  name "PortKilla"
  desc "Menu bar port manager — see and kill processes occupying ports"
  homepage "https://github.com/mukes555/PortKilla"

  depends_on macos: :ventura

  app "PortKilla.app"
  # Puts `portkilla` on PATH so the CLI (list / kill / whoami) works from any shell.
  binary "#{appdir}/PortKilla.app/Contents/MacOS/PortKilla", target: "portkilla"

  # The app is ad-hoc signed (no Apple Developer account), so Gatekeeper
  # quarantine must be stripped for it to launch without a scary dialog.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/PortKilla.app"],
                   sudo: false
  end

  # `brew reinstall` replaces the bundle; quit the running copy first so the
  # menu-bar icon isn't left running from a deleted bundle, and drop the
  # login-item registration that pointed at it.
  uninstall quit:       "com.mukes555.PortKilla",
            login_item: "PortKilla"

  zap trash: [
    "~/Library/Caches/com.mukes555.PortKilla",
    "~/Library/HTTPStorages/com.mukes555.PortKilla",
    "~/Library/Preferences/com.mukes555.PortKilla.plist",
    "~/Library/Saved Application State/com.mukes555.PortKilla.savedState",
  ]
end
