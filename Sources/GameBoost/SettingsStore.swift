import SwiftUI

/// What "One-click Boost" actually does — user-customizable, persisted.
struct BoostConfig: Codable {
    var freeMemory = true
    var pauseSpotlight = true
    var enableDND = true
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

/// Sidebar destination version.
struct BoostSettingsPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Customize One-click Boost").font(.system(size: 14, weight: .semibold))
                Text("Pick exactly what happens when you hit the One-click Boost button — on the dashboard or in the menu bar.")
                    .font(.caption).foregroundColor(.secondary)
                BoostSettingsForm()
            }
            .frame(maxWidth: 460, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }
}
