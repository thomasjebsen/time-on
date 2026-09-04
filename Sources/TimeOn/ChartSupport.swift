import Cocoa

// Shared drawing vocabulary for the Insights charts.

/// Colors are computed properties so they resolve against the current appearance inside `draw(_:)`
/// and never go stale when the system switches between light and dark.
enum ChartStyle {
    static let barGap: CGFloat = 2
    static let minBarWidth: CGFloat = 2
    static let maxBarWidth: CGFloat = 24
    static let barCornerRadius: CGFloat = 4
    static let axisLabelFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

    static var accent: NSColor { .controlAccentColor }
    static var mutedBar: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.4) }
    static var hoveredBar: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.75) }
    static var segment: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.85) }
    static var liveSegment: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.5) }
    static var hoveredLiveSegment: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.7) }
    static var columnHighlight: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.12) }
    static var track: NSColor { .quaternaryLabelColor }
    static var axis: NSColor { .separatorColor }
    static var referenceLine: NSColor { .tertiaryLabelColor }
    static var axisText: NSColor { .tertiaryLabelColor }
    static var secondaryText: NSColor { .secondaryLabelColor }

    /// Rounds a coordinate to the device pixel grid so hairlines and bar edges stay crisp.
    static func snapped(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }
}

extension NSBezierPath {
    enum RoundedEdge {
        /// Rounded at the data end only (the top of a column), square at the baseline.
        case top
        /// Rounded at both ends (a span on a timeline).
        case all
    }

    /// A bar path whose corner radius is clamped so tiny bars never invert.
    static func bar(in rect: NSRect, radius: CGFloat, roundedEdge: RoundedEdge) -> NSBezierPath {
        let r = min(radius, rect.width / 2, rect.height / 2)
        guard r > 0 else { return NSBezierPath(rect: rect) }
        switch roundedEdge {
        case .all:
            return NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
        case .top:
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX, y: rect.minY))
            path.line(to: NSPoint(x: rect.minX, y: rect.maxY - r))
            path.appendArc(withCenter: NSPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                           startAngle: 180, endAngle: 90, clockwise: true)
            path.line(to: NSPoint(x: rect.maxX - r, y: rect.maxY))
            path.appendArc(withCenter: NSPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                           startAngle: 90, endAngle: 0, clockwise: true)
            path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
            path.close()
            return path
        }
    }
}

enum ChartText {
    /// Draws a single line of text with its bottom edge at `origin.y`, aligned horizontally around `origin.x`.
    static func draw(_ text: String, at origin: NSPoint, alignment: NSTextAlignment, font: NSFont, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        var point = origin
        switch alignment {
        case .center: point.x -= size.width / 2
        case .right: point.x -= size.width
        default: break
        }
        (text as NSString).draw(at: point, withAttributes: attributes)
    }

    static func height(of font: NSFont) -> CGFloat {
        ("0" as NSString).size(withAttributes: [.font: font]).height
    }
}

/// Base class for the hand-drawn charts: fixed height, hover tracking with index callbacks,
/// click-to-select, and a redraw whenever the effective appearance changes.
class HoverChartView: NSView {
    var onHover: ((Int?) -> Void)?
    var onSelect: ((Int) -> Void)?

    private(set) var hoveredIndex: Int? {
        didSet {
            guard hoveredIndex != oldValue else { return }
            needsDisplay = true
            onHover?(hoveredIndex)
        }
    }
    private var trackingArea: NSTrackingArea?

    /// Subclasses report their fixed height here.
    var chartHeight: CGFloat { 100 }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: chartHeight)
    }

    /// Maps a point in view coordinates to the hover index the subclass understands.
    func index(at point: NSPoint) -> Int? { nil }

    func clearHover() {
        hoveredIndex = nil
    }

    /// Keeps the current hover when it still points at something in the new model, so a periodic
    /// refresh does not wipe the readout from under the pointer; clears it otherwise.
    func revalidateHover(isValid: (Int) -> Bool) {
        if let index = hoveredIndex, !isValid(index) {
            hoveredIndex = nil
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        hoveredIndex = index(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
    }

    override func mouseUp(with event: NSEvent) {
        if let index = index(at: convert(event.locationInWindow, from: nil)) {
            onSelect?(index)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
