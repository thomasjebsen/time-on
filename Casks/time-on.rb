cask "time-on" do
  version "1.3.0"
  sha256 "def70e7badbf3e7e4194233bfc8d0da0b8308b3aee6229893f81330e31990b5b"

  url "https://github.com/thomasjebsen/time-on/releases/download/v#{version}/TimeOn.app.zip"
  name "Time On"
  desc "Menu bar app that tracks screen time and keeps your Mac awake"
  homepage "https://github.com/thomasjebsen/time-on"

  app "TimeOn.app"

  caveats <<~EOS
    #{token} is not signed with an Apple Developer certificate.
    macOS may show a warning on first launch. To allow it:
      System Settings → Privacy & Security → scroll down → click "Open Anyway"
  EOS

  zap trash: [
    "~/Library/Application Support/TimeOn",
    "~/Library/Preferences/com.timeon.app.plist",
  ]
end
