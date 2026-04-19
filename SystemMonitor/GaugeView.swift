import SwiftUI

struct GaugeView: View {
    let value: Double
    let label: String
    let icon: String
    let subtitle: String
    let isSelected: Bool
    let onTap: () -> Void

    private var fraction: Double { min(max(value / 100, 0), 1) }

    private var gaugeColor: Color {
        switch value {
        case ..<50: return .green
        case ..<80: return .yellow
        default:    return .red
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if isSelected {
                    Circle()
                        .stroke(gaugeColor.opacity(0.35), lineWidth: 2)
                        .frame(width: 72, height: 72)
                }
                Circle()
                    .stroke(gaugeColor.opacity(0.2),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(gaugeColor,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: fraction)
                VStack(spacing: 1) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? gaugeColor : .secondary)
                    Text("\(Int(value))%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                }
            }
            .frame(width: 64, height: 64)

            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Text(subtitle)
                    .font(.system(size: 9, design: .rounded).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
