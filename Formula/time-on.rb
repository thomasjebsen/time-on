class TimeOn < Formula
  desc "Menu bar app that tracks screen time and keeps your Mac awake"
  homepage "https://github.com/thomasjebsen/time-on"
  url "https://github.com/thomasjebsen/time-on/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256"
  license "MIT"

  depends_on xcode: ["14.0", :build]
  depends_on :macos

  def install
    system "swift", "build",
           "-c", "release",
           "--disable-sandbox"

    app_bundle = prefix/"TimeOn.app/Contents"
    (app_bundle/"MacOS").mkpath
    (app_bundle/"Resources").mkpath

    cp ".build/release/TimeOn", app_bundle/"MacOS/TimeOn"
    cp "Resources/Info.plist", app_bundle/"Info.plist"
  end

  def caveats
    <<~EOS
      Time On has been installed to:
        #{prefix}/TimeOn.app

      To launch, run:
        open #{prefix}/TimeOn.app

      Or move it to /Applications:
        cp -r #{prefix}/TimeOn.app /Applications/
    EOS
  end

  test do
    assert_predicate prefix/"TimeOn.app/Contents/MacOS/TimeOn", :exist?
  end
end
