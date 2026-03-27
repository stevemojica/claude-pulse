import SwiftUI
import Charts
import ClaudePulseCore

struct HistoryChartData: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
    let window: String
}

struct HistoryView: View {
    let snapshots: [UsageSnapshot]

    private var chartData: [HistoryChartData] {
        snapshots.flatMap { snap -> [HistoryChartData] in
            var items: [HistoryChartData] = []
            if let v = snap.fiveHourPct { items.append(.init(timestamp: snap.timestamp, value: v, window: "5-hour")) }
            if let v = snap.sevenDayPct { items.append(.init(timestamp: snap.timestamp, value: v, window: "7-day")) }
            if let v = snap.sonnetPct { items.append(.init(timestamp: snap.timestamp, value: v, window: "Sonnet")) }
            return items
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Usage History")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if chartData.count >= 2 {
                Chart(chartData) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Usage %", point.value)
                    )
                    .foregroundStyle(by: .value("Window", point.window))
                    .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2]))
                        AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%").font(.system(size: 9)) }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel(format: .dateTime.hour().minute())
                            .font(.system(size: 9))
                    }
                }
                .chartLegend(position: .bottom, spacing: 4)
                .frame(height: 120)
            } else {
                Text("Need more data points for chart")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
