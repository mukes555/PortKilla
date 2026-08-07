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

  depends_on macos: ">= :ventura"

  app "PortKilla.app"

  # The app is ad-hoc signed (no Apple Developer account), so Gatekeeper
  # quarantine must be stripped for it to launch without a scary dialog.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/PortKilla.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Preferences/com.mukes555.PortKilla.plist",
  ]
end
