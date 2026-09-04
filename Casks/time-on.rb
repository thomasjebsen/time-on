cask "time-on" do
  version "1.3.0"
  sha256 "def70e7badbf3e7e4194233bfc8d0da0b8308b3aee6229893f81330e31990b5b"

  url "https://github.com/thomasjebsen/time-on/releases/download/v#{version}/TimeOn.app.zip"
  name "Time On"
  desc "Menu bar app that tracks screen time and keeps your Mac awake"
  homepage "https://github.com/thomasjebsen/time-on"

  app "TimeOn.app"

  caveats <<~EOS
    #{token} is not signed with an Apple Developer certificate, so macOS may
    refuse to open it on first launch ("Apple could not verify ...").

    Either allow it once:
      System Settings → Privacy & Security → scroll down → click "Open Anyway"

    Or skip the quarantine flag when installing or upgrading:
      brew install --cask --no-quarantine thomasjebsen/tap/#{token}
      brew upgrade --cask --no-quarantine #{token}
  EOS

  zap trash: [
    "~/Library/Application Support/TimeOn",
    "~/Library/Preferences/com.timeon.app.plist",
  ]
end
