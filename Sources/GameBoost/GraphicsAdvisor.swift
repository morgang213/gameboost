import Foundation
import SwiftUI
import AppKit
import Metal

struct HardwareInfo {
    var chip: String
    var isAppleSilicon: Bool
    var cpuCores: Int
    var ramGB: Double
    var gpuName: String
    var gpuCores: Int?      // Apple Silicon only
    var vramGB: Double
    var unifiedMemory: Bool
    var displayWidth: Int
    var displayHeight: Int
    var refreshHz: Int

    var displayLabel: String { "\(displayWidth)×\(displayHeight) @ \(refreshHz)Hz" }
    var gpuLabel: String {
        if let c = gpuCores { return "\(gpuName) · \(c)-core GPU" }
        return gpuName
    }
}

struct GraphicsRecommendation {
    let tier: String
    let tierLevel: Int           // 0 Low … 3 Ultra
    let settings: [(String, String)]
    let notes: [String]
}

enum GraphicsAdvisor {
    /// Fast detection safe to run on the main thread (no shell-outs).
    static func quickInfo() -> HardwareInfo {
        let chip = SystemStats.cpuModel()

        var arm: Int32 = 0; var asz = MemoryLayout<Int32>.size
        sysctlbyname("hw.optional.arm64", &arm, &asz, nil, 0)
        let isAS = arm == 1

        var cores: Int32 = 0; var csz = MemoryLayout<Int32>.size
        sysctlbyname("hw.physicalcpu", &cores, &csz, nil, 0)

        let ramGB = Double(SystemStats.memory().totalBytes) / 1_073_741_824

        var gpuName = "Unknown GPU", vramGB = 0.0, unified = false
        if let dev = MTLCreateSystemDefaultDevice() {
            gpuName = dev.name
            unified = dev.hasUnifiedMemory
            vramGB = Double(dev.recommendedMaxWorkingSetSize) / 1_073_741_824
        }

        var w = 1920, h = 1080, hz = 60
        if let screen = NSScreen.main {
            let scale = screen.backingScaleFactor
            w = Int(screen.frame.width * scale)
            h = Int(screen.frame.height * scale)
            if screen.maximumFramesPerSecond > 0 { hz = screen.maximumFramesPerSecond }
        }

        return HardwareInfo(chip: chip, isAppleSilicon: isAS, cpuCores: Int(cores),
                            ramGB: ramGB, gpuName: gpuName, gpuCores: nil,
                            vramGB: vramGB, unifiedMemory: unified,
                            displayWidth: w, displayHeight: h, refreshHz: hz)
    }

    /// Apple GPU core count via system_profiler (slow ~1s — call off the main thread).
    static func appleGPUCores() -> Int? {
        let task = Process()
        task.launchPath = "/usr/sbin/system_profiler"
        task.arguments = ["SPDisplaysDataType"]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8) else { return nil }
        for line in out.split(separator: "\n") where line.contains("Total Number of Cores") {
            let digits = line.filter { $0.isNumber }
            return Int(digits)
        }
        return nil
    }

    static func recommend(_ hw: HardwareInfo) -> GraphicsRecommendation {
        var level: Int
        if let c = hw.gpuCores {
            if c >= 30 { level = 3 } else if c >= 16 { level = 2 } else if c >= 10 { level = 1 } else { level = 0 }
        } else if hw.vramGB >= 12 { level = 3 }
        else if hw.vramGB >= 8 { level = 2 }
        else if hw.vramGB >= 4 { level = 1 }
        else { level = 0 }

        var notes: [String] = []
        if hw.ramGB <= 8.5 && level >= 2 {
            level = 1
            notes.append("Capped at Medium: \(Int(hw.ramGB)) GB of \(hw.unifiedMemory ? "unified " : "")memory is shared with macOS, so high-res textures will swap and stutter.")
        }

        let tierNames = ["Low", "Medium", "High", "Ultra"]
        let pixels = hw.displayWidth * hw.displayHeight
        let is5Kplus = pixels >= 13_000_000
        let is4Kplus = pixels >= 7_500_000 && !is5Kplus
        let is1440 = pixels >= 3_400_000 && !is4Kplus && !is5Kplus

        // Resolution / render scale
        var renderScale = "100% (native)"
        switch level {
        case 3:
            if is5Kplus { renderScale = "80% + MetalFX upscaling" }
        case 2:
            if is5Kplus { renderScale = "60% + MetalFX" }
            else if is4Kplus { renderScale = "80% + MetalFX" }
        case 1:
            if is5Kplus { renderScale = "50%" }
            else if is4Kplus { renderScale = "67%" }
            else if is1440 { renderScale = "85%" }
        default:
            renderScale = is4Kplus || is5Kplus ? "50%" : (is1440 ? "67%" : "75%")
        }

        var texture = ["Low", "Medium", "High", "Ultra"][level]
        if hw.ramGB <= 8.5 && (texture == "High" || texture == "Ultra") { texture = "Medium" }
        let shadows = ["Low", "Medium", "High", "High/Ultra"][level]
        let aa = ["Off / FXAA", "FXAA or TAA", "TAA", "TAA (high quality)"][level]
        let effects = ["Low", "Medium", "High", "Ultra"][level]

        let refresh = hw.refreshHz
        let targetFPS: String
        switch level {
        case 3: targetFPS = refresh >= 120 ? "120 (ProMotion)" : "\(refresh)"
        case 2: targetFPS = refresh >= 120 ? "90–120" : "60"
        case 1: targetFPS = "60"
        default: targetFPS = "30–60"
        }
        let vsync = (level >= 2 && refresh >= 120) ? "Off (cap FPS / ProMotion)" : "On (steadier frame times)"

        // Notes / reasoning
        if hw.isAppleSilicon && level >= 2 {
            notes.append("On Apple Silicon, prefer MetalFX upscaling over native 4K/5K — it buys a lot of headroom for little visible loss.")
        }
        if !hw.isAppleSilicon {
            notes.append("Intel Mac with an older/discrete GPU — start one tier lower than suggested and raise settings until frames dip.")
        }
        notes.append("Cap in-game FPS at your display's \(refresh) Hz — rendering past it just heats the chip for no benefit.")
        notes.append("Run One-click Boost (or a game profile) before measuring, so background apps aren't stealing GPU/CPU.")
        notes.append("These are hardware-tier guesses, not per-game. Setting names vary by title — match the intent (e.g. \"Texture Quality\", \"Shadow Detail\").")

        let settings: [(String, String)] = [
            ("Resolution / render scale", renderScale),
            ("Texture quality", texture),
            ("Shadow quality", shadows),
            ("Anti-aliasing", aa),
            ("Effects / post-processing", effects),
            ("Target frame rate", "\(targetFPS) fps"),
            ("V-Sync", vsync),
        ]
        return GraphicsRecommendation(tier: tierNames[level], tierLevel: level, settings: settings, notes: notes)
    }
}

struct GraphicsView: View {
    @State private var hw: HardwareInfo?
    @State private var rec: GraphicsRecommendation?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if loading {
                    HStack { ProgressView(); Text("Detecting hardware…").foregroundColor(.secondary) }
                        .padding(.top, 20)
                }
                if let hw { hardwareCard(hw) }
                if let rec { recommendationCard(rec) }
                if let rec { notesCard(rec) }
            }
            .padding(16)
        }
        .onAppear(perform: detect)
    }

    private func detect() {
        guard hw == nil else { return }
        let quick = GraphicsAdvisor.quickInfo()
        hw = quick
        DispatchQueue.global().async {
            let cores = GraphicsAdvisor.appleGPUCores()
            DispatchQueue.main.async {
                var h = quick; h.gpuCores = cores
                hw = h
                rec = GraphicsAdvisor.recommend(h)
                loading = false
            }
        }
    }

    private func hardwareCard(_ hw: HardwareInfo) -> some View {
        card {
            Label("This Mac", systemImage: "cpu").font(.system(size: 13, weight: .semibold))
            row("Chip", hw.chip)
            row("CPU", "\(hw.cpuCores) cores")
            row("GPU", hw.gpuLabel)
            row("Memory", String(format: "%.0f GB%@", hw.ramGB, hw.unifiedMemory ? " unified" : ""))
            row("Display", hw.displayLabel)
        }
    }

    private func recommendationCard(_ rec: GraphicsRecommendation) -> some View {
        card {
            HStack {
                Label("Suggested graphics settings", systemImage: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(rec.tier.uppercased())
                    .font(.caption2).bold()
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(tierColor(rec.tierLevel).opacity(0.2))
                    .foregroundColor(tierColor(rec.tierLevel))
                    .cornerRadius(5)
            }
            VStack(spacing: 0) {
                ForEach(rec.settings.indices, id: \.self) { i in
                    HStack {
                        Text(rec.settings[i].0).font(.system(size: 12)).foregroundColor(.secondary)
                        Spacer()
                        Text(rec.settings[i].1).font(.system(size: 12, weight: .medium))
                    }
                    .padding(.vertical, 7)
                    if i < rec.settings.count - 1 { Divider().opacity(0.25) }
                }
            }
        }
    }

    private func notesCard(_ rec: GraphicsRecommendation) -> some View {
        card {
            Label("Why these", systemImage: "info.circle").font(.system(size: 13, weight: .semibold))
            ForEach(rec.notes.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 6) {
                    Text("•").foregroundColor(.secondary)
                    Text(rec.notes[i]).font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
            .cornerRadius(10)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(size: 12, weight: .medium)).multilineTextAlignment(.trailing)
        }
    }

    private func tierColor(_ level: Int) -> Color {
        [.gray, .blue, .green, .purple][level]
    }
}
