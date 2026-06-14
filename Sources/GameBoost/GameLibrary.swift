import Foundation
import AppKit

struct DiscoveredGame: Identifiable, Hashable {
    let name: String
    let appPath: String?
    let source: String           // "Steam" or "Application"

    var id: String { appPath ?? "\(source):\(name)" }
    var icon: NSImage? {
        guard let appPath, FileManager.default.fileExists(atPath: appPath) else { return nil }
        return NSWorkspace.shared.icon(forFile: appPath)
    }
}

/// Finds installed games from Steam manifests and the Applications folders.
enum GameScanner {
    static func scan() -> [DiscoveredGame] {
        var all = steamGames() + nativeGames()
        var seen = Set<String>()
        all = all.filter { seen.insert($0.appPath ?? $0.id).inserted }
        return all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Steam

    private static func steamGames() -> [DiscoveredGame] {
        let fm = FileManager.default
        let base = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam/steamapps")
        guard let items = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { return [] }

        var games: [DiscoveredGame] = []
        for acf in items where acf.pathExtension == "acf" {
            guard let text = try? String(contentsOf: acf, encoding: .utf8),
                  let name = vdfValue(text, "name"),
                  let installdir = vdfValue(text, "installdir") else { continue }
            let commonDir = base.appendingPathComponent("common").appendingPathComponent(installdir)
            let appPath = findApp(in: commonDir)
            games.append(DiscoveredGame(name: name, appPath: appPath, source: "Steam"))
        }
        return games
    }

    // MARK: Native (apps that declare the games category)

    private static func nativeGames() -> [DiscoveredGame] {
        let fm = FileManager.default
        let dirs = [
            URL(fileURLWithPath: "/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
        var games: [DiscoveredGame] = []
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for app in items where app.pathExtension == "app" {
                if let cat = category(of: app), cat.contains("game") {
                    games.append(DiscoveredGame(
                        name: app.deletingPathExtension().lastPathComponent,
                        appPath: app.path, source: "Application"))
                }
            }
        }
        return games
    }

    // MARK: Helpers

    private static func category(of app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: plist) else { return nil }
        return (dict["LSApplicationCategoryType"] as? String)?.lowercased()
    }

    private static func findApp(in dir: URL) -> String? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        if let app = items.first(where: { $0.pathExtension == "app" }) { return app.path }
        // Look one level deeper (some games nest the bundle).
        for sub in items {
            let isDir = (try? sub.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir, sub.pathExtension != "app" else { continue }
            if let inner = try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil),
               let app = inner.first(where: { $0.pathExtension == "app" }) {
                return app.path
            }
        }
        return nil
    }

    /// Pull a value out of Valve's VDF text, e.g. `"name"  "Portal 2"`.
    private static func vdfValue(_ text: String, _ key: String) -> String? {
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("\"\(key.lowercased())\"") else { continue }
            let tokens = trimmed.components(separatedBy: "\"")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if tokens.count >= 2 { return tokens.last }
        }
        return nil
    }
}
