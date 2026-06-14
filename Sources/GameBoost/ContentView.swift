import SwiftUI
import Charts
import AppKit

struct Sample: Identifiable {
    let id = UUID()
    let t: Date
    let value: Double
}

struct ContentView: View {
    @State private var mem: MemoryStats = SystemStats.memory()
    @State private var apps: [RunningApp] = []
    @State private var log: [String] = []
    @State private var busy: Bool = false
    @State private var spotlightPaused: Bool = false
    @State private var dndOn: Bool = false
    @State private var selection: Set<pid_t> = []
    @State private var memHistory: [Sample] = []
    @State private var cpuHistory: [Sample] = []
    @State private var currentCPU: Double = 0

    private let cpuSampler = CPUSampler()
    private let refreshTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()
    private let appsTimer = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()
    private let historyWindow: TimeInterval = 60

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.08, blue: 0.12),
                         Color(red: 0.11, green: 0.10, blue: 0.16)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()

            HSplitView {
                leftPane.frame(minWidth: 360, idealWidth: 400)
                rightPane.frame(minWidth: 420)
            }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 860, minHeight: 600)
        .onAppear {
            _ = cpuSampler.sample()
            refresh()
            refreshApps()
        }
        .onReceive(refreshTimer) { _ in refresh() }
        .onReceive(appsTimer) { _ in refreshApps() }
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
                             systemImage: "memorychip", tint: .blue) {
                    runAsync { Optimizer.freeInactiveMemory() }
                }
                actionButton(spotlightPaused ? "Resume Spotlight indexing" : "Pause Spotlight indexing",
                             subtitle: "Frees disk + CPU during gameplay",
                             systemImage: "magnifyingglass",
                             tint: spotlightPaused ? .orange : .blue) {
                    let target = !spotlightPaused
                    runAsync {
                        let r = Optimizer.setSpotlight(enabled: !target)
                        if r.success { spotlightPaused = target }
                        return r
                    }
                }
                actionButton(dndOn ? "Turn off Do Not Disturb" : "Turn on Do Not Disturb",
                             subtitle: "Silences notifications",
                             systemImage: dndOn ? "moon.fill" : "moon",
                             tint: dndOn ? .indigo : .blue) {
                    let target = !dndOn
                    runAsync {
                        let r = Optimizer.setDoNotDisturb(enabled: target)
                        if r.success { dndOn = target }
                        return r
                    }
                }
            }

            Button(action: runOneClick) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                    Text("One-click Boost").font(.system(size: 14, weight: .bold))
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [.purple, .pink],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .foregroundColor(.white)
                .cornerRadius(10)
                .shadow(color: .purple.opacity(0.4), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(busy)

            Spacer()
            Text("Uptime \(SystemStats.uptime())")
                .font(.caption2).foregroundColor(.secondary.opacity(0.6))
        }
        .padding(18)
    }

    private var memoryCard: some View {
        card {
            HStack {
                Label("Memory", systemImage: "memorychip")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(String(format: "%.1f / %.1f GB", mem.usedGB, mem.totalGB))
                    .font(.caption.monospacedDigit()).foregroundColor(.secondary)
            }
            Chart(memHistory) { s in
                AreaMark(x: .value("t", s.t), y: .value("v", s.value))
                    .foregroundStyle(LinearGradient(
                        colors: [pressureColor.opacity(0.5), pressureColor.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("t", s.t), y: .value("v", s.value))
                    .foregroundStyle(pressureColor)
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.06))
                }
            }
            .frame(height: 70)

            HStack(spacing: 14) {
                stat("Inactive", String(format: "%.1f GB", mem.inactiveGB))
                stat("Compressed", String(format: "%.1f GB", mem.compressedGB))
                stat("Pressure", String(format: "%.0f%%", mem.pressurePercent))
                    .foregroundColor(pressureColor)
            }
        }
    }

    private var cpuCard: some View {
        card {
            HStack {
                Label("CPU", systemImage: "cpu")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(String(format: "%.0f%%", currentCPU))
                    .font(.caption.monospacedDigit()).foregroundColor(.secondary)
            }
            Chart(cpuHistory) { s in
                AreaMark(x: .value("t", s.t), y: .value("v", s.value))
                    .foregroundStyle(LinearGradient(
                        colors: [.cyan.opacity(0.5), .cyan.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("t", s.t), y: .value("v", s.value))
                    .foregroundStyle(Color.cyan)
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.06))
                }
            }
            .frame(height: 70)
        }
    }

    @ViewBuilder
    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .padding(12)
            .background(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.06), lineWidth: 1))
            .cornerRadius(10)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.caption.monospacedDigit())
        }
    }

    private var pressureColor: Color {
        switch mem.pressurePercent {
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
                    .background(tint.opacity(0.18))
                    .foregroundColor(tint)
                    .cornerRadius(6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(subtitle).font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 8).padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06), lineWidth: 1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    // MARK: - Right

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Running apps").font(.system(size: 14, weight: .semibold))
                Text("\(apps.count)").font(.caption).foregroundColor(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.white.opacity(0.08)).cornerRadius(4)
                Spacer()
                Button {
                    quitSelected()
                } label: {
                    Label("Quit selected", systemImage: "xmark.circle.fill")
                }
                .disabled(selection.isEmpty || busy)
            }
            .padding(.horizontal, 14).padding(.top, 14)

            List(apps, selection: $selection) { app in
                HStack(spacing: 10) {
                    if let icon = app.icon {
                        Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                    }
                    Text(app.name).font(.system(size: 13))
                    Spacer()
                    if AppManager.isProtected(app) {
                        Image(systemName: "lock.fill")
                            .font(.caption2).foregroundColor(.secondary.opacity(0.6))
                    }
                    Text(String(format: "%.0f MB", app.memoryMB))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(memColor(app.memoryMB))
                        .frame(width: 70, alignment: .trailing)
                }
                .tag(app.id)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.inset)

            Divider().opacity(0.3)
            Text("ACTIVITY").font(.caption2).bold().foregroundColor(.secondary).tracking(1.5)
                .padding(.horizontal, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(log.indices.reversed(), id: \.self) { i in
                        Text(log[i]).font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
            }
            .frame(height: 120)
            .padding(.bottom, 10)
        }
    }

    private func memColor(_ mb: Double) -> Color {
        switch mb {
        case ..<200: return .secondary
        case ..<800: return .yellow
        default: return .orange
        }
    }

    // MARK: - Refresh / actions

    private func refresh() {
        mem = SystemStats.memory()
        currentCPU = cpuSampler.sample()
        let now = Date()
        memHistory.append(Sample(t: now, value: mem.pressurePercent))
        cpuHistory.append(Sample(t: now, value: currentCPU))
        let cutoff = now.addingTimeInterval(-historyWindow)
        memHistory.removeAll { $0.t < cutoff }
        cpuHistory.removeAll { $0.t < cutoff }
    }

    private func refreshApps() { apps = AppManager.runningApps() }

    private func runAsync(_ work: @escaping () -> OptimizeResult) {
        busy = true
        DispatchQueue.global().async {
            let r = work()
            DispatchQueue.main.async {
                logLine("\(r.success ? "✓" : "✗") \(r.action.rawValue): \(r.detail)")
                busy = false
                refresh(); refreshApps()
            }
        }
    }

    private func quitSelected() {
        let toQuit = apps.filter { selection.contains($0.id) && !AppManager.isProtected($0) }
        for app in toQuit {
            AppManager.quit(app)
            logLine("✓ Quit \(app.name) (freed ~\(Int(app.memoryMB)) MB)")
        }
        selection.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { refreshApps() }
    }

    private func runOneClick() {
        busy = true
        DispatchQueue.global().async {
            let dnd = Optimizer.setDoNotDisturb(enabled: true)
            let sp = Optimizer.setSpotlight(enabled: false)
            let purge = Optimizer.freeInactiveMemory()
            DispatchQueue.main.async {
                if sp.success { spotlightPaused = true }
                if dnd.success { dndOn = true }
                for r in [dnd, sp, purge] {
                    logLine("\(r.success ? "✓" : "✗") \(r.action.rawValue): \(r.detail)")
                }
                logLine("— One-click Boost complete —")
                busy = false
                refresh(); refreshApps()
            }
        }
    }

    private func logLine(_ s: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        log.append("[\(stamp)] \(s)")
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }
}
