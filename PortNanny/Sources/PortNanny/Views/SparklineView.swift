import PortNannyCore
import SwiftUI

/// A tiny line chart of one process's last samples. Observes the metrics
/// store on its own, so a new sample redraws this and nothing else.
struct SparklineView: View {
    enum Series {
        case cpu
        case memory
    }

    @ObservedObject var metrics: MetricsHistory
    let pid: Int
    let series: Series
    var tint: Color = .accentColor

    private var values: [Double] {
        series == .cpu ? metrics.cpu(for: pid) : metrics.memoryKB(for: pid)
    }

    var body: some View {
        // Reading `tick` is what subscribes this view to new samples.
        let _ = metrics.tick
        Sparkline(values: values, tint: tint)
            .accessibilityLabel(series == .cpu ? "CPU trend" : "memory trend")
    }
}

/// The drawing: a line over the samples with a soft fill beneath, scaled to
/// the series' own range so a quiet process still shows its shape.
struct Sparkline: View {
    let values: [Double]
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            let points = Self.points(for: values, in: geometry.size)
            ZStack {
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: geometry.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: geometry.size.height))
                        path.closeSubpath()
                    }
                    .fill(tint.opacity(0.15))
                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                } else {
                    Rectangle()
                        .fill(tint.opacity(0.08))
                }
            }
        }
    }

    /// Normalised to the series' own min and max, one point per sample,
    /// spread across the width; a flat series sits at mid height.
    static func points(for values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count > 1, let low = values.min(), let high = values.max() else { return [] }
        let span = max(high - low, 0.0001)
        let step = size.width / CGFloat(values.count - 1)
        let inset: CGFloat = 1.5
        return values.enumerated().map { index, value in
            let fraction = high == low ? 0.5 : (value - low) / span
            let y = size.height - inset - CGFloat(fraction) * (size.height - 2 * inset)
            return CGPoint(x: CGFloat(index) * step, y: y)
        }
    }
}
