import Foundation
import AppKit

struct RunningApp: Identifiable, Hashable {
    let id: pid_t
    let name: String
    let bundleID: String?
    let memoryMB: Double
    let icon: NSImage?
}

enum AppManager {
    /// Apps that should never be auto-quit (system / essentials).
    private static let protectedBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.WindowManager",
        "com.apple.loginwindow",
        "com.anthropic.claude-code",
        Bundle.main.bundleIdentifier ?? ""
    ]

    static func runningApps() -> [RunningApp] {
        let memMap = processMemoryMap()
        return NSWorkspace.shared.runningApplications.compactMap { app -> RunningApp? in
            guard app.activationPolicy == .regular,
                  let name = app.localizedName else { return nil }
            let mem = memMap[app.processIdentifier] ?? 0
            return RunningApp(
                id: app.processIdentifier,
                name: name,
                bundleID: app.bundleIdentifier,
                memoryMB: mem,
                icon: app.icon
            )
        }
        .sorted { $0.memoryMB > $1.memoryMB }
    }

    static func isProtected(_ app: RunningApp) -> Bool {
        if let bid = app.bundleID, protectedBundleIDs.contains(bid) { return true }
        return false
    }

    static func quit(_ app: RunningApp) {
        if let nsApp = NSRunningApplication(processIdentifier: app.id) {
            nsApp.terminate()
        }
    }

    /// Parse `ps -axo pid=,rss=` to get RSS in KB per pid.
    private static func processMemoryMap() -> [pid_t: Double] {
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-axo", "pid=,rss="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return [:] }
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8) else { return [:] }

        var map: [pid_t: Double] = [:]
        for line in out.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).filter { !$0.isEmpty }
            if parts.count >= 2, let pid = Int32(parts[0]), let rssKB = Double(parts[1]) {
                map[pid] = rssKB / 1024.0  // MB
            }
        }
        return map
    }
}
