import Foundation
import AppKit

/// A saved set of boost actions tied to a specific game.
struct GameProfile: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var appPath: String           // path to the game .app to launch
    var quitBundleIDs: [String]   // apps to quit before launch
    var pauseSpotlight: Bool
    var enableDND: Bool
    var freeMemory: Bool
    var autoRestore: Bool         // revert spotlight/DND when the game quits

    var appURL: URL { URL(fileURLWithPath: appPath) }

    var icon: NSImage? {
        guard FileManager.default.fileExists(atPath: appPath) else { return nil }
        return NSWorkspace.shared.icon(forFile: appPath)
    }

    /// Short human summary of what this profile does.
    var summary: String {
        var parts: [String] = []
        if freeMemory { parts.append("purge RAM") }
        if pauseSpotlight { parts.append("pause Spotlight") }
        if enableDND { parts.append("DND") }
        if !quitBundleIDs.isEmpty { parts.append("quit \(quitBundleIDs.count)") }
        if autoRestore { parts.append("auto-restore") }
        return parts.isEmpty ? "Launch only" : parts.joined(separator: " · ")
    }

    static func new(appPath: String, name: String) -> GameProfile {
        GameProfile(name: name, appPath: appPath, quitBundleIDs: [],
                    pauseSpotlight: true, enableDND: true, freeMemory: true, autoRestore: true)
    }
}

final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()
    @Published var profiles: [GameProfile] = []

    private let fileURL: URL

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GameBoost", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("profiles.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([GameProfile].self, from: data) else { return }
        profiles = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: fileURL)
    }

    func upsert(_ profile: GameProfile) {
        if let i = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[i] = profile
        } else {
            profiles.append(profile)
        }
        save()
    }

    func delete(_ profile: GameProfile) {
        profiles.removeAll { $0.id == profile.id }
        save()
    }
}
