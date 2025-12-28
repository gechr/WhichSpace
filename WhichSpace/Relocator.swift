import AppKit

enum Relocator {
    private static let alertSuppressKey = "moveToApplicationsFolderAlertSuppress"
    private static let localizationTable = "Relocator"

    private enum Strings {
        static let couldNotMove = "Could not move to the Applications folder."
        static let questionTitle = "Move to the Applications folder?"
        static let questionTitleHome = "Move to the Applications folder in your Home folder?"
        static let questionMessage = "%@ can move itself to the Applications folder."
        static let buttonMove = "Move to Applications Folder"
        static let buttonDoNotMove = "Do Not Move"
        static let questionInfoDownloads = "This will keep your Downloads folder tidy."
    }

    static func moveIfNecessary(appName: String) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: alertSuppressKey) else {
            return
        }

        let bundleURL = Bundle.main.bundleURL
        let isNestedApplication = isApplicationNested(bundleURL)
        if isInApplicationsFolder(bundleURL), !isNestedApplication {
            return
        }

        guard let preferred = preferredInstallDirectory() else {
            return
        }

        let fileManager = FileManager.default
        let destinationURL = preferred.url.appendingPathComponent(bundleURL.lastPathComponent)
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }

        let alert = NSAlert()
        alert.messageText = localized(preferred.isUserApplications ? Strings.questionTitleHome : Strings.questionTitle)
        var informativeText = localized(Strings.questionMessage, appName)
        if isInDownloadsFolder(bundleURL) {
            informativeText += " " + localized(Strings.questionInfoDownloads)
        }
        alert.informativeText = informativeText
        alert.addButton(withTitle: localized(Strings.buttonMove))
        let cancelButton = alert.addButton(withTitle: localized(Strings.buttonDoNotMove))
        cancelButton.keyEquivalent = "\u{1b}"

        alert.showsSuppressionButton = true
        if let cell = alert.suppressionButton?.cell {
            cell.controlSize = .small
            cell.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        }

        let response = alert.runModal()
        if response != .alertFirstButtonReturn {
            if alert.suppressionButton?.state == .on {
                defaults.set(true, forKey: alertSuppressKey)
            }
            return
        }

        if !fileManager.fileExists(atPath: preferred.url.path) {
            do {
                try fileManager.createDirectory(
                    at: preferred.url,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                showFailureAlert()
                return
            }
        }

        guard fileManager.isWritableFile(atPath: preferred.url.path) else {
            showFailureAlert()
            return
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            if isApplicationAtURLRunning(destinationURL) {
                NSWorkspace.shared.open(destinationURL)
                exit(0)
            }
            guard fileManager.isWritableFile(atPath: destinationURL.path),
                  (try? fileManager.trashItem(at: destinationURL, resultingItemURL: nil)) != nil
            else {
                showFailureAlert()
                return
            }
        }

        do {
            try fileManager.copyItem(at: bundleURL, to: destinationURL)
        } catch {
            showFailureAlert()
            return
        }

        _ = try? fileManager.trashItem(at: bundleURL, resultingItemURL: nil)
        relaunch(at: destinationURL)
    }

    private static func preferredInstallDirectory() -> (url: URL, isUserApplications: Bool)? {
        let fileManager = FileManager.default
        let userApps = fileManager.urls(for: .applicationDirectory, in: .userDomainMask)
            .first?
            .resolvingSymlinksInPath()

        if let userApps, directoryHasApplications(userApps), canWriteToDirectory(userApps) {
            return (userApps, true)
        }

        let localApps = fileManager.urls(for: .applicationDirectory, in: .localDomainMask)
            .first?
            .resolvingSymlinksInPath()

        if let localApps, canWriteToDirectory(localApps) {
            return (localApps, false)
        }

        if let userApps, canWriteToDirectory(userApps) {
            return (userApps, true)
        }

        return nil
    }

    private static func directoryHasApplications(_ url: URL) -> Bool {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return contents.contains { $0.hasSuffix(".app") }
    }

    private static func canWriteToDirectory(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            return isDirectory.boolValue && fileManager.isWritableFile(atPath: url.path)
        }
        let parent = url.deletingLastPathComponent()
        return fileManager.isWritableFile(atPath: parent.path)
    }

    private static func isInApplicationsFolder(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let appDirs = FileManager.default.urls(for: .applicationDirectory, in: .allDomainsMask)
        if appDirs.contains { path.hasPrefix($0.standardizedFileURL.path) } {
            return true
        }
        return url.pathComponents.contains("Applications")
    }

    private static func isInDownloadsFolder(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let downloadDirs = FileManager.default.urls(for: .downloadsDirectory, in: .allDomainsMask)
        return downloadDirs.contains { path.hasPrefix($0.standardizedFileURL.path) }
    }

    private static func isApplicationNested(_ url: URL) -> Bool {
        let parentComponents = url.deletingLastPathComponent().pathComponents
        return parentComponents.contains { $0.hasSuffix(".app") }
    }

    private static func isApplicationAtURLRunning(_ url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleURL?.standardizedFileURL == standardizedURL
        }
    }

    private static func relaunch(at destinationURL: URL) {
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-d", "-r", "com.apple.quarantine", destinationURL.path]
        try? xattr.run()
        xattr.waitUntilExit()

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destinationURL, configuration: configuration) { _, _ in
            exit(0)
        }
    }

    private static func showFailureAlert() {
        let alert = NSAlert()
        alert.messageText = localized(Strings.couldNotMove)
        alert.runModal()
    }

    private static func localized(_ key: String) -> String {
        String(localized: .init(key), table: localizationTable, bundle: .main)
    }

    private static func localized(_ key: String, _ args: CVarArg...) -> String {
        let format = localized(key)
        return String(format: format, locale: Locale.current, arguments: args)
    }
}
