import Cocoa

struct BarChartModel: Equatable {
    struct Bar: Equatable {
        let value: Double
        let hasData: Bool
        /// Drawn in the full accent color; everything else is muted.
        let emphasized: Bool
    }

    struct AxisLabel: Equatable {
        /// In slot units: 0 is the left edge of the first bar, `bars.count` the right edge of the last.
        let position: CGFloat
        let text: String
    }

    struct ReferenceLine: Equatable {
        let value: Double
        let label: String
    }

    let bars: [Bar]
    let axisLabels: [AxisLabel]
    let referenceLine: ReferenceLine?
}

/// A single-hue column chart with a hairline baseline, an optional labelled reference line,
/// hover highlighting, and click-to-select. Used for both the 28-day and the 24-hour views.
final class BarChartView: HoverChartView {
    var model: BarChartModel? {
        didSet {
            let count = model?.bars.count ?? 0
            revalidateHover { $0 >= 0 && $0 < count }
            needsDisplay = true
        }
    }

    private let height: CGFloat
    private let axisLabelHeight: CGFloat = 16
    private let topPadding: CGFloat = 4
    private let referenceLabelWidth: CGFloat = 64

    init(height: CGFloat) {
        self.height = height
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var chartHeight: CGFloat { height }

    // MARK: - Geometry

    private var plotRect: NSRect {
        var rect = bounds
        rect.origin.y += axisLabelHeight
        rect.size.height -= axisLabelHeight + topPadding
        if model?.referenceLine != nil {
            rect.size.width -= referenceLabelWidth
        }
        return rect
    }

    private var slotWidth: CGFloat {
        guard let count = model?.bars.count, count > 0 else { return 0 }
        return plotRect.width / CGFloat(count)
    }

    override func index(at point: NSPoint) -> Int? {
        guard let model = model, !model.bars.isEmpty, bounds.contains(point) else { return nil }
        let plot = plotRect
        guard point.x >= plot.minX, point.x < plot.maxX, slotWidth > 0 else { return nil }
        let index = Int((point.x - plot.minX) / slotWidth)
        return (0..<model.bars.count).contains(index) ? index : nil
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let model = model, !model.bars.isEmpty else { return }
        let plot = plotRect
        let scale = window?.backingScaleFactor ?? 2
        let slot = slotWidth
        let barWidth = min(ChartStyle.maxBarWidth, max(ChartStyle.minBarWidth, slot - ChartStyle.barGap))
        let maxValue = max(model.bars.map { $0.value }.max() ?? 0, model.referenceLine?.value ?? 0, 1)
        let baseline = ChartStyle.snapped(plot.minY, scale: scale)

        if let hovered = hoveredIndex {
            let column = NSRect(x: plot.minX + slot * CGFloat(hovered), y: plot.minY, width: slot, height: plot.height)
            ChartStyle.columnHighlight.setFill()
            NSBezierPath(roundedRect: column, xRadius: 3, yRadius: 3).fill()
        }

        for (index, bar) in model.bars.enumerated() where bar.hasData && bar.value > 0 {
            let x = ChartStyle.snapped(plot.minX + slot * CGFloat(index) + (slot - barWidth) / 2, scale: scale)
            let barHeight = max(1, plot.height * CGFloat(bar.value / maxValue))
            let color: NSColor
            if bar.emphasized {
                color = ChartStyle.accent
            } else if index == hoveredIndex {
                color = ChartStyle.hoveredBar
            } else {
                color = ChartStyle.mutedBar
            }
            color.setFill()
            let rect = NSRect(x: x, y: baseline, width: barWidth, height: barHeight)
            NSBezierPath.bar(in: rect, radius: ChartStyle.barCornerRadius, roundedEdge: .top).fill()
        }

        ChartStyle.axis.setFill()
        NSRect(x: plot.minX, y: baseline - 1 / scale, width: plot.width, height: 1 / scale).fill()

        if let reference = model.referenceLine {
            let y = ChartStyle.snapped(plot.minY + plot.height * CGFloat(reference.value / maxValue), scale: scale)
            ChartStyle.referenceLine.setFill()
            NSRect(x: plot.minX, y: y, width: plot.width, height: 1 / scale).fill()
            let textHeight = ChartText.height(of: ChartStyle.axisLabelFont)
            ChartText.draw(reference.label, at: NSPoint(x: plot.maxX + 6, y: y - textHeight / 2),
                           alignment: .left, font: ChartStyle.axisLabelFont, color: ChartStyle.secondaryText)
        }

        let count = CGFloat(model.bars.count)
        for label in model.axisLabels {
            let x = plot.minX + slot * label.position
            let alignment: NSTextAlignment = label.position <= 0 ? .left : (label.position >= count ? .right : .center)
            ChartText.draw(label.text, at: NSPoint(x: x, y: 1),
                           alignment: alignment, font: ChartStyle.axisLabelFont, color: ChartStyle.axisText)
        }
    }
}
