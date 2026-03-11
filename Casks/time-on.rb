cask "time-on" do
  version "1.0.0"
  sha256 "PLACEHOLDER_SHA256"

  url "https://github.com/thomasjebsen/time-on/releases/download/v#{version}/TimeOn.app.zip"
  name "Time On"
  desc "Menu bar app that tracks screen time and keeps your Mac awake"
  homepage "https://github.com/thomasjebsen/time-on"

  app "TimeOn.app"

  zap trash: [
    "~/Library/Application Support/TimeOn",
    "~/Library/Preferences/com.timeon.app.plist",
  ]
end
