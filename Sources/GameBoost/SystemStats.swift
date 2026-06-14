import Foundation
import Darwin

struct MemoryStats {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let freeBytes: UInt64
    let activeBytes: UInt64
    let inactiveBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let pressurePercent: Double

    var usedGB: Double { Double(usedBytes) / 1_073_741_824 }
    var totalGB: Double { Double(totalBytes) / 1_073_741_824 }
    var inactiveGB: Double { Double(inactiveBytes) / 1_073_741_824 }
    var compressedGB: Double { Double(compressedBytes) / 1_073_741_824 }
}

struct CPUTicks {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64
    var total: UInt64 { user + system + idle + nice }
    var busy: UInt64 { user + system + nice }
}

final class CPUSampler {
    private var last: CPUTicks?

    /// Returns CPU usage percent since the previous call (0–100). First call returns 0.
    func sample() -> Double {
        guard let now = SystemStats.cpuTicks() else { return 0 }
        defer { last = now }
        guard let prev = last else { return 0 }
        let dTotal = Double(now.total &- prev.total)
        let dBusy = Double(now.busy &- prev.busy)
        guard dTotal > 0 else { return 0 }
        return min(100, max(0, dBusy / dTotal * 100))
    }
}

enum SystemStats {
    static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    static func memory() -> MemoryStats {
        var size: UInt64 = 0
        var sizeLen = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &sizeLen, nil, 0)

        let pageSize = UInt64(vm_kernel_page_size)
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return MemoryStats(totalBytes: size, usedBytes: 0, freeBytes: 0, activeBytes: 0,
                               inactiveBytes: 0, wiredBytes: 0, compressedBytes: 0, pressurePercent: 0)
        }

        let free = UInt64(vmStats.free_count) * pageSize
        let active = UInt64(vmStats.active_count) * pageSize
        let inactive = UInt64(vmStats.inactive_count) * pageSize
        let wired = UInt64(vmStats.wire_count) * pageSize
        let compressed = UInt64(vmStats.compressor_page_count) * pageSize
        let used = active + wired + compressed

        let pressure = size > 0 ? Double(used) / Double(size) * 100 : 0

        return MemoryStats(totalBytes: size, usedBytes: used, freeBytes: free,
                           activeBytes: active, inactiveBytes: inactive, wiredBytes: wired,
                           compressedBytes: compressed, pressurePercent: pressure)
    }

    static func cpuModel() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0)
        return String(cString: bytes)
    }

    static func uptime() -> String {
        var boottime = timeval()
        var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &boottime, &size, nil, 0)
        let bootDate = Date(timeIntervalSince1970: TimeInterval(boottime.tv_sec))
        let interval = Date().timeIntervalSince(bootDate)
        let hours = Int(interval) / 3600
        let mins = (Int(interval) % 3600) / 60
        return "\(hours)h \(mins)m"
    }
}
