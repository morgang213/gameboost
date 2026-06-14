import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let menuBar = MenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar.install()
    }

    // Re-open the dashboard when the Dock icon is clicked with no windows open.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppState.shared.showMainWindow() }
        return true
    }
}

@available(macOS 13.0, *)
struct GameBoostApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup("GameBoost") {
            ContentView()
        }
        .defaultSize(width: 1040, height: 680)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("One-click Boost") { AppState.shared.oneClickBoost() }
                    .keyboardShortcut("b", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Link("GameBoost on GitHub",
                     destination: URL(string: "https://github.com/morgang213/gameboost")!)
            }
        }
    }
}

// Manual entry point so this works as a Swift Package executable (no @main).
NSApplication.shared.setActivationPolicy(.regular)
if #available(macOS 13.0, *) {
    GameBoostApp.main()
} else {
    fatalError("GameBoost requires macOS 13 or later")
}
