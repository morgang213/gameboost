import SwiftUI
import Charts
import AppKit

enum NavSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case profiles = "Game Profiles"
    case graphics = "Graphics"
    case stats = "Stats"
    case settings = "Settings"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .profiles:  return "gamecontroller"
        case .graphics:  return "slider.horizontal.3"
        case .stats:     return "chart.bar.fill"
        case .settings:  return "gearshape"
        }
    }
}

struct ContentView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var settings = SettingsStore.shared
    @State private var section: NavSection? = .dashboard

    var body: some View {
        NavigationSplitView(sidebar: {
            sidebar
        }, detail: {
            ZStack {
                gradient
                detailView
            }
            .navigationTitle(section?.rawValue ?? "GameBoost")
        })
        .preferredColorScheme(.dark)
        .frame(minWidth: 900, minHeight: 480)
        .onAppear { state.start() }
    }

    private var gradient: some View {
        LinearGradient(
            colors: [Color(red: 0.07, green: 0.08, blue: 0.12),
                     Color(red: 0.11, green: 0.10, blue: 0.16)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ).ignoresSafeArea()
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "gamecontroller.fill")
                    .foregroundStyle(LinearGradient(colors: [.purple, .pink], startPoint: .top, endPoint: .bottom))
                Text("GameBoost").font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 6)

            List(selection: $section) {
                ForEach(NavSection.allCases) { s in
                    Label(s.rawValue, systemImage: s.icon).tag(s)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            sidebarFooter
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 250)
    }

    private var sidebarFooter: some View {
        VStack(spacing: 8) {
            Divider().opacity(0.25)
            HStack(spacing: 8) {
                footStat("CPU", String(format: "%.0f%%", state.currentCPU), .cyan)
                footStat("Pressure", String(format: "%.0f%%", state.mem.pressurePercent), pressureColor)
                footStat("Temp", state.thermal.shortLabel, thermalColor)
            }
            Text("Uptime \(SystemStats.uptime())")
                .font(.caption2).foregroundColor(.secondary.opacity(0.5))
        }
        .padding(10)
    }

    private func footStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05)).cornerRadius(8)
    }

    // MARK: - Detail router

    @ViewBuilder
    private var detailView: some View {
        switch section ?? .dashboard {
        case .dashboard:
            HSplitView {
                leftPane.frame(minWidth: 320, idealWidth: 380)
                rightPane.frame(minWidth: 360)
            }
        case .profiles:
            ProfilesView()
        case .graphics:
            GraphicsView()
        case .stats:
            StatsView()
        case .settings:
            SettingsPage()
        }
    }

    // MARK: - Dashboard: left

    private var leftPane: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            Text(SystemStats.cpuModel())
                .font(.caption2).foregroundColor(.secondary).lineLimit(1)

            if let receipt = state.lastReceipt { receiptCard(receipt) }
            statusCard
            memoryCard
            cpuCard

            VStack(alignment: .leading, spacing: 6) {
                Text("BOOST").font(.caption2).bold().foregroundColor(.secondary).tracking(1.5)
                actionButton("Free inactive memory",
                             subtitle: "Runs `purge` (admin required)",
                             systemImage: "memorychip", tint: .blue) { state.freeMemory() }
                toggleRow("Pause Spotlight indexing",
                          subtitle: "Frees disk + CPU during gameplay",
                          systemImage: "magnifyingglass",
                          tint: state.spotlightPaused ? .orange : .blue,
                          isOn: Binding(get: { state.spotlightPaused },
                                        set: { state.setSpotlightPaused($0) }))
                toggleRow("Do Not Disturb",
                          subtitle: "Silences notifications",
                          systemImage: state.dndOn ? "moon.fill" : "moon",
                          tint: state.dndOn ? .indigo : .blue,
                          isOn: Binding(get: { state.dndOn },
                                        set: { state.setDND($0) }))
                toggleRow("Keep display awake",
                          subtitle: "Stops sleep during controller play",
                          systemImage: state.keepAwakeOn ? "cup.and.saucer.fill" : "cup.and.saucer",
                          tint: state.keepAwakeOn ? .green : .blue,
                          isOn: Binding(get: { state.keepAwakeOn },
                                        set: { state.setKeepAwake($0) }))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Button(action: { state.oneClickBoost() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                            Text("One-click Boost").font(.system(size: 14, weight: .bold))
                            Spacer()
                            if state.busy { ProgressView().controlSize(.small) }
                        }
                        .padding(.vertical, 12).padding(.horizontal, 14)
                        .frame(maxWidth: .infinity)
                        .background(LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing))
                        .foregroundColor(.white).cornerRadius(10)
                        .shadow(color: .purple.opacity(0.4), radius: 8, y: 2)
                    }
                    .buttonStyle(.plain).disabled(state.busy)

                    Button(action: { section = .settings }) {
                        Image(systemName: "gearshape.fill")
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.06))
                            .foregroundColor(.secondary)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .help("Customize what One-click Boost does")
                }
                HStack {
                    Text("Will: \(settings.boost.summary)")
                        .font(.caption2).foregroundColor(.secondary.opacity(0.8))
                    Spacer()
                    Button { state.restoreDefaults() } label: {
                        Label("Undo boost", systemImage: "arrow.uturn.backward")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(state.hasActiveBoost ? .orange : .secondary.opacity(0.5))
                    .disabled(state.busy || !state.hasActiveBoost)
                    .help("Resume Spotlight, turn off Do Not Disturb and keep-awake. Quit apps and purged memory can't be undone.")
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }

    private var memoryCard: some View {
        card {
            HStack {
                Label("Memory", systemImage: "memorychip").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(String(format: "%.1f / %.1f GB", state.mem.usedGB, state.mem.totalGB))
                    .font(.caption.monospacedDigit()).foregroundColor(.secondary)
            }
            Chart(state.memHistory) { s in
                AreaMark(x: .value("t", s.t), y: .value("v", s.value))
                    .foregroundStyle(LinearGradient(colors: [pressureColor.opacity(0.5), pressureColor.opacity(0.05)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("t", s.t), y: .value("v", s.value))
                    .foregroundStyle(pressureColor).interpolationMethod(.monotone)
            }
            .chartYScale(domain: 0...100).chartXAxis(.hidden)
            .chartYAxis { AxisMarks(values: [0, 50, 100]) { _ in AxisGridLine().foregroundStyle(.white.opacity(0.06)) } }
            .frame(height: 70)
            HStack(spacing: 14) {
                stat("Inactive", String(format: "%.1f GB", state.mem.inactiveGB))
                stat("Compressed", String(format: "%.1f GB", state.mem.compressedGB))
                stat("Pressure", String(format: "%.0f%%", state.mem.pressurePercent)).foregroundColor(pressureColor)
            }
        }
    }

    private var cpuCard: some View {
        card {
            HStack {
                Label("CPU", systemImage: "cpu").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(String(format: "%.0f%%", state.currentCPU)).font(.caption.monospacedDigit()).foregroundColor(.secondary)
            }
            Chart(state.cpuHistory) { s in
                AreaMark(x: .value("t", s.t), y: .value("v", s.value))
                    .foregroundStyle(LinearGradient(colors: [.cyan.opacity(0.5), .cyan.opacity(0.05)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("t", s.t), y: .value("v", s.value))
                    .foregroundStyle(Color.cyan).interpolationMethod(.monotone)
            }
            .chartYScale(domain: 0...100).chartXAxis(.hidden)
            .chartYAxis { AxisMarks(values: [0, 50, 100]) { _ in AxisGridLine().foregroundStyle(.white.opacity(0.06)) } }
            .frame(height: 70)
        }
    }

    private func receiptCard(_ r: BoostReceipt) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Boost applied").font(.system(size: 12, weight: .semibold))
                Text(r.summary).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Button { state.lastReceipt = nil } label: {
                Image(systemName: "xmark").font(.caption2)
            }
            .buttonStyle(.plain).foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color.green.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.3), lineWidth: 1))
        .cornerRadius(10)
    }

    private var statusCard: some View {
        card {
            HStack {
                Label("System", systemImage: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            HStack(spacing: 8) {
                pill(icon: thermalIcon, text: state.thermal.label, color: thermalColor)
                pill(icon: powerIcon, text: state.power.summary,
                     color: state.power.isThrottlingLikely ? .orange : .green)
            }
            if state.thermal.severity >= 2 {
                warn("Chip is thermal-throttling — frames are being capped. Improve airflow or cooling.")
            }
            if state.power.isThrottlingLikely {
                warn(state.power.lowPowerMode
                     ? "Low Power Mode is on — turn it off in Settings for full performance."
                     : "Running on battery — plug in for full GPU/CPU performance.")
            }
        }
    }

    private func pill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(color.opacity(0.15)).foregroundColor(color).cornerRadius(6)
    }

    private func warn(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundColor(.orange)
            Text(text).font(.caption2).foregroundColor(.orange)
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

    private var thermalIcon: String {
        switch state.thermal.severity {
        case 0: return "thermometer.low"
        case 1: return "thermometer.medium"
        case 2: return "thermometer.high"
        default: return "thermometer.sun.fill"
        }
    }

    private var powerIcon: String {
        if !state.power.hasBattery { return "powerplug.fill" }
        if state.power.onAC { return state.power.charging ? "battery.100.bolt" : "powerplug.fill" }
        return "battery.50"
    }

    @ViewBuilder
    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .padding(12)
            .background(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
            .cornerRadius(10)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.caption.monospacedDigit())
        }
    }

    private var pressureColor: Color {
        switch state.mem.pressurePercent {
        case ..<60: return .green
        case ..<80: return .yellow
        default: return .red
        }
    }

    private func actionButton(_ title: String, subtitle: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 24, height: 24)
                    .background(tint.opacity(0.18)).foregroundColor(tint).cornerRadius(6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(subtitle).font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 8).padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain).disabled(state.busy)
    }

    private func toggleRow(_ title: String, subtitle: String, systemImage: String, tint: Color, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.18)).foregroundColor(tint).cornerRadius(6)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).disabled(state.busy)
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .cornerRadius(8)
    }

    // MARK: - Dashboard: right

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Running apps").font(.system(size: 14, weight: .semibold))
                Text("\(state.apps.count)").font(.caption).foregroundColor(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.white.opacity(0.08)).cornerRadius(4)
                Spacer()
                Picker("", selection: $state.appSort) {
                    ForEach(AppState.AppSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 130)
                .onChange(of: state.appSort) { _ in state.refreshApps() }
                Button { state.quitSelected() } label: {
                    Label("Quit selected", systemImage: "xmark.circle.fill")
                }
                .disabled(state.selection.isEmpty || state.busy)
            }
            .padding(.horizontal, 14).padding(.top, 14)

            List(state.apps, selection: $state.selection) { app in
                HStack(spacing: 10) {
                    if let icon = app.icon {
                        Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                    }
                    Text(app.name).font(.system(size: 13))
                    Spacer()
                    if AppManager.isProtected(app) {
                        Image(systemName: "lock.fill").font(.caption2).foregroundColor(.secondary.opacity(0.6))
                    }
                    Text(String(format: "%.0f%%", app.cpuPercent))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(cpuColor(app.cpuPercent))
                        .frame(width: 46, alignment: .trailing)
                    Text(String(format: "%.0f MB", app.memoryMB))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(memColor(app.memoryMB))
                        .frame(width: 70, alignment: .trailing)
                }
                .tag(app.id)
            }
            .scrollContentBackground(.hidden).listStyle(.inset)

            Divider().opacity(0.3)
            Text("ACTIVITY").font(.caption2).bold().foregroundColor(.secondary).tracking(1.5)
                .padding(.horizontal, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(state.log.indices.reversed(), id: \.self) { i in
                        Text(state.log[i]).font(.caption.monospaced()).foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
            }
            .frame(height: 120).padding(.bottom, 10)
        }
    }

    private func memColor(_ mb: Double) -> Color {
        switch mb {
        case ..<200: return .secondary
        case ..<800: return .yellow
        default: return .orange
        }
    }

    private func cpuColor(_ p: Double) -> Color {
        switch p {
        case ..<25: return .secondary
        case ..<75: return .yellow
        default: return .orange
        }
    }
}
