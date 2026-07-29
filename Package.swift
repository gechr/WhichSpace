// swift-tools-version: 6.0

// This file exists for Dependabot compatibility.
// The actual build is done via WhichSpace.xcodeproj.

import PackageDescription

let package = Package(
    name: "WhichSpace",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        // EmojiKit 3.x requires macOS 15, so pin it <3.x while macOS 14.0 is still supported
        .package(url: "https://github.com/danielsaidi/EmojiKit", "2.2.0" ..< "3.0.0"),
        .package(url: "https://github.com/sindresorhus/Defaults", from: "9.0.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern", from: "1.0.0"),
        // Pinned to a main revision: the fix keeping the settings window from
        // becoming the main window (#125) is not in any tagged release yet
        .package(url: "https://github.com/sindresorhus/Settings", revision: "f41475771f65379ca10852c95119a7f53f0de5a5"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    ]
)
