import Foundation
import IOKit.ps
import IOKit.pwr_mgt

// MARK: - Thermal

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal:  return "Normal"
        case .fair:     return "Fair"
        case .serious:  return "Throttling"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
    var shortLabel: String {
        switch self {
        case .nominal:  return "Good"
        case .fair:     return "Fair"
        case .serious:  return "Hot"
        case .critical: return "Critical"
        @unknown default: return "—"
        }
    }
    /// 0 good … 3 critical, for color/severity.
    var severity: Int {
        switch self {
        case .nominal: return 0
        case .fair: return 1
        case .serious: return 2
        case .critical: return 3
        @unknown default: return 0
        }
    }
}

// MARK: - Power

struct PowerInfo {
    let hasBattery: Bool
    let onAC: Bool
    let charging: Bool
    let percent: Int?
    let lowPowerMode: Bool

    /// True when the Mac is likely capping performance.
    var isThrottlingLikely: Bool { lowPowerMode || (hasBattery && !onAC) }

    var summary: String {
        if !hasBattery { return onAC ? "AC power" : "Unknown" }
        let pct = percent.map { "\($0)%" } ?? "—"
        let src = onAC ? (charging ? "Charging \(pct)" : "Plugged in \(pct)") : "On battery \(pct)"
        return lowPowerMode ? "\(src) · Low Power" : src
    }
}

extension SystemStats {
    static func power() -> PowerInfo {
        let lpm = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            // No power sources reported → desktop on AC.
            return PowerInfo(hasBattery: false, onAC: true, charging: false, percent: nil, lowPowerMode: lpm)
        }
        for src in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, src)?.takeUnretainedValue() as? [String: Any]
            else { continue }
            let state = desc[kIOPSPowerSourceStateKey] as? String
            let onAC = state == kIOPSACPowerValue
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            var percent: Int? = nil
            if let cur = desc[kIOPSCurrentCapacityKey] as? Int,
               let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
                percent = Int((Double(cur) / Double(max) * 100).rounded())
            }
            return PowerInfo(hasBattery: true, onAC: onAC, charging: charging, percent: percent, lowPowerMode: lpm)
        }
        return PowerInfo(hasBattery: false, onAC: true, charging: false, percent: nil, lowPowerMode: lpm)
    }
}

// MARK: - Keep awake (prevent display sleep)

final class KeepAwake {
    private var assertionID: IOPMAssertionID = 0
    private(set) var active = false

    @discardableResult
    func set(_ on: Bool) -> Bool {
        if on && !active {
            let reason = "GameBoost: gaming session in progress" as CFString
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason, &assertionID)
            active = (result == kIOReturnSuccess)
        } else if !on && active {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            active = false
        }
        return active
    }
}
