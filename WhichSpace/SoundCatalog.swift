import AppKit

/// Discovers the selectable Space-change sounds: bundled system sounds and
/// user-provided audio files in ~/Library/Sounds.
enum SoundCatalog {
    nonisolated static let systemSounds = discoverSounds(in: URL(fileURLWithPath: "/System/Library/Sounds"))

    nonisolated static let userSoundsDirectory =
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds")

    /// Rescans ~/Library/Sounds. Safe to call off-main.
    nonisolated static func discoverUserSounds() -> [String] {
        discoverSounds(in: userSoundsDirectory)
    }

    private nonisolated static func discoverSounds(in directory: URL) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentTypeKey]
        ) else {
            return []
        }
        var sounds = Set<String>()
        for url in contents {
            guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
                  type.conforms(to: .audio)
            else {
                continue
            }
            sounds.insert(url.deletingPathExtension().lastPathComponent)
        }
        return sounds.sorted()
    }

    /// Opens ~/Library/Sounds in Finder, creating the directory first if needed.
    @MainActor
    static func openUserSoundsFolder() {
        let directory = userSoundsDirectory
        if FileManager.default.fileExists(atPath: directory.path) {
            NSWorkspace.shared.open(directory)
            return
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Give the filesystem a moment to settle so Finder opens the new folder reliably
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSWorkspace.shared.open(directory)
        }
    }
}
