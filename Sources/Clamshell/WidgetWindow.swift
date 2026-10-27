import AppKit
import SwiftUI

/// Hosting view that behaves like a desktop widget rather than a document window:
/// the first click goes straight through to the control instead of being eaten by
/// window activation, and right-click opens the shared app menu.
private final class WidgetHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

/// Borderless, frosted, draggable window holding the toggle.
///
/// At `.desktop` level it sits just above the wallpaper and behind every
/// application window — a real widget. At `.floating` level it stays on top so it
/// can be reached without clearing the screen first.
final class WidgetWindow: NSWindow {
    private let preferences: Preferences

    init(controller: SleepController, menu: NSMenu, preferences: Preferences = .shared) {
        self.preferences = preferences

        super.init(
            contentRect: NSRect(origin: .zero, size: WidgetMetrics.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        level = preferences.windowLayer.windowLevel

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = WidgetMetrics.cornerRadius
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true
        blur.menu = menu

        let hosting = WidgetHostingView(rootView: ToggleWidget(controller: controller))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.menu = menu
        blur.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: blur.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: blur.bottomAnchor)
        ])

        contentView = blur
        delegate = self

        restorePosition()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func apply(layer: WindowLayer) {
        level = layer.windowLevel
        if isVisible, layer == .floating {
            orderFrontRegardless()
        }
    }

    func show() {
        orderFrontRegardless()
    }

    // MARK: - Position

    private func restorePosition() {
        if let origin = preferences.widgetOrigin, isOnAnyScreen(origin: origin) {
            setFrameOrigin(origin)
        } else {
            moveToDefaultPosition()
        }
    }

    private func moveToDefaultPosition() {
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
        let inset = WidgetMetrics.screenInset
        setFrameOrigin(
            CGPoint(
                x: visible.maxX - WidgetMetrics.size.width - inset,
                y: visible.minY + inset
            )
        )
    }

    /// Guards against restoring onto a display that is no longer connected.
    private func isOnAnyScreen(origin: CGPoint) -> Bool {
        let frame = NSRect(origin: origin, size: WidgetMetrics.size)
        return NSScreen.screens.contains { $0.frame.intersects(frame) }
    }
}

extension WidgetWindow: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        preferences.widgetOrigin = frame.origin
    }
}
