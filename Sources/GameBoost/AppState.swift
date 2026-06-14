import Foundation
import SwiftUI
import AppKit
import Combine

struct Sample: Identifiable {
    let id = UUID()
    let t: Date
    let value: Double
}

/// Measured before/after result of a boost.
struct BoostReceipt {
    let date: Date
    let ramReclaimedGB: Double
    let pressureBefore: Double
    let pressureAfter: Double
    let appsQuit: Int

    var summary: String {
        var parts: [String] = []
        if appsQuit > 0 { parts.append("quit \(appsQuit) app\(appsQuit == 1 ? "" : "s")") }
        if ramReclaimedGB >= 0.1 { parts.append(String(format: "reclaimed %.1f GB", ramReclaimedGB)) }
        parts.append(String(format: "pressure %.0f%% → %.0f%%", pressureBefore, pressureAfter))
        return parts.joined(separator: " · ")
    }
}

/// Single source of truth, shared by the main window and the menu-bar popover.
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var mem: MemoryStats = SystemStats.memory()
    @Published var apps: [RunningApp] = []
    @Published var log: [String] = []
    @Published var busy = false
    @Published var spotlightPaused = false
    @Published var dndOn = false
    @Published var selection: Set<pid_t> = []
    @Published var memHistory: [Sample] = []
    @Published var cpuHistory: [Sample] = []
    @Published var currentCPU: Double = 0
    @Published var thermal: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    @Published var power: PowerInfo = SystemStats.power()
    @Published var keepAwakeOn = false
    @Published var appSort: AppSort = .memory
    @Published var lastReceipt: BoostReceipt?

    enum AppSort: String, CaseIterable { case memory = "Memory", cpu = "CPU" }

    private struct ActiveGame { let profile: GameProfile; let start: Date }
    private var activeGames: [pid_t: ActiveGame] = [:]

    private let cpuSampler = CPUSampler()
    private let keepAwake = KeepAwake()
    private var statsTimer: Timer?
    private var appsTimer: Timer?
    private let historyWindow: TimeInterval = 60
    private var started = false

    private init() {
        _ = cpuSampler.sample()
        observeTerminations()
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        refresh(); refreshApps()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        appsTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refreshApps()
        }
    }

    func refresh() {
        mem = SystemStats.memory()
        currentCPU = cpuSampler.sample()
        thermal = ProcessInfo.processInfo.thermalState
        power = SystemStats.power()
        let now = Date()
        memHistory.append(Sample(t: now, value: mem.pressurePercent))
        cpuHistory.append(Sample(t: now, value: currentCPU))
        let cutoff = now.addingTimeInterval(-historyWindow)
        memHistory.removeAll { $0.t < cutoff }
        cpuHistory.removeAll { $0.t < cutoff }
    }

    func refreshApps() {
        let list = AppManager.runningApps()
        switch appSort {
        case .memory: apps = list.sorted { $0.memoryMB > $1.memoryMB }
        case .cpu:    apps = list.sorted { $0.cpuPercent > $1.cpuPercent }
        }
    }

    func setKeepAwake(_ on: Bool) {
        keepAwakeOn = keepAwake.set(on)
        logLine(keepAwakeOn ? "☕️ Keep-awake on — display won't sleep" : "💤 Keep-awake off")
    }

    // MARK: - Single actions

    func freeMemory() { runAsync { Optimizer.freeInactiveMemory() } }

    func setSpotlightPaused(_ paused: Bool) {
        runAsync {
            let r = Optimizer.setSpotlight(enabled: !paused)
            if r.success { DispatchQueue.main.async { self.spotlightPaused = paused } }
            return r
        }
    }

    func setDND(_ on: Bool) {
        runAsync {
            let r = Optimizer.setDoNotDisturb(enabled: on)
            if r.success { DispatchQueue.main.async { self.dndOn = on } }
            return r
        }
    }

    func quitSelected() {
        let toQuit = apps.filter { selection.contains($0.id) && !AppManager.isProtected($0) }
        for app in toQuit {
            AppManager.quit(app)
            logLine("✓ Quit \(app.name) (freed ~\(Int(app.memoryMB)) MB)")
        }
        selection.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refreshApps() }
    }

    func oneClickBoost() {
        let cfg = SettingsStore.shared.boost
        busy = true
        logLine("⚡ One-click Boost (\(cfg.summary))…")
        let before = SystemStats.memory()
        DispatchQueue.global().async {
            var lines: [String] = []
            var didSpotlight = false, didDND = false
            var quitCount = 0

            if cfg.quitHeavyApps {
                let heavy = AppManager.runningApps()
                    .filter { !AppManager.isProtected($0) && $0.memoryMB >= cfg.heavyThresholdMB }
                for app in heavy {
                    AppManager.quit(app)
                    quitCount += 1
                    lines.append("✓ Quit \(app.name) (~\(Int(app.memoryMB)) MB)")
                }
            }
            if cfg.enableDND {
                let r = Optimizer.setDoNotDisturb(enabled: true)
                lines.append(self.fmt(r)); didDND = r.success
            }
            if cfg.pauseSpotlight {
                let r = Optimizer.setSpotlight(enabled: false)
                lines.append(self.fmt(r)); didSpotlight = r.success
            }
            if cfg.freeMemory {
                lines.append(self.fmt(Optimizer.freeInactiveMemory()))
            }

            DispatchQueue.main.async {
                if didSpotlight { self.spotlightPaused = true }
                if didDND { self.dndOn = true }
                if lines.isEmpty {
                    lines.append("No actions enabled — customize the boost with the gear button.")
                }
                lines.forEach { self.logLine($0) }
                self.busy = false
                self.refresh(); self.refreshApps()
                // Measure the result after things settle, then post a receipt.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    let after = SystemStats.memory()
                    let reclaimed = max(0, before.usedGB - after.usedGB)
                    let receipt = BoostReceipt(date: Date(),
                                               ramReclaimedGB: reclaimed,
                                               pressureBefore: before.pressurePercent,
                                               pressureAfter: after.pressurePercent,
                                               appsQuit: quitCount)
                    self.lastReceipt = receipt
                    self.logLine("🧾 Boost result: \(receipt.summary)")
                    self.refresh()
                }
            }
        }
    }

    // MARK: - Game profiles

    func launchProfile(_ p: GameProfile) {
        guard FileManager.default.fileExists(atPath: p.appPath) else {
            logLine("✗ '\(p.name)' app not found at \(p.appPath)")
            return
        }
        busy = true
        logLine("▶ Launching profile '\(p.name)'…")
        DispatchQueue.global().async {
            var lines: [String] = []
            for bid in p.quitBundleIDs {
                for app in NSRunningApplication.runningApplications(withBundleIdentifier: bid) {
                    let name = app.localizedName ?? bid
                    app.terminate()
                    lines.append("✓ Quit \(name)")
                }
            }
            if p.pauseSpotlight { lines.append(self.fmt(Optimizer.setSpotlight(enabled: false))) }
            if p.enableDND { lines.append(self.fmt(Optimizer.setDoNotDisturb(enabled: true))) }
            if p.freeMemory { lines.append(self.fmt(Optimizer.freeInactiveMemory())) }
            DispatchQueue.main.async {
                if p.pauseSpotlight { self.spotlightPaused = true }
                if p.enableDND { self.dndOn = true }
                lines.forEach { self.logLine($0) }
                self.launchApp(p)
            }
        }
    }

    private func launchApp(_ p: GameProfile) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if p.metalHUD {
            config.environment = ["MTL_HUD_ENABLED": "1", "MTL_HUD_ALIGNMENT": "top-right"]
        }
        NSWorkspace.shared.openApplication(at: p.appURL, configuration: config) { [weak self] app, err in
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                if let err {
                    self.logLine("✗ Could not launch \(p.name): \(err.localizedDescription)")
                    return
                }
                self.logLine("🎮 Launched \(p.name)\(p.metalHUD ? " (FPS HUD on)" : "")")
                if let app {
                    self.activeGames[app.processIdentifier] = ActiveGame(profile: p, start: Date())
                    if p.autoRestore {
                        self.logLine("⏲ Auto-restore armed — will revert when \(p.name) quits")
                    }
                }
            }
        }
    }

    private func observeTerminations() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self.handleTermination(pid: app.processIdentifier)
        }
    }

    private func handleTermination(pid: pid_t) {
        guard let game = activeGames[pid] else { return }
        activeGames[pid] = nil
        let p = game.profile

        // Log the play session.
        SessionStore.shared.add(game: p.name, start: game.start, end: Date())
        let mins = Int(Date().timeIntervalSince(game.start) / 60)
        logLine("■ \(p.name) quit after \(mins)m — session logged")

        guard p.autoRestore else { refresh(); return }
        logLine("Restoring system…")
        DispatchQueue.global().async {
            var lines: [String] = []
            if p.pauseSpotlight { lines.append(self.fmt(Optimizer.setSpotlight(enabled: true))) }
            if p.enableDND { lines.append(self.fmt(Optimizer.setDoNotDisturb(enabled: false))) }
            DispatchQueue.main.async {
                if p.pauseSpotlight { self.spotlightPaused = false }
                if p.enableDND { self.dndOn = false }
                lines.forEach { self.logLine($0) }
                self.refresh()
            }
        }
    }

    // MARK: - Helpers

    private func runAsync(_ work: @escaping () -> OptimizeResult) {
        busy = true
        DispatchQueue.global().async {
            let r = work()
            DispatchQueue.main.async {
                self.logLine(self.fmt(r))
                self.busy = false
                self.refresh(); self.refreshApps()
            }
        }
    }

    private func fmt(_ r: OptimizeResult) -> String {
        "\(r.success ? "✓" : "✗") \(r.action.rawValue): \(r.detail)"
    }

    func logLine(_ s: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        log.append("[\(stamp)] \(s)")
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    /// Bring the main dashboard window forward (used from the menu bar).
    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows where w.canBecomeMain {
            w.makeKeyAndOrderFront(nil)
        }
    }
}
