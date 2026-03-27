import SwiftUI
import ClaudePulseCore

struct SparklineView: View {
    let snapshots: [UsageSnapshot]
    let keyPath: KeyPath<UsageSnapshot, Double?>
    let color: Color
    var height: CGFloat = 30

    private var values: [Double] {
        snapshots.compactMap { $0[keyPath: keyPath] }
    }

    var body: some View {
        if values.count >= 2 {
            let minVal = max((values.min() ?? 0) - 5, 0)
            let maxVal = min((values.max() ?? 100) + 5, 100)
            let range = max(maxVal - minVal, 1)

            Canvas { context, size in
                let step = size.width / CGFloat(values.count - 1)
                var path = Path()
                for (i, val) in values.enumerated() {
                    let x = CGFloat(i) * step
                    let y = size.height * (1 - CGFloat((val - minVal) / range))
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(path, with: .color(color), lineWidth: 1.5)

                // Fill under the line
                var fillPath = path
                fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
                fillPath.addLine(to: CGPoint(x: 0, y: size.height))
                fillPath.closeSubpath()
                context.fill(fillPath, with: .linearGradient(
                    Gradient(colors: [color.opacity(0.2), color.opacity(0.02)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                ))
            }
            .frame(height: height)
        } else {
            Text("Collecting data...")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(height: height)
        }
    }
}
