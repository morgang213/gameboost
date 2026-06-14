import SwiftUI
import Charts
import AppKit

enum Tab: String, CaseIterable { case dashboard = "Dashboard", profiles = "Game Profiles", graphics = "Graphics" }

struct ContentView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var settings = SettingsStore.shared
    @State private var tab: Tab = .dashboard
    @State private var showBoostSettings = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.08, blue: 0.12),
                         Color(red: 0.11, green: 0.10, blue: 0.16)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 8)
                .frame(maxWidth: 360)

                switch tab {
                case .dashboard:
                    HSplitView {
                        leftPane.frame(minWidth: 360, idealWidth: 400)
                        rightPane.frame(minWidth: 420)
                    }
                case .profiles:
                    ProfilesView()
                case .graphics:
                    GraphicsView()
                }
            }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 860, minHeight: 600)
        .onAppear { state.start() }
        .sheet(isPresented: $showBoostSettings) {
            BoostSettingsView { showBoostSettings = false }
        }
    }

    // MARK: - Left

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "gamecontroller.fill")
                    .font(.title2)
                    .foregroundStyle(LinearGradient(colors: [.purple, .pink], startPoint: .top, endPoint: .bottom))
                VStack(alignment: .leading, spacing: 0) {
                    Text("GameBoost").font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(SystemStats.cpuModel())
                        .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
            }

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

                    Button(action: { showBoostSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.06))
                            .foregroundColor(.secondary)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .help("Customize what One-click Boost does")
                }
                Text("Will: \(settings.boost.summary)")
                    .font(.caption2).foregroundColor(.secondary.opacity(0.8))
            }

            Spacer()
            Text("Uptime \(SystemStats.uptime())")
                .font(.caption2).foregroundColor(.secondary.opacity(0.6))
        }
        .padding(18)
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

    // MARK: - Right

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Running apps").font(.system(size: 14, weight: .semibold))
                Text("\(state.apps.count)").font(.caption).foregroundColor(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.white.opacity(0.08)).cornerRadius(4)
                Spacer()
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
}
