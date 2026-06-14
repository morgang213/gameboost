import SwiftUI
import ServiceManagement

enum AppInfo {
    static let repoURL = URL(string: "https://github.com/morgang213/gameboost")!
    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let b, b != v { return "\(v) (\(b))" }
        return v
    }
}

/// Launch-at-login via the modern Service Management API (macOS 13+).
enum LoginItem {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }
    static func set(_ on: Bool) throws {
        guard #available(macOS 13.0, *) else { return }
        if on { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }
}

/// What "One-click Boost" actually does — user-customizable, persisted.
struct BoostConfig: Codable {
    var freeMemory = true
    var pauseSpotlight = true
    var enableDND = false   // leave Do Not Disturb alone unless the user opts in
    var quitHeavyApps = false
    var heavyThresholdMB: Double = 750

    var summary: String {
        var p: [String] = []
        if freeMemory { p.append("free RAM") }
        if pauseSpotlight { p.append("pause Spotlight") }
        if enableDND { p.append("DND on") }
        if quitHeavyApps { p.append("quit apps >\(Int(heavyThresholdMB)) MB") }
        return p.isEmpty ? "nothing configured" : p.joined(separator: " · ")
    }
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    @Published var boost: BoostConfig { didSet { save() } }
    private let key = "boostConfig.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let cfg = try? JSONDecoder().decode(BoostConfig.self, from: data) {
            boost = cfg
        } else {
            boost = BoostConfig()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(boost) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// The shared form, reused by both the sheet and the sidebar page.
struct BoostSettingsForm: View {
    @ObservedObject var settings = SettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Free inactive memory (purge)", isOn: $settings.boost.freeMemory)
                    Toggle("Pause Spotlight indexing", isOn: $settings.boost.pauseSpotlight)
                    Toggle("Turn on Do Not Disturb", isOn: $settings.boost.enableDND)
                    Divider()
                    Toggle("Quit memory-hungry apps", isOn: $settings.boost.quitHeavyApps)
                    HStack {
                        Text("Quit apps using more than").font(.system(size: 12))
                        Spacer()
                        Text("\(Int(settings.boost.heavyThresholdMB)) MB")
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundColor(settings.boost.quitHeavyApps ? .primary : .secondary)
                    }
                    Slider(value: $settings.boost.heavyThresholdMB, in: 250...4000, step: 50)
                        .disabled(!settings.boost.quitHeavyApps)
                }
                .padding(8)
            }
            Text("Boost will: \(settings.boost.summary)")
                .font(.caption).foregroundColor(.secondary)
        }
    }
}

/// Sidebar Settings destination: General + One-click Boost + About.
struct SettingsPage: View {
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("General") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Launch GameBoost at login", isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) { newValue in
                                do {
                                    try LoginItem.set(newValue)
                                } catch {
                                    launchAtLogin = LoginItem.isEnabled
                                    errorMessage = error.localizedDescription
                                }
                            }
                        Text("Keeps the menu-bar icon available right after you log in.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("One-click Boost").font(.system(size: 13, weight: .semibold))
                    Text("Pick exactly what happens when you hit the One-click Boost button — on the dashboard or in the menu bar.")
                        .font(.caption).foregroundColor(.secondary)
                    BoostSettingsForm()
                }

                GroupBox("About") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Version").foregroundColor(.secondary)
                            Spacer()
                            Text(AppInfo.version).monospacedDigit()
                        }
                        .font(.caption)
                        Link("GameBoost on GitHub", destination: AppInfo.repoURL).font(.caption)
                        Text("An honest macOS gaming optimizer — no fake driver updates, no placebo cleaners.")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(8)
                }
            }
            .frame(maxWidth: 480, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .alert("Couldn't update login item", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}
