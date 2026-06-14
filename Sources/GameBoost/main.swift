import SwiftUI
import AppKit

@available(macOS 13.0, *)
struct GameBoostApp: App {
    var body: some Scene {
        WindowGroup("GameBoost") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
    }
}

// Manual entry point so this works as a Swift Package executable (no @main).
NSApplication.shared.setActivationPolicy(.regular)
if #available(macOS 13.0, *) {
    GameBoostApp.main()
} else {
    fatalError("GameBoost requires macOS 13 or later")
}
