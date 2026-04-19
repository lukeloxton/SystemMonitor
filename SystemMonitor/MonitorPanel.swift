import SwiftUI
import Darwin
import SystemMonitorCore

enum PanelSection: Equatable { case cpu, mem, disk }

final class PanelState: ObservableObject {
    @Published var expanded: PanelSection? = nil
}

// MARK: - Dials (lives in its own NSMenuItem — never resizes, never moves)

struct DialsView: View {
    @ObservedObject var stats: SystemStats
    @ObservedObject var state: PanelState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                GaugeView(
                    value: stats.cpuUsage, label: "CPU", icon: "cpu",
                    subtitle: "",
                    isSelected: state.expanded == .cpu,
                    onTap: {
                        let opening = state.expanded != .cpu
                        state.expanded = opening ? .cpu : nil
                        if opening { stats.triggerFastCPUSample() }
                    }
                )
                GaugeView(
                    value: stats.memoryUsage, label: "RAM", icon: "memorychip",
                    subtitle: String(format: "%.1f / %.0f GB", stats.memoryUsed, stats.memoryTotal),
                    isSelected: state.expanded == .mem,
                    onTap: { state.expanded = state.expanded == .mem ? nil : .mem }
                )
                GaugeView(
                    value: stats.diskUsage, label: "DISK", icon: "internaldrive",
                    subtitle: String(format: "%.0f / %.0f GB", stats.diskUsed, stats.diskTotal),
                    isSelected: state.expanded == .disk,
                    onTap: {
                        let opening = state.expanded != .disk
                        state.expanded = opening ? .disk : nil
                        if opening { stats.triggerLargeFilesScan() }
                    }
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            NetworkRow(upBPS: stats.netUpBPS, downBPS: stats.netDownBPS)
        }
    }
}

// MARK: - Detail (lives in a separate NSMenuItem — starts at height 0, grows on expand)

struct DetailView: View {
    @ObservedObject var stats: SystemStats
    @ObservedObject var state: PanelState

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            detailContent
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var detailContent: some View {
        switch state.expanded {
        case .cpu:
            if stats.perCoreCPU.isEmpty {
                StatRow(label: "Sampling cores…", value: "")
            } else {
                VStack(spacing: 8) {
                    CoreGrid(cores: stats.perCoreCPU)
                    let l = stats.loadAvg
                    StatRow(label: "Load avg (1m 5m 15m)",
                            value: String(format: "%.2f  %.2f  %.2f", l.one, l.five, l.fifteen))
                    if !stats.topCPUProcesses.isEmpty {
                        Divider()
                        ForEach(stats.topCPUProcesses) { p in
                            ProcessRow(label: p.name,
                                       value: String(format: "%.1f%%", p.cpuPercent),
                                       pid: p.id)
                        }
                    }
                }
            }
        case .mem:
            VStack(spacing: 8) {
                ForEach(stats.topMemProcesses) { p in
                    ProcessRow(
                        label: p.name,
                        value: p.rssMB >= 1024
                            ? String(format: "%.1f GB", p.rssMB / 1024)
                            : String(format: "%.0f MB", p.rssMB),
                        pid: p.id
                    )
                }
            }
        case .disk:
            VStack(spacing: 8) {
                if stats.largeFiles.isEmpty {
                    StatRow(label: "Scanning…", value: "")
                } else {
                    ForEach(stats.largeFiles) { f in
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [URL(fileURLWithPath: f.path)]
                            )
                        } label: {
                            StatRow(
                                label: f.name,
                                value: f.sizeMB >= 1024
                                    ? String(format: "%.1f GB", f.sizeMB / 1024)
                                    : String(format: "%.0f MB", f.sizeMB)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Network row

struct NetworkRow: View {
    let upBPS:   Double
    let downBPS: Double

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("↑ \(bpsLabel(upBPS))")
                .font(.system(size: 10, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Text("↓ \(bpsLabel(downBPS))")
                .font(.system(size: 10, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }

    private func bpsLabel(_ bps: Double) -> String {
        if bps < 1_024     { return String(format: "%.0f B/s",  bps) }
        if bps < 1_048_576 { return String(format: "%.1f KB/s", bps / 1_024) }
        return               String(format: "%.1f MB/s", bps / 1_048_576)
    }
}

// MARK: - Per-core bar grid

struct CoreGrid: View {
    let cores: [CoreCPUInfo]
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 5) {
            ForEach(cores) { core in
                HStack(spacing: 5) {
                    Text("C\(core.id)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(coreColor(core.usage))
                                .frame(width: geo.size.width * core.usage / 100)
                        }
                    }
                    .frame(height: 8)
                    Text(String(format: "%2.0f%%", core.usage))
                        .font(.system(size: 9, design: .monospaced).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 26, alignment: .trailing)
                }
            }
        }
    }

    private func coreColor(_ v: Double) -> Color {
        v < 50 ? .green : v < 80 ? .yellow : .red
    }
}

// MARK: - Shared rows

struct StatRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Text(value).font(.system(.body, design: .rounded).monospacedDigit())
        }
    }
}

struct ProcessRow: View {
    let label: String
    let value: String
    let pid:   Int32

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Text(value).font(.system(.body, design: .rounded).monospacedDigit())
            Button {
                _ = Darwin.kill(pid, SIGTERM)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red.opacity(0.55))
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
        }
    }
}
