import SwiftUI

@main
struct AppMain: App {
    // swiftformat:disable:next unusedPrivateDeclarations
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The empty scene only satisfies the App protocol. Without
        // commandsRemoved it registers its own Cmd+, item in the hidden main
        // menu, which opens this blank scene whenever a tracked menu does not
        // claim the shortcut first
        Settings {}.commandsRemoved()
    }
}
