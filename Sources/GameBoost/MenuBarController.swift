import SwiftUI
import AppKit
import Combine
import Charts

/// Installs a status-bar item showing live CPU%, with a popover dashboard.
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?

    func install() {
        AppState.shared.start()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "GameBoost")
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        statusItem = item

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 440)
        popover.contentViewController = NSHostingController(rootView: MenuBarView())

        cancellable = AppState.shared.$currentCPU
            .receive(on: RunLoop.main)
            .sink { [weak self] cpu in
                self?.statusItem?.button?.title = String(format: " %.0f%%", cpu)
            }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

struct MenuBarView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject var store = ProfileStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "gamecontroller.fill")
                    .foregroundStyle(LinearGradient(colors: [.purple, .pink], startPoint: .top, endPoint: .bottom))
                Text("GameBoost").font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
            }

            HStack(spacing: 10) {
                miniStat("CPU", String(format: "%.0f%%", state.currentCPU), .cyan)
                miniStat("Pressure", String(format: "%.0f%%", state.mem.pressurePercent), pressureColor)
                miniStat("Temp", state.thermal.shortLabel, thermalColor)
            }

            if state.thermal.severity >= 2 || state.power.isThrottlingLikely {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundColor(.orange)
                    Text(state.thermal.severity >= 2
                         ? "Thermal-throttling — performance reduced."
                         : (state.power.lowPowerMode ? "Low Power Mode on." : "On battery — plug in for full power."))
                        .font(.caption2).foregroundColor(.orange)
                }
            }

            Chart(state.cpuHistory) { s in
                AreaMark(x: .value("t", s.t), y: .value("v", s.value))
                    .foregroundStyle(LinearGradient(colors: [.cyan.opacity(0.4), .cyan.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("t", s.t), y: .value("v", s.value))
                    .foregroundStyle(.cyan).interpolationMethod(.monotone)
            }
            .chartYScale(domain: 0...100).chartXAxis(.hidden).chartYAxis(.hidden)
            .frame(height: 48)

            Button(action: { state.oneClickBoost() }) {
                HStack {
                    Image(systemName: "bolt.fill")
                    Text("One-click Boost").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if state.busy { ProgressView().controlSize(.small) }
                }
                .padding(.vertical, 8).padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .background(LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing))
                .foregroundColor(.white).cornerRadius(8)
            }
            .buttonStyle(.plain).disabled(state.busy)

            if state.battery != nil {
                Button(action: { state.setOverdrive(!state.overdriveOn) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                        Text(state.overdriveOn ? "Overdrive ON" : "Overdrive")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .background(state.overdriveOn
                        ? AnyShapeStyle(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Color.orange.opacity(0.12)))
                    .foregroundColor(state.overdriveOn ? .white : .orange)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain).disabled(state.busy)
            }

            if !store.profiles.isEmpty {
                Text("PROFILES").font(.caption2).bold().foregroundColor(.secondary).tracking(1.5)
                ForEach(store.profiles.prefix(5)) { p in
                    Button(action: { state.launchProfile(p) }) {
                        HStack(spacing: 8) {
                            if let icon = p.icon {
                                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                            }
                            Text(p.name).font(.system(size: 12))
                            Spacer()
                            Image(systemName: "play.fill").font(.caption2).foregroundColor(.secondary)
                        }
                        .padding(.vertical, 5).padding(.horizontal, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.05)).cornerRadius(6)
                    }
                    .buttonStyle(.plain).disabled(state.busy)
                }
            }

            Divider()
            HStack {
                Button("Open dashboard") { state.showMainWindow() }
                    .font(.system(size: 12))
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .font(.system(size: 12))
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private func miniStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.05)).cornerRadius(8)
    }

    private var pressureColor: Color {
        switch state.mem.pressurePercent {
        case ..<60: return .green
        case ..<80: return .yellow
        default: return .red
        }
    }

    private var thermalColor: Color {
        switch state.thermal.severity {
        case 0: return .green
        case 1: return .yellow
        case 2: return .orange
        default: return .red
        }
    }
}
