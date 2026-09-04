import Cocoa

// MARK: - Content

/// What a badge says. Built by the callers (StatusBarController, Settings "Test" buttons).
struct BadgeContent {
    let title: String
    let subtitle: String
    let symbolName: String
    let accent: NSColor

    static func breakReminder(activeFor formatted: String) -> BadgeContent {
        BadgeContent(
            title: "Time for a break",
            subtitle: "Active for \(formatted)",
            symbolName: "figure.walk",
            accent: NSColor(hex: Preferences.pomodoroBreakColor) ?? .systemTeal
        )
    }

    static func pomodoro(next phase: SessionManager.PomodoroPhase) -> BadgeContent {
        switch phase {
        case .work:
            return BadgeContent(
                title: "Back to work",
                subtitle: "\(Preferences.pomodoroWorkMinutes) min focus",
                symbolName: "timer",
                accent: NSColor(hex: Preferences.pomodoroWorkColor) ?? .systemOrange
            )
        case .shortBreak:
            return BadgeContent(
                title: "Break time!",
                subtitle: "\(Preferences.pomodoroShortBreakMinutes) min short break",
                symbolName: "cup.and.saucer.fill",
                accent: NSColor(hex: Preferences.pomodoroBreakColor) ?? .systemTeal
            )
        case .longBreak:
            return BadgeContent(
                title: "Break time!",
                subtitle: "\(Preferences.pomodoroLongBreakMinutes) min long break",
                symbolName: "cup.and.saucer.fill",
                accent: NSColor(hex: Preferences.pomodoroBreakColor) ?? .systemTeal
            )
        }
    }
}

// MARK: - Geometry

/// Pure positioning math, kept free of AppKit state so it can be unit-tested.
/// Mirrored in Tests/run_tests.swift — keep the two copies in sync.
enum BadgeGeometry {
    static let gapBelowMenuBar: CGFloat = 6
    static let screenInset: CGFloat = 8

    /// Centres `size` under `anchor` (the status button in screen coordinates), or puts it
    /// in the top-right corner when there is no anchor, and clamps the result inside
    /// `visibleFrame` so the card never hangs off-screen (e.g. when the menu bar is hidden).
    static func cardFrame(size: CGSize, anchor: CGRect?, visibleFrame vf: CGRect) -> CGRect {
        var origin: CGPoint
        if let a = anchor {
            origin = CGPoint(x: a.midX - size.width / 2, y: a.minY - gapBelowMenuBar - size.height)
        } else {
            origin = CGPoint(x: vf.maxX - screenInset - size.width, y: vf.maxY - gapBelowMenuBar - size.height)
        }
        origin.x = min(max(origin.x, vf.minX + screenInset), vf.maxX - screenInset - size.width)
        origin.y = min(max(origin.y, vf.minY + screenInset), vf.maxY - gapBelowMenuBar - size.height)
        return CGRect(origin: origin, size: size)
    }
}

// MARK: - Controller

/// A small card that drops down from the menu-bar icon. It never activates the app or
/// takes keyboard focus, shows over fullscreen apps and on every Space, and stays until
/// the user clicks it (or the status item), or a newer badge replaces it in place.
final class BadgePanelController {
    private enum Layout {
        static let size = CGSize(width: 220, height: 110)
        static let cornerRadius: CGFloat = 12
        static let horizontalPadding: CGFloat = 14
        static let iconPointSize: CGFloat = 30
    }

    private let panel: BadgePanel
    private let contentView = BadgeContentView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    /// Incremented on every show(); a fade-out completion only hides the panel if no
    /// newer show() happened while it was fading.
    private var showGeneration = 0

    var isVisible: Bool { panel.isVisible }

    init() {
        panel = BadgePanel(
            contentRect: CGRect(origin: .zero, size: Layout.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false   // NSPanel default is true; the app is rarely active anyway
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .none   // alpha is animated manually in fade(to:)

        setupContentView()
        panel.contentView = contentView
        contentView.onClick = { [weak self] in self?.dismiss() }
    }

    // MARK: Showing

    /// Shows the badge centred under `anchor` (screen coordinates), or replaces the
    /// current badge's content in place if one is already visible.
    func show(_ content: BadgeContent, anchoredTo anchor: CGRect?) {
        showGeneration += 1
        apply(content)

        guard let screen = targetScreen(for: anchor) else { return }
        let frame = BadgeGeometry.cardFrame(size: Layout.size, anchor: anchor, visibleFrame: screen.visibleFrame)
        panel.setFrame(frame, display: false)

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        fade(to: 1, duration: 0.18)
    }

    func dismiss() {
        guard panel.isVisible else { return }
        let generation = showGeneration
        fade(to: 0, duration: 0.25) { [weak self] in
            guard let self, self.showGeneration == generation else { return }
            self.panel.orderOut(nil)
        }
    }

    // MARK: Private

    private func setupContentView() {
        contentView.material = .popover
        contentView.blendingMode = .behindWindow
        contentView.state = .active   // default follows window-active state, which is never active here
        contentView.wantsLayer = true
        contentView.maskImage = Self.roundedMask(radius: Layout.cornerRadius)

        iconView.imageScaling = .scaleNone

        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .labelColor
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        for label in [titleLabel, subtitleLabel] {
            label.alignment = .center
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        let stack = NSStackView(views: [iconView, titleLabel, subtitleLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 2
        stack.setCustomSpacing(8, after: iconView)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Layout.horizontalPadding),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Layout.horizontalPadding),
        ])
    }

    private func apply(_ content: BadgeContent) {
        let config = NSImage.SymbolConfiguration(pointSize: Layout.iconPointSize, weight: .medium)
        let symbol = NSImage(systemSymbolName: content.symbolName, accessibilityDescription: content.title)
            ?? NSImage(systemSymbolName: "bell.fill", accessibilityDescription: content.title)
        iconView.image = symbol?.withSymbolConfiguration(config)
        iconView.contentTintColor = content.accent
        titleLabel.stringValue = content.title
        subtitleLabel.stringValue = content.subtitle
    }

    /// The display whose x-range contains the anchor (so a menu bar that slid off the top
    /// in fullscreen still resolves to the right screen), else the one under the mouse.
    private func targetScreen(for anchor: CGRect?) -> NSScreen? {
        if let a = anchor,
           let screen = NSScreen.screens.first(where: { $0.frame.minX <= a.midX && a.midX < $0.frame.maxX }) {
            return screen
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func fade(to alpha: CGFloat, duration: TimeInterval, completion: (() -> Void)? = nil) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduceMotion ? 0 : duration
            panel.animator().alphaValue = alpha
        }, completionHandler: completion)
    }

    /// A stretchable rounded-rect mask. `layer.cornerRadius` does not reliably clip a
    /// behind-window blur, but `NSVisualEffectView.maskImage` does.
    private static func roundedMask(radius r: CGFloat) -> NSImage {
        let edge = r * 2 + 1
        let image = NSImage(size: CGSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        image.resizingMode = .stretch
        return image
    }
}

// MARK: - Panel & content view

/// Borderless panel that can never become key or main, so showing it never steals focus.
private final class BadgePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Blurred card background that treats a click anywhere inside as "dismiss".
private final class BadgeContentView: NSVisualEffectView {
    var onClick: (() -> Void)?

    /// The panel is never key, so without this the first click would be swallowed.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Route every click inside the card to this view so the labels/icon don't eat it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
