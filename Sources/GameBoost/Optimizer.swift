import Foundation
import AppKit

enum OptimizeAction: String {
    case purgedMemory = "Freed inactive memory"
    case pausedSpotlight = "Paused Spotlight indexing"
    case resumedSpotlight = "Resumed Spotlight indexing"
    case enabledDND = "Enabled Do Not Disturb"
    case disabledDND = "Disabled Do Not Disturb"
    case quitApp = "Quit app"
    case failed = "Failed"
}

struct OptimizeResult {
    let action: OptimizeAction
    let detail: String
    let success: Bool
}

enum Optimizer {
    /// Run `purge` — requires admin. Uses osascript so the user sees a system prompt.
    static func freeInactiveMemory() -> OptimizeResult {
        let script = "do shell script \"/usr/sbin/purge\" with administrator privileges"
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        let err = Pipe()
        task.standardError = err
        task.standardOutput = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                return OptimizeResult(action: .purgedMemory,
                                      detail: "Inactive pages flushed to disk",
                                      success: true)
            }
        } catch {}
        let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return OptimizeResult(action: .failed,
                              detail: msg.isEmpty ? "purge failed (admin required)" : msg,
                              success: false)
    }

    /// Pause / resume Spotlight indexing on / .
    static func setSpotlight(enabled: Bool) -> OptimizeResult {
        let script = "do shell script \"/usr/bin/mdutil -a -i \(enabled ? "on" : "off")\" with administrator privileges"
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                return OptimizeResult(action: enabled ? .resumedSpotlight : .pausedSpotlight,
                                      detail: enabled ? "Indexing resumed" : "Indexing suspended",
                                      success: true)
            }
        } catch {}
        return OptimizeResult(action: .failed, detail: "mdutil failed", success: false)
    }

    /// Toggle Do Not Disturb via Shortcuts (macOS Focus). Requires a shortcut named
    /// "Toggle DND" or we fall back to opening Focus settings.
    static func setDoNotDisturb(enabled: Bool) -> OptimizeResult {
        let shortcutName = enabled ? "Turn On Do Not Disturb" : "Turn Off Do Not Disturb"
        let task = Process()
        task.launchPath = "/usr/bin/shortcuts"
        task.arguments = ["run", shortcutName]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                return OptimizeResult(action: enabled ? .enabledDND : .disabledDND,
                                      detail: "Focus updated via Shortcuts",
                                      success: true)
            }
        } catch {}
        // Fallback: open Focus settings so the user can toggle manually.
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension")!)
        return OptimizeResult(action: .failed,
                              detail: "Create a Shortcut named '\(shortcutName)' to enable one-click toggling. Focus settings opened.",
                              success: false)
    }
}
