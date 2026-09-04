import Cocoa

struct DayTimelineModel: Equatable {
    struct Segment: Equatable {
        let startMinute: Double
        let endMinute: Double
        let isLive: Bool
    }

    /// Visible range of the track, in minutes after midnight.
    let startMinute: Int
    let endMinute: Int
    let segments: [Segment]
}

/// One day as a horizontal track: sessions are filled spans, the space between them is a break.
///
/// Hover indices: `>= 0` is a segment, `-(k + 1)` is the gap after segment `k`.
final class DayTimelineView: HoverChartView {
    var model: DayTimelineModel? {
        didSet {
            let count = model?.segments.count ?? 0
            revalidateHover { index in
                if let after = DayTimelineView.gapSegment(index) {
                    return after + 1 < count
                }
                return index < count
            }
            needsDisplay = true
        }
    }

    private let trackHeight: CGFloat = 18
    private let tickHeight: CGFloat = 4
    private let hitSlop: CGFloat = 2
    private let minimumLabelSpacing: CGFloat = 34

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var chartHeight: CGFloat { 40 }

    static func gapIndex(after segment: Int) -> Int { -(segment + 1) }

    /// The segment a gap index follows, or nil for a segment index.
    static func gapSegment(_ index: Int) -> Int? { index < 0 ? -index - 1 : nil }

    // MARK: - Geometry

    private var trackRect: NSRect {
        NSRect(x: 0, y: bounds.height - trackHeight - 2, width: bounds.width, height: trackHeight)
    }

    private var pointsPerMinute: CGFloat {
        guard let model = model, model.endMinute > model.startMinute else { return 0 }
        return trackRect.width / CGFloat(model.endMinute - model.startMinute)
    }

    private func x(atMinute minute: Double) -> CGFloat {
        guard let model = model else { return 0 }
        return trackRect.minX + CGFloat(minute - Double(model.startMinute)) * pointsPerMinute
    }

    override func index(at point: NSPoint) -> Int? {
        guard let model = model, trackRect.insetBy(dx: 0, dy: -4).contains(point) else { return nil }
        for (index, segment) in model.segments.enumerated() {
            let start = x(atMinute: segment.startMinute) - hitSlop
            let end = max(x(atMinute: segment.endMinute), x(atMinute: segment.startMinute) + ChartStyle.minBarWidth) + hitSlop
            if point.x >= start && point.x <= end {
                return index
            }
            if point.x < start {
                return index > 0 ? DayTimelineView.gapIndex(after: index - 1) : nil
            }
        }
        return nil
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let model = model else { return }
        let track = trackRect
        let scale = window?.backingScaleFactor ?? 2

        ChartStyle.track.setFill()
        NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()

        if let hovered = hoveredIndex, let after = DayTimelineView.gapSegment(hovered), after + 1 < model.segments.count {
            let gapStart = x(atMinute: model.segments[after].endMinute)
            let gapEnd = x(atMinute: model.segments[after + 1].startMinute)
            let gap = NSRect(x: gapStart, y: track.minY, width: max(0, gapEnd - gapStart), height: track.height).insetBy(dx: 1, dy: 3)
            if gap.width > 0 {
                ChartStyle.columnHighlight.setFill()
                NSBezierPath(roundedRect: gap, xRadius: 2, yRadius: 2).fill()
            }
        }

        drawHourLabels(model: model, track: track, scale: scale)

        for (index, segment) in model.segments.enumerated() {
            let start = x(atMinute: segment.startMinute)
            let end = max(x(atMinute: segment.endMinute), start + ChartStyle.minBarWidth)
            let rect = NSRect(x: start, y: track.minY, width: end - start, height: track.height)
            let isHovered = index == hoveredIndex
            let color: NSColor
            if segment.isLive {
                color = isHovered ? ChartStyle.hoveredLiveSegment : ChartStyle.liveSegment
            } else {
                color = isHovered ? ChartStyle.accent : ChartStyle.segment
            }
            color.setFill()
            NSBezierPath.bar(in: rect, radius: 2, roundedEdge: .all).fill()

            if segment.isLive {
                ChartStyle.accent.setFill()
                NSRect(x: end - 2, y: track.minY, width: 2, height: track.height).fill()
            }
        }
    }

    private func drawHourLabels(model: DayTimelineModel, track: NSRect, scale: CGFloat) {
        let perMinute = pointsPerMinute
        guard perMinute > 0 else { return }
        let step = [1, 2, 3, 4, 6].first { CGFloat($0 * 60) * perMinute >= minimumLabelSpacing } ?? 6
        let firstHour = (model.startMinute + 59) / 60
        let lastHour = model.endMinute / 60
        guard firstHour <= lastHour else { return }

        for hour in firstHour...lastHour where hour % step == 0 {
            let x = ChartStyle.snapped(self.x(atMinute: Double(hour * 60)), scale: scale)
            ChartStyle.axis.setFill()
            NSRect(x: x, y: track.minY - tickHeight - 1, width: 1 / scale, height: tickHeight).fill()
            let alignment: NSTextAlignment = hour * 60 <= model.startMinute ? .left : (hour * 60 >= model.endMinute ? .right : .center)
            ChartText.draw("\(hour)", at: NSPoint(x: x, y: 0),
                           alignment: alignment, font: ChartStyle.axisLabelFont, color: ChartStyle.axisText)
        }
    }
}
