cask "whichspace" do
  version "0.12.12"
  sha256 "c4cb5776c7173396589f930ec09cc4975f4fe430896bfa66c2c1d06a5b45c3c7"

  url "https://github.com/gechr/WhichSpace/releases/download/v#{version}/WhichSpace.zip"
  name "WhichSpace"
  desc "Menu bar app showing the current Space number"
  homepage "https://github.com/gechr/WhichSpace"

  depends_on macos: ">= :sonoma"

  app "WhichSpace.app"

  postflight do
    system "xattr", "-d", "com.apple.quarantine", "#{appdir}/WhichSpace.app"
  end

  uninstall quit: "io.gechr.WhichSpace"

  zap trash: [
    "~/Library/Caches/io.gechr.WhichSpace",
    "~/Library/Cookies/io.gechr.WhichSpace.binarycookies",
    "~/Library/Preferences/io.gechr.WhichSpace.plist",
    "~/Library/Saved Application State/io.gechr.WhichSpace.savedState",
  ]
end
