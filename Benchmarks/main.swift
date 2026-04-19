import Foundation
@_exported import SystemMonitorCore

// MARK: - Helpers

func time(_ label: String, iterations: Int = 10, block: () -> Void) {
    // Warm up
    block()

    var times = [Double]()
    for _ in 0..<iterations {
        let t = Date()
        block()
        times.append(Date().timeIntervalSince(t) * 1000)
    }
    let avg = times.reduce(0, +) / Double(times.count)
    let mn  = times.min()!
    let mx  = times.max()!
    let padded = label.padding(toLength: 38, withPad: " ", startingAt: 0)
    print(String(format: "  %@  avg %6.2f ms  min %6.2f ms  max %6.2f ms", padded, avg, mn, mx))
}

func assert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if !condition {
        print("  FAIL [\(file):\(line)] \(message)")
        exit(1)
    }
}

func pass(_ label: String) {
    print("  PASS  \(label)")
}

// MARK: - Correctness checks

func runCorrectnessChecks() {
    print("\n=== Correctness ===\n")

    // Memory
    let mem = SystemStats.readMemory()
    assert(mem.total > 0,             "readMemory: total > 0")
    assert(mem.used  >= 0,            "readMemory: used >= 0")
    assert(mem.used  <= mem.total + 0.5, "readMemory: used <= total")
    assert(mem.usage >= 0 && mem.usage <= 100, "readMemory: usage in [0,100]")
    let physical = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    assert(abs(mem.total - physical) < 0.01, "readMemory: total matches physical RAM")
    pass("readMemory — \(String(format: "%.1f", mem.used)) / \(String(format: "%.0f", mem.total)) GB used (\(String(format: "%.0f", mem.usage))%)")

    // Disk
    let disk = SystemStats.readDisk()
    assert(disk.total > 0,             "readDisk: total > 0")
    assert(disk.used  > 0,             "readDisk: used > 0")
    assert(disk.used  <= disk.total,   "readDisk: used <= total")
    assert(disk.usage >= 0 && disk.usage <= 100, "readDisk: usage in [0,100]")
    pass("readDisk — \(String(format: "%.0f", disk.used)) / \(String(format: "%.0f", disk.total)) GB used (\(String(format: "%.0f", disk.usage))%)")

    // Load average
    let load = SystemStats.readLoadAvg()
    assert(load.one >= 0 && load.five >= 0 && load.fifteen >= 0, "readLoadAvg: all non-negative")
    pass("readLoadAvg — 1m: \(String(format: "%.2f", load.one))  5m: \(String(format: "%.2f", load.five))  15m: \(String(format: "%.2f", load.fifteen))")

    // CPU (single sample — no delta)
    let cpu1 = SystemStats.readCPU(previous: nil)
    assert(cpu1.usage >= 0 && cpu1.usage <= 100, "readCPU(nil): usage in [0,100]")
    Thread.sleep(forTimeInterval: 0.1)
    let cpu2 = SystemStats.readCPU(previous: cpu1.info)
    assert(cpu2.usage >= 0 && cpu2.usage <= 100, "readCPU(delta): usage in [0,100]")
    pass("readCPU — \(String(format: "%.1f", cpu2.usage))%")

    // Per-core CPU
    let (cores1, ticks1) = SystemStats.readPerCoreCPU(previous: [])
    assert(cores1.count == ProcessInfo.processInfo.processorCount, "readPerCoreCPU: count == processorCount")
    assert(cores1.enumerated().allSatisfy { $0.element.id == $0.offset }, "readPerCoreCPU: sequential IDs")
    Thread.sleep(forTimeInterval: 0.2)
    let (cores2, _) = SystemStats.readPerCoreCPU(previous: ticks1)
    assert(cores2.allSatisfy { $0.usage >= 0 && $0.usage <= 100 }, "readPerCoreCPU: all in [0,100]")
    let coreStr = cores2.map { c in "C\(c.id):\(Int(c.usage))%" }.joined(separator: "  ")
    pass("readPerCoreCPU — \(coreStr)")

    // Process stats — mem sorted, CPU needs two samples
    let w1 = Date().timeIntervalSinceReferenceDate
    let (mem1, cpu_procs1, times1) = SystemStats.readProcessStats(prevTimes: [:], prevWall: 0, wallNow: w1)
    assert(!mem1.isEmpty, "readProcessStats: non-empty mem results")
    let memSorted = zip(mem1, mem1.dropFirst()).allSatisfy { $0.rssBytes >= $1.rssBytes }
    assert(memSorted, "readProcessStats: mem results sorted descending")
    assert(cpu_procs1.isEmpty, "readProcessStats: no CPU without prev sample")
    pass("readProcessStats (cold) — \(mem1.count) mem procs, top: \(mem1.first.map { "\($0.name) \(String(format: "%.0f", $0.rssMB))MB" } ?? "none")")

    Thread.sleep(forTimeInterval: 1.0)
    let w2 = Date().timeIntervalSinceReferenceDate
    let (_, cpu_procs2, _) = SystemStats.readProcessStats(prevTimes: times1, prevWall: w1, wallNow: w2)
    assert(!cpu_procs2.isEmpty, "readProcessStats: CPU results after second sample")
    let cpuSorted = zip(cpu_procs2, cpu_procs2.dropFirst()).allSatisfy { $0.cpuPercent >= $1.cpuPercent }
    assert(cpuSorted, "readProcessStats: CPU results sorted descending")
    pass("readProcessStats (delta) — \(cpu_procs2.count) CPU procs, top: \(cpu_procs2.first.map { "\($0.name) \(String(format: "%.1f", $0.cpuPercent))%" } ?? "none")")
}

// MARK: - Sync benchmarks

func runSyncBenchmarks() {
    print("\n=== Sync Benchmarks (10 iterations each) ===\n")

    time("readMemory()") {
        _ = SystemStats.readMemory()
    }

    time("readDisk()") {
        _ = SystemStats.readDisk()
    }

    time("readLoadAvg()") {
        _ = SystemStats.readLoadAvg()
    }

    time("readCPU(previous: nil)") {
        _ = SystemStats.readCPU(previous: nil)
    }

    var cpuInfo = SystemStats.readCPU(previous: nil).info
    time("readCPU(previous: info)") {
        let r = SystemStats.readCPU(previous: cpuInfo)
        cpuInfo = r.info
    }

    var coreTicks: [[integer_t]] = []
    (_, coreTicks) = SystemStats.readPerCoreCPU(previous: [])
    time("readPerCoreCPU(warmed)") {
        let r = SystemStats.readPerCoreCPU(previous: coreTicks)
        coreTicks = r.ticks
    }

    // Cold (no prev times — skips CPU delta, just collects mem+names)
    let wall = Date().timeIntervalSinceReferenceDate
    time("readProcessStats(cold, no delta)") {
        _ = SystemStats.readProcessStats(prevTimes: [:], prevWall: 0, wallNow: wall)
    }

    // Warm — full pass with CPU delta
    let w1 = Date().timeIntervalSinceReferenceDate
    let (_, _, prevTimes) = SystemStats.readProcessStats(prevTimes: [:], prevWall: 0, wallNow: w1)
    Thread.sleep(forTimeInterval: 0.5)
    time("readProcessStats(warm, with CPU delta)") {
        let w = Date().timeIntervalSinceReferenceDate
        _ = SystemStats.readProcessStats(prevTimes: prevTimes, prevWall: w1, wallNow: w)
    }
}

// MARK: - Async operation timings

func timeAsync(_ label: String, setup: ((SystemStats) -> Void)? = nil, trigger: @escaping (SystemStats) -> Void, done: @escaping (SystemStats) -> Bool) {
    let stats = SystemStats()
    setup?(stats)

    let sema  = DispatchSemaphore(value: 0)
    let start = Date()
    var elapsed = 0.0

    trigger(stats)

    // Poll on a background thread so NSMetadataQuery's main-thread run loop keeps spinning
    DispatchQueue.global().async {
        while !done(stats) {
            Thread.sleep(forTimeInterval: 0.02)
        }
        elapsed = Date().timeIntervalSince(start)
        sema.signal()
    }

    // Run main run loop to service NSMetadataQuery callbacks
    let deadline = Date().addingTimeInterval(15)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        if sema.wait(timeout: .now()) == .success { break }
    }

    print(String(format: "  %@  %.2f s", label.padding(toLength: 38, withPad: " ", startingAt: 0), elapsed))
}

func runAsyncBenchmarks() {
    print("\n=== Async Operation Timings ===\n")

    timeAsync(
        "triggerFastCPUSample()",
        trigger: { $0.triggerFastCPUSample() },
        done:    { !$0.topCPUProcesses.isEmpty }
    )

    timeAsync(
        "triggerLargeFilesScan()",
        trigger: { $0.triggerLargeFilesScan() },
        done:    { _ in
            // NSMetadataQuery fires even with 0 results; we detect by
            // checking that largeFiles was set (possibly empty) after query fires.
            // Use a flag via a short sleep — query typically finishes in < 1s.
            Thread.sleep(forTimeInterval: 0.1)
            return true
        }
    )

    // More accurate large files timing using DispatchSemaphore + Combine
    print("")
    print("  (re-running large files scan with result count...)")
    let stats2 = SystemStats()
    let sema2  = DispatchSemaphore(value: 0)
    let start2 = Date()
    var elapsed2 = 0.0
    var resultCount = 0

    let c = stats2.$largeFiles
        .dropFirst()
        .first()
        .sink { files in
            elapsed2 = Date().timeIntervalSince(start2)
            resultCount = files.count
            sema2.signal()
        }

    stats2.triggerLargeFilesScan()

    let deadline2 = Date().addingTimeInterval(15)
    while Date() < deadline2 {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        if sema2.wait(timeout: .now()) == .success { break }
    }
    _ = c

    print(String(format: "  %@  %.2f s  (%d files >50 MB found)", "triggerLargeFilesScan() (accurate)".padding(toLength: 38, withPad: " ", startingAt: 0), elapsed2, resultCount))
}

// MARK: - Run

runCorrectnessChecks()
runSyncBenchmarks()
runAsyncBenchmarks()
print("\nDone.")
