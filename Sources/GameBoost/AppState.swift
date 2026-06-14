import Foundation
import SwiftUI
import AppKit
import Combine

struct Sample: Identifiable {
    let id = UUID()
    let t: Date
    let value: Double
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

    private let cpuSampler = CPUSampler()
    private var statsTimer: Timer?
    private var appsTimer: Timer?
    private let historyWindow: TimeInterval = 60
    private var activeSessions: [pid_t: GameProfile] = [:]
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
        let now = Date()
        memHistory.append(Sample(t: now, value: mem.pressurePercent))
        cpuHistory.append(Sample(t: now, value: currentCPU))
        let cutoff = now.addingTimeInterval(-historyWindow)
        memHistory.removeAll { $0.t < cutoff }
        cpuHistory.removeAll { $0.t < cutoff }
    }

    func refreshApps() { apps = AppManager.runningApps() }

    // MARK: - Single actions

    func freeMemory() { runAsync { Optimizer.freeInactiveMemory() } }

    func toggleSpotlight() {
        let target = !spotlightPaused
        runAsync {
            let r = Optimizer.setSpotlight(enabled: !target)
            if r.success { DispatchQueue.main.async { self.spotlightPaused = target } }
            return r
        }
    }

    func toggleDND() {
        let target = !dndOn
        runAsync {
            let r = Optimizer.setDoNotDisturb(enabled: target)
            if r.success { DispatchQueue.main.async { self.dndOn = target } }
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
        busy = true
        DispatchQueue.global().async {
            let dnd = Optimizer.setDoNotDisturb(enabled: true)
            let sp = Optimizer.setSpotlight(enabled: false)
            let purge = Optimizer.freeInactiveMemory()
            DispatchQueue.main.async {
                if sp.success { self.spotlightPaused = true }
                if dnd.success { self.dndOn = true }
                [dnd, sp, purge].forEach { self.logLine(self.fmt($0)) }
                self.logLine("— One-click Boost complete —")
                self.busy = false
                self.refresh(); self.refreshApps()
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
        NSWorkspace.shared.openApplication(at: p.appURL, configuration: config) { [weak self] app, err in
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                if let err {
                    self.logLine("✗ Could not launch \(p.name): \(err.localizedDescription)")
                    return
                }
                self.logLine("🎮 Launched \(p.name)")
                if p.autoRestore, let app {
                    self.activeSessions[app.processIdentifier] = p
                    self.logLine("⏲ Auto-restore armed — will revert when \(p.name) quits")
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
        guard let p = activeSessions[pid] else { return }
        activeSessions[pid] = nil
        logLine("■ \(p.name) quit — restoring system")
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
