import Foundation
import SwiftUI
import IOKit

/// Detailed battery readings from the AppleSmartBattery IORegistry entry.
/// All fields are optional — anything that doesn't read back is hidden rather
/// than faked, since these keys are undocumented.
struct BatteryInfo {
    var chargePercent: Int?
    var powerWatts: Double?      // signed: + charging, − discharging
    var temperatureC: Double?
    var cycleCount: Int?
    var healthPercent: Int?
    var designCapacity: Int?     // mAh
    var maxCapacity: Int?        // mAh (raw, full-charge capacity now)
    var isCharging: Bool
    var externalConnected: Bool
    var chargerWatts: Int?
    var timeRemainingMin: Int?

    var discharging: Bool { (powerWatts ?? 0) < -0.05 }
    /// Plugged in, but the adapter can't keep up — battery still draining.
    var chargerUnderpowered: Bool { externalConnected && !isCharging && discharging }
}

extension SystemStats {
    static func battery() -> BatteryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }

        func int(_ key: String) -> Int? { (props[key] as? NSNumber)?.intValue }
        func bool(_ key: String) -> Bool {
            if let b = props[key] as? Bool { return b }
            return (props[key] as? NSNumber)?.boolValue ?? false
        }
        // AppleSmartBattery amperage is 32-bit two's-complement; fix sign if it
        // came through as a large unsigned value.
        func signed32(_ key: String) -> Int? {
            guard var v = (props[key] as? NSNumber)?.intValue else { return nil }
            if v > Int(Int32.max) { v -= (Int(UInt32.max) + 1) }
            return v
        }

        let voltage = int("Voltage")                                   // mV
        let amperage = signed32("InstantAmperage") ?? signed32("Amperage")  // mA, signed

        var watts: Double?
        if let v = voltage, let a = amperage { watts = Double(v) / 1000.0 * Double(a) / 1000.0 }

        var tempC: Double?
        if let t = int("Temperature") { tempC = Double(t) / 100.0 }

        let design = int("DesignCapacity")
        let rawMax = int("AppleRawMaxCapacity") ?? int("NominalChargeCapacity")
        var health: Int?
        if let d = design, d > 0, let m = rawMax { health = Int((Double(m) / Double(d) * 100).rounded()) }

        var charge: Int?
        if let cur = int("CurrentCapacity"), let mx = int("MaxCapacity"), mx > 0 {
            charge = mx == 100 ? cur : Int((Double(cur) / Double(mx) * 100).rounded())
        }

        var chargerW: Int?
        if let adapter = props["AdapterDetails"] as? [String: Any] {
            chargerW = (adapter["Watts"] as? NSNumber)?.intValue
        }

        let raw = int("TimeRemaining") ?? int("AvgTimeToEmpty")
        let timeRemaining = (raw == nil || raw == 65535 || raw == 0) ? nil : raw

        return BatteryInfo(
            chargePercent: charge, powerWatts: watts, temperatureC: tempC,
            cycleCount: int("CycleCount"), healthPercent: health,
            designCapacity: design, maxCapacity: rawMax,
            isCharging: bool("IsCharging"), externalConnected: bool("ExternalConnected"),
            chargerWatts: chargerW, timeRemainingMin: timeRemaining)
    }
}

struct BatteryView: View {
    @ObservedObject var state = AppState.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let b = state.battery {
                    if b.chargerUnderpowered {
                        warnBanner("Your charger can't keep up — the battery is still draining while plugged in. Use a higher-wattage adapter for gaming.")
                    }
                    HStack(spacing: 12) {
                        bigStat("Power draw", powerText(b), powerColor(b))
                        bigStat("Temperature", b.temperatureC.map { String(format: "%.1f°C", $0) } ?? "—", tempColor(b))
                        bigStat("Charge", b.chargePercent.map { "\($0)%" } ?? "—", .green)
                    }
                    healthCard(b)
                    powerSourceCard(b)
                    Text("Live values from the system's AppleSmartBattery sensors. Power draw is voltage × current; negative means discharging.")
                        .font(.caption2).foregroundColor(.secondary)
                } else {
                    emptyDesktop
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    // MARK: Cards

    private func healthCard(_ b: BatteryInfo) -> some View {
        card("Battery health") {
            row("Health", b.healthPercent.map { "\($0)%" } ?? "—",
                color: (b.healthPercent ?? 100) < 80 ? .orange : .primary)
            row("Cycle count", b.cycleCount.map { "\($0)" } ?? "—")
            if let max = b.maxCapacity, let design = b.designCapacity {
                row("Full charge capacity", "\(max) / \(design) mAh")
            }
        }
    }

    private func powerSourceCard(_ b: BatteryInfo) -> some View {
        card("Power source") {
            row("Status", b.externalConnected ? (b.isCharging ? "Charging" : "Plugged in (not charging)") : "On battery",
                color: b.externalConnected ? .green : .orange)
            if let w = b.chargerWatts { row("Charger", "\(w) W") }
            if let v = b.powerWatts { row("Current flow", String(format: "%+.1f W", v)) }
            if let t = b.timeRemainingMin {
                row(b.isCharging ? "Time to full" : "Time remaining", "\(t / 60)h \(t % 60)m")
            }
        }
    }

    private var emptyDesktop: some View {
        VStack(spacing: 10) {
            Image(systemName: "powerplug.fill")
                .font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
            Text("No battery detected").font(.headline)
            Text("This looks like a desktop Mac — battery metrics aren't available.")
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }

    // MARK: Bits

    private func bigStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .cornerRadius(10)
    }

    private func warnBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text(text).font(.caption).foregroundColor(.orange)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.3), lineWidth: 1))
        .cornerRadius(10)
    }

    private func row(_ label: String, _ value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(size: 12, weight: .medium)).foregroundColor(color)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func card<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .cornerRadius(10)
    }

    // MARK: Formatting

    private func powerText(_ b: BatteryInfo) -> String {
        guard let w = b.powerWatts else { return "—" }
        let mag = abs(w)
        if b.isCharging { return String(format: "Charging %.1f W", mag) }
        if mag < 0.05 { return "Idle" }
        return String(format: "%.1f W", mag)
    }

    private func powerColor(_ b: BatteryInfo) -> Color {
        guard let w = b.powerWatts, !b.isCharging else { return .green }
        switch abs(w) {
        case ..<15: return .green
        case ..<35: return .yellow
        default: return .orange
        }
    }

    private func tempColor(_ b: BatteryInfo) -> Color {
        guard let t = b.temperatureC else { return .secondary }
        switch t {
        case ..<35: return .green
        case ..<40: return .yellow
        default: return .orange
        }
    }
}
