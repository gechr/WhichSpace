import AppIntents

// MARK: - Intent Error

/// Wraps scripting-layer errors so Shortcuts shows the localized message
/// instead of a generic "operation couldn't be completed" failure.
private struct IntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String

    var localizedStringResource: LocalizedStringResource {
        "\(message)"
    }
}

// MARK: - Switching

/// Switches to a Space, optionally applying a label and badge in one step.
/// Mirrors the AppleScript `switch to space number` command.
struct SwitchSpaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Space"
    static let description = IntentDescription(
        "Switches to a Space on the current display, optionally applying a label and badge."
    )

    @Parameter(title: "Space Number")
    var spaceNumber: Int

    @Parameter(title: "Label")
    var label: String?

    @Parameter(title: "Badge")
    var badge: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Switch to Space \(\.$spaceNumber)") {
            \.$label
            \.$badge
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let env = AppEnvironment.shared
        do {
            try ScriptingHelpers.switchToSpace(number: spaceNumber, appState: env.appState)
            // Keyed by the target Space number, so these cannot race the
            // asynchronous switch animation
            if let label {
                ScriptingHelpers.setLabel(
                    label,
                    forSpace: spaceNumber,
                    appState: env.appState,
                    store: env.store
                )
            }
            if let badge {
                try ScriptingHelpers.setBadge(
                    badge,
                    forSpace: spaceNumber,
                    appState: env.appState,
                    store: env.store
                )
            }
        } catch {
            throw IntentError(message: error.localizedDescription)
        }
        return .result()
    }
}

// MARK: - Spaces

/// Returns the current Space number (1-based numeric index).
/// Mirrors the AppleScript `current space number` property.
struct GetCurrentSpaceNumberIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Current Space Number"
    static let description = IntentDescription(
        "Returns the current Space number."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        .result(value: AppEnvironment.shared.appState.currentSpace)
    }
}

// MARK: - Labels

/// Returns the current Space label as shown in the menu bar.
/// Mirrors reading the AppleScript `current space label` property.
struct GetCurrentSpaceLabelIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Current Space Label"
    static let description = IntentDescription(
        "Returns the current Space label as shown in the menu bar."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let env = AppEnvironment.shared
        return .result(value: ScriptingHelpers.resolveCurrentLabel(
            appState: env.appState,
            store: env.store
        ))
    }
}

/// Applies a custom label to the current Space. An empty label resets it
/// to its default, as a synonym for `ResetCurrentSpaceLabelIntent`.
/// Mirrors assigning the AppleScript `current space label` property.
struct SetCurrentSpaceLabelIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Current Space Label"
    static let description = IntentDescription(
        "Applies a custom label to the current Space. An empty label resets it to its default."
    )

    @Parameter(title: "Label")
    var label: String

    static var parameterSummary: some ParameterSummary {
        Summary("Set the current Space label to \(\.$label)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let env = AppEnvironment.shared
        ScriptingHelpers.setCurrentLabel(label, appState: env.appState, store: env.store)
        return .result()
    }
}

/// Resets the current Space label to its default.
/// Mirrors the AppleScript `reset current space label` command.
struct ResetCurrentSpaceLabelIntent: AppIntent {
    static let title: LocalizedStringResource = "Reset Current Space Label"
    static let description = IntentDescription(
        "Resets the current Space label to its default."
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        let env = AppEnvironment.shared
        ScriptingHelpers.resetCurrentLabel(appState: env.appState, store: env.store)
        return .result()
    }
}

/// Resets the labels of all Spaces to their defaults.
/// Mirrors the AppleScript `reset all space labels` command.
struct ResetAllSpaceLabelsIntent: AppIntent {
    static let title: LocalizedStringResource = "Reset All Space Labels"
    static let description = IntentDescription(
        "Resets the labels of all Spaces to their defaults."
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        SpacePreferences.clearAllLabels(store: AppEnvironment.shared.store)
        return .result()
    }
}

// MARK: - Badges

/// Returns the current Space badge character, or an empty string when unset.
/// Mirrors reading the AppleScript `current space badge` property.
struct GetCurrentSpaceBadgeIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Current Space Badge"
    static let description = IntentDescription(
        "Returns the current Space badge character, or an empty string when no badge is set."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let env = AppEnvironment.shared
        return .result(value: ScriptingHelpers.resolveCurrentBadge(
            appState: env.appState,
            store: env.store
        ))
    }
}

/// Applies a badge character to the current Space ("#" shows the Space
/// number). An empty badge resets it, as a synonym for
/// `ResetCurrentSpaceBadgeIntent`.
/// Mirrors assigning the AppleScript `current space badge` property.
struct SetCurrentSpaceBadgeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Current Space Badge"
    static let description = IntentDescription(
        "Applies a badge character to the current Space (\"#\" shows the Space number). An empty badge resets it."
    )

    @Parameter(title: "Badge")
    var badge: String

    static var parameterSummary: some ParameterSummary {
        Summary("Set the current Space badge to \(\.$badge)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let env = AppEnvironment.shared
        do {
            try ScriptingHelpers.setCurrentBadge(badge, appState: env.appState, store: env.store)
        } catch {
            throw IntentError(message: error.localizedDescription)
        }
        return .result()
    }
}

/// Resets the current Space badge to its default.
/// Mirrors the AppleScript `reset current space badge` command.
struct ResetCurrentSpaceBadgeIntent: AppIntent {
    static let title: LocalizedStringResource = "Reset Current Space Badge"
    static let description = IntentDescription(
        "Resets the current Space badge to its default."
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        let env = AppEnvironment.shared
        ScriptingHelpers.resetCurrentBadge(appState: env.appState, store: env.store)
        return .result()
    }
}

/// Resets the badges of all Spaces to their defaults.
/// Mirrors the AppleScript `reset all space badges` command.
struct ResetAllSpaceBadgesIntent: AppIntent {
    static let title: LocalizedStringResource = "Reset All Space Badges"
    static let description = IntentDescription(
        "Resets the badges of all Spaces to their defaults."
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        SpacePreferences.clearAllBadges(store: AppEnvironment.shared.store)
        return .result()
    }
}

// MARK: - App Shortcuts

/// Zero-setup shortcuts surfaced in Spotlight and Siri without the user
/// having to build them in the Shortcuts app first.
struct WhichSpaceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SwitchSpaceIntent(),
            phrases: [
                "Switch Space with \(.applicationName)",
                "Switch to a Space with \(.applicationName)",
            ],
            shortTitle: "Switch Space",
            systemImageName: "number.square"
        )
        AppShortcut(
            intent: GetCurrentSpaceNumberIntent(),
            phrases: [
                "Get the current Space with \(.applicationName)",
                "Which Space am I on in \(.applicationName)",
            ],
            shortTitle: "Current Space",
            systemImageName: "number.square"
        )
    }
}
