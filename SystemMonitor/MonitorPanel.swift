import SwiftUI

struct GaugePanel: View {
    @ObservedObject var stats: SystemStats

    var body: some View {
        VStack(spacing: 12) {
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

            Divider()

            StatRow(label: "CPU Usage", value: "\(Int(stats.cpuUsage))%")
            StatRow(label: "Memory", value: String(format: "%.1f of %.0f GB", stats.memoryUsed, stats.memoryTotal))
            StatRow(label: "Disk", value: String(format: "%.0f of %.0f GB", stats.diskUsed, stats.diskTotal))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
