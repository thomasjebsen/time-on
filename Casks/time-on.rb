cask "time-on" do
  version "1.0.1"
  sha256 "55cebe358f24283c804d0a4e6a8ec9fadbd276b6ae2831fb0777876674b4bbab"

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
