import AppKit

enum AppMover {
    private static let alertSuppressKey = "moveToApplicationsFolderAlertSuppress"

    static func moveIfNecessary(appName: String) {
        // Early-exit checks that don't require the run loop
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

        // Defer modal UI to a Task so applicationDidFinishLaunching returns
        // immediately and the run loop / status bar can initialize.
        Task { @MainActor in
            let fileManager = FileManager.default
            let destinationURL = preferred.url.appendingPathComponent(bundleURL.lastPathComponent)
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }

            let alert = NSAlert()
            alert.messageText = preferred.isUserApplications
                ? String(localized: "question_title_home", table: "AppMover")
                : String(localized: "question_title", table: "AppMover")
            var informativeText = String(
                format: String(localized: "question_message", table: "AppMover"),
                appName
            )
            if isInDownloadsFolder(bundleURL) {
                informativeText += " " + String(localized: "question_info_downloads", table: "AppMover")
            }
            alert.informativeText = informativeText
            alert.addButton(withTitle: String(localized: "button_move", table: "AppMover"))
            let cancelButton = alert.addButton(withTitle: String(localized: "button_do_not_move", table: "AppMover"))
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
                if let runningApp = runningApplication(at: destinationURL) {
                    if isSameBundleAndVersion(bundleURL, destinationURL) {
                        if NSWorkspace.shared.open(destinationURL) {
                            exit(0)
                        }
                        showFailureAlert()
                        return
                    }
                    guard confirmReplaceRunningApp(appName: appName) else {
                        return
                    }
                    guard terminateRunningApplication(runningApp) else {
                        showFailureAlert()
                        return
                    }
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

            await relaunch(from: bundleURL, to: destinationURL)
        }
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
        return appDirs.contains { appDir in
            let appPath = appDir.standardizedFileURL.path
            return path == appPath || path.hasPrefix(appPath + "/")
        }
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

    private static func runningApplication(at url: URL) -> NSRunningApplication? {
        let standardizedURL = url.standardizedFileURL
        return NSWorkspace.shared.runningApplications.first {
            $0.bundleURL?.standardizedFileURL == standardizedURL
        }
    }

    private static func terminateRunningApplication(_ app: NSRunningApplication) -> Bool {
        if app.isTerminated {
            return true
        }
        app.terminate()
        let deadline = Date().addingTimeInterval(5)
        while !app.isTerminated, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return app.isTerminated
    }

    private static func isSameBundleAndVersion(_ sourceURL: URL, _ destinationURL: URL) -> Bool {
        guard let sourceInfo = bundleInfo(at: sourceURL),
              let destinationInfo = bundleInfo(at: destinationURL),
              let sourceBundleID = sourceInfo.bundleID,
              let destinationBundleID = destinationInfo.bundleID
        else {
            return false
        }
        return sourceBundleID == destinationBundleID &&
            sourceInfo.shortVersion == destinationInfo.shortVersion &&
            sourceInfo.buildVersion == destinationInfo.buildVersion
    }

    private static func bundleInfo(
        at url: URL
    ) -> (bundleID: String?, shortVersion: String?, buildVersion: String?)? {
        guard let bundle = Bundle(url: url) else {
            return nil
        }
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return (bundle.bundleIdentifier, shortVersion, buildVersion)
    }

    @MainActor
    private static func confirmReplaceRunningApp(appName: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "replace_title", table: "AppMover")
        alert.informativeText = String(
            format: String(localized: "replace_message", table: "AppMover"),
            appName
        )
        alert.addButton(withTitle: String(localized: "button_quit_and_replace", table: "AppMover"))
        let cancelButton = alert.addButton(withTitle: String(localized: "button_do_not_move", table: "AppMover"))
        cancelButton.keyEquivalent = "\u{1b}"
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func relaunch(from sourceURL: URL, to destinationURL: URL) async {
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-d", "-r", "com.apple.quarantine", destinationURL.path]
        do {
            try xattr.run()
        } catch {
            NSLog("AppMover: failed to remove quarantine attribute: %@", error.localizedDescription)
        }

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                xattr.waitUntilExit()
                continuation.resume()
            }
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: destinationURL, configuration: configuration)
            do {
                try FileManager.default.trashItem(at: sourceURL, resultingItemURL: nil)
            } catch {
                NSLog("AppMover: failed to trash source bundle at %@: %@", sourceURL.path, error.localizedDescription)
            }
            exit(0)
        } catch {
            await showFailureAlert()
        }
    }

    @MainActor
    private static func showFailureAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "error_could_not_move", table: "AppMover")
        alert.runModal()
    }
}
