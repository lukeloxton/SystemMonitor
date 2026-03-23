import Foundation
import Darwin

final class SystemStats: ObservableObject {
    @Published var cpuUsage: Double = 0
    @Published var memoryUsage: Double = 0
    @Published var memoryUsed: Double = 0
    @Published var memoryTotal: Double = 0
    @Published var diskUsage: Double = 0
    @Published var diskUsed: Double = 0
    @Published var diskTotal: Double = 0

    private var timer: Timer?
    private var previousInfo: host_cpu_load_info?

    init() {
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    deinit {
        timer?.invalidate()
    }

    private func update() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let cpu = Self.readCPU(previous: self?.previousInfo)
            let mem = Self.readMemory()
            let disk = Self.readDisk()

            DispatchQueue.main.async {
                self?.previousInfo = cpu.info
                self?.cpuUsage = cpu.usage
                self?.memoryUsage = mem.usage
                self?.memoryUsed = mem.used
                self?.memoryTotal = mem.total
                self?.diskUsage = disk.usage
                self?.diskUsed = disk.used
                self?.diskTotal = disk.total
            }
        }
    }

    // MARK: - CPU

    private static func readCPU(previous: host_cpu_load_info?) -> (usage: Double, info: host_cpu_load_info) {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()

        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return (0, info) }

        let user = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3)

        if let prev = previous {
            let dUser = user - Double(prev.cpu_ticks.0)
            let dSystem = system - Double(prev.cpu_ticks.1)
            let dIdle = idle - Double(prev.cpu_ticks.2)
            let dNice = nice - Double(prev.cpu_ticks.3)
            let total = dUser + dSystem + dIdle + dNice
            if total > 0 {
                return (min(100, (dUser + dSystem + dNice) / total * 100), info)
            }
        }

        let total = user + system + idle + nice
        if total > 0 {
            return (min(100, (user + system + nice) / total * 100), info)
        }
        return (0, info)
    }

    // MARK: - Memory

    private static func readMemory() -> (usage: Double, used: Double, total: Double) {
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        let totalGB = totalBytes / 1_073_741_824

        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var stats = vm_statistics64_data_t()

        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return (0, 0, totalGB) }

        let pageSize = Double(vm_kernel_page_size)
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let speculative = Double(stats.speculative_count) * pageSize

        let used = active + wired + compressed - speculative
        let usedGB = max(0, used) / 1_073_741_824
        let usage = min(100, usedGB / totalGB * 100)

        return (usage, usedGB, totalGB)
    }

    // MARK: - Disk

    private static func readDisk() -> (usage: Double, used: Double, total: Double) {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: "/")
            let total = (attrs[.systemSize] as? Int64) ?? 0
            let free = (attrs[.systemFreeSize] as? Int64) ?? 0
            let used = total - free
            let totalGB = Double(total) / 1_073_741_824
            let usedGB = Double(used) / 1_073_741_824
            let usage = totalGB > 0 ? usedGB / totalGB * 100 : 0
            return (usage, usedGB, totalGB)
        } catch {
            return (0, 0, 0)
        }
    }
}
