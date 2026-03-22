import SwiftUI

struct GaugeView: View {
    let value: Double
    let label: String
    let icon: String
    let detail: String

    private var fraction: Double { min(max(value / 100, 0), 1) }

    private var gaugeColor: Color {
        switch value {
        case ..<50: return .green
        case ..<80: return .yellow
        default: return .red
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Background track
                Circle()
                    .stroke(
                        gaugeColor.opacity(0.2),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )

                // Filled arc
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        gaugeColor,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: fraction)

                // Center icon + percentage
                VStack(spacing: 1) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text("\(Int(value))%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                }
            }
            .frame(width: 64, height: 64)

            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .help(detail)
    }
}
