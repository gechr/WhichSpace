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
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    ]
)
