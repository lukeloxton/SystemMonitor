import Foundation
import Darwin

public struct ProcessMemInfo: Identifiable {
    public let id: Int32
    public let name: String
    public let rssBytes: UInt64
    public var rssMB: Double { Double(rssBytes) / 1_048_576 }
}

public struct ProcessCPUInfo: Identifiable {
    public let id: Int32
    public let name: String
    public let cpuPercent: Double
}

public struct CoreCPUInfo: Identifiable {
    public let id: Int
    public let usage: Double
}

public struct LargeFileInfo: Identifiable {
    public let id: String
    public let name: String
    public let path: String
    public let sizeBytes: Int64
    public var sizeMB: Double { Double(sizeBytes) / 1_048_576 }
}

public final class SystemStats: ObservableObject {
    @Published public var cpuUsage: Double = 0
    @Published public var memoryUsage: Double = 0
    @Published public var memoryUsed: Double = 0
    @Published public var memoryTotal: Double = 0
    @Published public var diskUsage: Double = 0
    @Published public var diskUsed: Double = 0
    @Published public var diskTotal: Double = 0
    @Published public var topMemProcesses: [ProcessMemInfo] = []
    @Published public var topCPUProcesses: [ProcessCPUInfo] = []
    @Published public var perCoreCPU: [CoreCPUInfo] = []
    @Published public var loadAvg: (one: Double, five: Double, fifteen: Double) = (0, 0, 0)
    @Published public var largeFiles: [LargeFileInfo] = []
    @Published public var netUpBPS:   Double = 0
    @Published public var netDownBPS: Double = 0

    private var timer: Timer?
    private var previousCPUInfo: host_cpu_load_info?
    private var prevCoreTicks: [[integer_t]] = []
    private var prevTaskTimes: [Int32: (user: UInt64, sys: UInt64)] = [:]
    private var prevSampleWall: Double = 0
    private var metadataQuery: NSMetadataQuery?
    private var queryObserver: NSObjectProtocol?
    private var prevNetBytes: (up: UInt64, down: UInt64) = (0, 0)
    private var prevNetWall:  Double = 0

    public init() {
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    deinit {
        timer?.invalidate()
        metadataQuery?.stop()
        if let obs = queryObserver { NotificationCenter.default.removeObserver(obs) }
    }

    // MARK: - Regular update

    private func update() {
        let capturedPrev      = prevTaskTimes
        let capturedWall      = prevSampleWall
        let capturedCoreTicks = prevCoreTicks
        let capturedPrevNet   = prevNetBytes
        let capturedNetWall   = prevNetWall

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let cpu     = Self.readCPU(previous: self.previousCPUInfo)
            let mem     = Self.readMemory()
            let disk    = Self.readDisk()
            let load    = Self.readLoadAvg()
            let wallNow = Date().timeIntervalSinceReferenceDate
            let (memProcs, cpuProcs, newTimes) = Self.readProcessStats(
                prevTimes: capturedPrev, prevWall: capturedWall, wallNow: wallNow
            )
            let (cores, newCoreTicks) = Self.readPerCoreCPU(previous: capturedCoreTicks)
            let net     = Self.readNetworkBytes()
            let netDt   = wallNow - capturedNetWall
            let netUp   = netDt > 0 && capturedPrevNet.up > 0 && net.up >= capturedPrevNet.up
                ? Double(net.up   - capturedPrevNet.up)   / netDt : 0
            let netDown = netDt > 0 && capturedPrevNet.down > 0 && net.down >= capturedPrevNet.down
                ? Double(net.down - capturedPrevNet.down) / netDt : 0

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.previousCPUInfo = cpu.info
                self.cpuUsage        = cpu.usage
                self.memoryUsage     = mem.usage
                self.memoryUsed      = mem.used
                self.memoryTotal     = mem.total
                self.diskUsage       = disk.usage
                self.diskUsed        = disk.used
                self.diskTotal       = disk.total
                self.topMemProcesses = memProcs
                self.topCPUProcesses = cpuProcs
                self.perCoreCPU      = cores
                self.loadAvg         = load
                self.prevTaskTimes   = newTimes
                self.prevSampleWall  = wallNow
                self.prevCoreTicks   = newCoreTicks
                self.netUpBPS    = netUp
                self.netDownBPS  = netDown
                self.prevNetBytes = net
                self.prevNetWall  = wallNow
            }
        }
    }

    // MARK: - On-demand CPU fast sample (called when section expands)

    public func triggerFastCPUSample() {
        topCPUProcesses = []
        perCoreCPU = []
        let wall1 = Date().timeIntervalSinceReferenceDate
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let (_, _, times1)     = Self.readProcessStats(prevTimes: [:], prevWall: 0, wallNow: wall1)
            let (_, coreTicks1)    = Self.readPerCoreCPU(previous: [])
            Thread.sleep(forTimeInterval: 0.8)
            let wall2 = Date().timeIntervalSinceReferenceDate
            let (_, cpuProcs, times2) = Self.readProcessStats(prevTimes: times1, prevWall: wall1, wallNow: wall2)
            let (cores, coreTicks2)   = Self.readPerCoreCPU(previous: coreTicks1)
            let load = Self.readLoadAvg()
            DispatchQueue.main.async { [weak self] in
                self?.topCPUProcesses = cpuProcs
                self?.perCoreCPU      = cores
                self?.loadAvg         = load
                self?.prevTaskTimes   = times2
                self?.prevSampleWall  = wall2
                self?.prevCoreTicks   = coreTicks2
            }
        }
    }

    // MARK: - On-demand large file scan via Spotlight (called when section expands)

    public func triggerLargeFilesScan() {
        // Must be called on main thread — NSMetadataQuery requires a run loop
        metadataQuery?.stop()
        if let obs = queryObserver { NotificationCenter.default.removeObserver(obs); queryObserver = nil }
        largeFiles = []

        let query = NSMetadataQuery()
        let minSize = (50 * 1_048_576) as NSNumber
        query.predicate = NSPredicate(
            format: "kMDItemFSSize > %@ && kMDItemContentTypeTree != 'public.folder'",
            minSize
        )
        let home = FileManager.default.homeDirectoryForCurrentUser
        query.searchScopes = ["Downloads", "Desktop", "Documents", "Movies", "Music"]
            .map { home.appendingPathComponent($0) }
        query.sortDescriptors = [NSSortDescriptor(key: "kMDItemFSSize", ascending: false)]

        queryObserver = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self, weak query] _ in
            guard let self, let query else { return }
            query.stop()
            var files: [LargeFileInfo] = []
            for i in 0..<min(query.resultCount, 10) {
                guard let item = query.result(at: i) as? NSMetadataItem,
                      let path = item.value(forAttribute: "kMDItemPath") as? String,
                      let size = (item.value(forAttribute: "kMDItemFSSize") as? NSNumber)?.int64Value
                else { continue }
                files.append(LargeFileInfo(
                    id: path,
                    name: URL(fileURLWithPath: path).lastPathComponent,
                    path: path,
                    sizeBytes: size
                ))
            }
            self.largeFiles = files
            self.metadataQuery = nil
            if let obs = self.queryObserver { NotificationCenter.default.removeObserver(obs); self.queryObserver = nil }
        }

        metadataQuery = query
        query.start()
    }

    // MARK: - System CPU

    public static func readCPU(previous: host_cpu_load_info?) -> (usage: Double, info: host_cpu_load_info) {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, info) }

        let user   = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle   = Double(info.cpu_ticks.2)
        let nice   = Double(info.cpu_ticks.3)

        if let prev = previous {
            let dU = user   - Double(prev.cpu_ticks.0)
            let dS = system - Double(prev.cpu_ticks.1)
            let dI = idle   - Double(prev.cpu_ticks.2)
            let dN = nice   - Double(prev.cpu_ticks.3)
            let total = dU + dS + dI + dN
            if total > 0 { return (min(100, (dU + dS + dN) / total * 100), info) }
        }
        let total = user + system + idle + nice
        if total > 0 { return (min(100, (user + system + nice) / total * 100), info) }
        return (0, info)
    }

    // MARK: - Memory

    public static func readMemory() -> (usage: Double, used: Double, total: Double) {
        let totalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0, totalGB) }
        let page        = Double(vm_kernel_page_size)
        let active      = Double(stats.active_count)           * page
        let wired       = Double(stats.wire_count)             * page
        let compressed  = Double(stats.compressor_page_count)  * page
        let speculative = Double(stats.speculative_count)      * page
        let usedGB = max(0, active + wired + compressed - speculative) / 1_073_741_824
        return (min(100, usedGB / totalGB * 100), usedGB, totalGB)
    }

    // MARK: - Process Stats

    public static func readProcessStats(
        prevTimes: [Int32: (user: UInt64, sys: UInt64)],
        prevWall: Double,
        wallNow: Double
    ) -> ([ProcessMemInfo], [ProcessCPUInfo], [Int32: (user: UInt64, sys: UInt64)]) {
        let wallDeltaNs = (wallNow - prevWall) * 1_000_000_000
        _ = ProcessInfo.processInfo.processorCount  // unused after per-core fix
        let pidCount    = proc_listallpids(nil, 0)
        guard pidCount > 0 else { return ([], [], [:]) }
        var pids = [Int32](repeating: 0, count: Int(pidCount) + 16)
        let actual = proc_listallpids(&pids, Int32(pids.count) * 4)
        guard actual > 0 else { return ([], [], [:]) }

        var memResults: [ProcessMemInfo] = []
        var cpuResults: [ProcessCPUInfo] = []
        var newTimes: [Int32: (user: UInt64, sys: UInt64)] = [:]
        let infoSize = Int32(MemoryLayout<proc_taskinfo>.size)

        for i in 0..<Int(actual) {
            let pid = pids[i]
            guard pid > 0 else { continue }
            var taskInfo = proc_taskinfo()
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, infoSize) == infoSize else { continue }
            var nameBuf = [CChar](repeating: 0, count: 1024)
            proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            let name = String(cString: nameBuf)
            guard !name.isEmpty else { continue }

            if taskInfo.pti_resident_size > 0 {
                memResults.append(ProcessMemInfo(id: pid, name: name, rssBytes: taskInfo.pti_resident_size))
            }
            let curUser = taskInfo.pti_total_user
            let curSys  = taskInfo.pti_total_system
            newTimes[pid] = (user: curUser, sys: curSys)
            if wallDeltaNs > 0, let prev = prevTimes[pid],
               curUser >= prev.user, curSys >= prev.sys {
                let pct = Double(curUser - prev.user + curSys - prev.sys) / wallDeltaNs * 100
                if pct > 0.1 {
                    cpuResults.append(ProcessCPUInfo(id: pid, name: name, cpuPercent: min(pct, 100)))
                }
            }
        }
        return (
            Array(memResults.sorted { $0.rssBytes   > $1.rssBytes   }.prefix(5)),
            Array(cpuResults.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5)),
            newTimes
        )
    }

    // MARK: - Load Average

    public static func readLoadAvg() -> (one: Double, five: Double, fifteen: Double) {
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)
        return (loads[0], loads[1], loads[2])
    }

    // MARK: - Per-Core CPU

    public static func readPerCoreCPU(previous: [[integer_t]]) -> (cores: [CoreCPUInfo], ticks: [[integer_t]]) {
        var numCPU: natural_t = 0
        var cpuInfoPtr: processor_info_array_t? = nil
        var numCPUInfo: mach_msg_type_number_t = 0

        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPU, &cpuInfoPtr, &numCPUInfo) == KERN_SUCCESS,
              let ptr = cpuInfoPtr else { return ([], previous) }

        defer {
            let sz = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: ptr), sz)
        }

        let stateMax = Int(CPU_STATE_MAX)
        var currentTicks: [[integer_t]] = []
        var cores: [CoreCPUInfo] = []

        for i in 0..<Int(numCPU) {
            let base = stateMax * i
            let ticks = (0..<stateMax).map { ptr[base + $0] }
            currentTicks.append(ticks)

            if i < previous.count {
                let prev  = previous[i]
                let dUser = Double(max(0, ticks[Int(CPU_STATE_USER)]   - prev[Int(CPU_STATE_USER)]))
                let dSys  = Double(max(0, ticks[Int(CPU_STATE_SYSTEM)] - prev[Int(CPU_STATE_SYSTEM)]))
                let dIdle = Double(max(0, ticks[Int(CPU_STATE_IDLE)]   - prev[Int(CPU_STATE_IDLE)]))
                let dNice = Double(max(0, ticks[Int(CPU_STATE_NICE)]   - prev[Int(CPU_STATE_NICE)]))
                let total = dUser + dSys + dIdle + dNice
                cores.append(CoreCPUInfo(id: i, usage: total > 0 ? min(100, (dUser + dSys + dNice) / total * 100) : 0))
            } else {
                cores.append(CoreCPUInfo(id: i, usage: 0))
            }
        }
        return (cores, currentTicks)
    }

    // MARK: - Disk

    public static func readDisk() -> (usage: Double, used: Double, total: Double) {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let total = attrs[.systemSize]     as? Int64,
              let free  = attrs[.systemFreeSize] as? Int64 else { return (0, 0, 0) }
        let totalGB = Double(total)        / 1_073_741_824
        let usedGB  = Double(total - free) / 1_073_741_824
        return (totalGB > 0 ? usedGB / totalGB * 100 : 0, usedGB, totalGB)
    }

    // MARK: - Network bandwidth

    public static func readNetworkBytes() -> (up: UInt64, down: UInt64) {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let head = ifaddrPtr else { return (0, 0) }
        defer { freeifaddrs(ifaddrPtr) }
        var upBytes: UInt64 = 0
        var downBytes: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let addr = cursor {
            let name = String(cString: addr.pointee.ifa_name)
            if !name.hasPrefix("lo"),
               let sa = addr.pointee.ifa_addr,
               sa.pointee.sa_family == UInt8(AF_LINK),
               let raw = addr.pointee.ifa_data {
                let data = raw.assumingMemoryBound(to: if_data.self)
                upBytes   += UInt64(data.pointee.ifi_obytes)
                downBytes += UInt64(data.pointee.ifi_ibytes)
            }
            cursor = addr.pointee.ifa_next
        }
        return (upBytes, downBytes)
    }
}
