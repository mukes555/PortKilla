# typed: strict
# frozen_string_literal: true

# Homebrew cask for PortNanny.
#
# To publish: create a GitHub repo named `homebrew-tap` under your account,
# copy this file to `Casks/portnanny.rb` in it, then users install with:
#
#   brew tap mukes555/tap
#   brew install --cask portnanny
#
# `version :latest` + `sha256 :no_check` means the cask always pulls the
# newest GitHub release (the release workflow uploads PortNanny.app.zip with
# a stable name), so the tap never needs updating per release.
cask "portnanny" do
  version :latest
  sha256 :no_check

  url "https://github.com/mukes555/PortNanny/releases/latest/download/PortNanny.app.zip"
  name "PortNanny"
  desc "Menu bar port manager that knows whose server it is"
  homepage "https://github.com/mukes555/PortNanny"

  depends_on macos: :ventura

  app "PortNanny.app"
  # Puts `portnanny` on PATH: the standalone CLI bundled beside the app binary
  # (no AppKit, so `portnanny mcp` stays small when an agent keeps one running).
  binary "#{appdir}/PortNanny.app/Contents/Helpers/portnanny"

  # The app is ad-hoc signed (no Apple Developer account), so Gatekeeper
  # quarantine must be stripped for it to launch without a scary dialog.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/PortNanny.app"],
                   sudo: false
  end

  # `brew reinstall` replaces the bundle; quit the running copy first so the
  # menu-bar icon isn't left running from a deleted bundle, and drop the
  # login-item registration that pointed at it.
  uninstall quit:       "com.mukes555.PortNanny",
            login_item: "PortNanny"

  zap trash: [
    "~/Library/Caches/com.mukes555.PortNanny",
    "~/Library/HTTPStorages/com.mukes555.PortNanny",
    "~/Library/Preferences/com.mukes555.PortNanny.plist",
    "~/Library/Saved Application State/com.mukes555.PortNanny.savedState",
  ]
end
