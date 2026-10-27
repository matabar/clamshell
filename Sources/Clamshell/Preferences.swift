import AppKit
import Combine

/// Where the widget sits in the window stack.
enum WindowLayer: String, CaseIterable {
    /// Pinned just above the desktop wallpaper, behind every application window.
    case desktop
    /// Floating above normal windows, always reachable.
    case floating

    var title: String {
        switch self {
        case .desktop: return "Desktop"
        case .floating: return "Floating"
        }
    }

    var windowLevel: NSWindow.Level {
        switch self {
        case .desktop:
            // One step above the Finder's desktop window rather than above the
            // wallpaper: that window spans the whole screen, so anything below it
            // looks right but never receives a click.
            return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .floating:
            return .floating
        }
    }
}

final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let windowLayer = "windowLayer"
        static let widgetVisible = "widgetVisible"
        static let widgetOriginX = "widgetOriginX"
        static let widgetOriginY = "widgetOriginY"
    }

    private let defaults: UserDefaults

    @Published var windowLayer: WindowLayer {
        didSet { defaults.set(windowLayer.rawValue, forKey: Key.windowLayer) }
    }

    @Published var widgetVisible: Bool {
        didSet { defaults.set(widgetVisible, forKey: Key.widgetVisible) }
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.widgetVisible: true])

        let stored = defaults.string(forKey: Key.windowLayer) ?? WindowLayer.desktop.rawValue
        windowLayer = WindowLayer(rawValue: stored) ?? .desktop
        widgetVisible = defaults.bool(forKey: Key.widgetVisible)
    }

    var widgetOrigin: CGPoint? {
        get {
            guard
                defaults.object(forKey: Key.widgetOriginX) != nil,
                defaults.object(forKey: Key.widgetOriginY) != nil
            else { return nil }
            return CGPoint(
                x: defaults.double(forKey: Key.widgetOriginX),
                y: defaults.double(forKey: Key.widgetOriginY)
            )
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.widgetOriginX)
                defaults.removeObject(forKey: Key.widgetOriginY)
                return
            }
            defaults.set(newValue.x, forKey: Key.widgetOriginX)
            defaults.set(newValue.y, forKey: Key.widgetOriginY)
        }
    }
}
