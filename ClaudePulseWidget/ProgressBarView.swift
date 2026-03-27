import SwiftUI

struct ProgressBarView: View {
    let label: String
    let percentage: Double
    let color: Color
    var resetTime: String? = nil
    var subtitle: String? = nil

    private var barColor: Color {
        if percentage >= 90 { return .red }
        if percentage >= 75 { return .orange }
        return color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(percentage))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(barColor)
            }

            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(height: 8)

                // Fill
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [barColor.opacity(0.8), barColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * min(percentage / 100, 1))
                        .overlay(
                            // Glossy highlight
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [.white.opacity(0.4), .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: 4)
                                .offset(y: -1)
                                .clipShape(RoundedRectangle(cornerRadius: 4)),
                            alignment: .top
                        )
                }
                .frame(height: 8)
            }

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else if let resetTime {
                Text("Resets \(formattedReset(resetTime))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func formattedReset(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fmt.date(from: iso) else { return iso }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: Date())
    }
}
