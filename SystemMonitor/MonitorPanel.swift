import SwiftUI

struct MonitorPanel: View {
    @ObservedObject var stats: SystemStats

    var body: some View {
        VStack(spacing: 12) {
            // Header
            Text("System Monitor")
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.secondary)

            Divider()

            // Circular gauges row
            HStack(spacing: 24) {
                GaugeView(
                    value: stats.cpuUsage,
                    label: "CPU",
                    icon: "cpu",
                    detail: "\(Int(stats.cpuUsage))%"
                )
                GaugeView(
                    value: stats.memoryUsage,
                    label: "MEM",
                    icon: "memorychip",
                    detail: String(format: "%.1f / %.0f GB", stats.memoryUsed, stats.memoryTotal)
                )
                GaugeView(
                    value: stats.diskUsage,
                    label: "DISK",
                    icon: "internaldrive",
                    detail: String(format: "%.0f / %.0f GB", stats.diskUsed, stats.diskTotal)
                )
            }
            .padding(.top, 8)

            Divider()

            // Summary rows
            StatRow(label: "CPU Usage", value: "\(Int(stats.cpuUsage))%")
            StatRow(label: "Memory", value: String(format: "%.1f of %.0f GB", stats.memoryUsed, stats.memoryTotal))
            StatRow(label: "Disk", value: String(format: "%.0f of %.0f GB", stats.diskUsed, stats.diskTotal))

            Divider()

            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(.body, design: .rounded))
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .rounded).monospacedDigit())
        }
    }
}
