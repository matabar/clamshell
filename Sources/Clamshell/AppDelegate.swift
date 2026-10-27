import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences.shared
    private let controller = SleepController()

    private var menuBar: MenuBarController?
    private var window: WidgetWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menuBar = MenuBarController(controller: controller, preferences: preferences)
        let window = WidgetWindow(controller: controller, menu: menuBar.menu, preferences: preferences)
        self.menuBar = menuBar
        self.window = window

        menuBar.onWidgetVisibilityChange = { [weak self] visible in
            self?.setWidget(visible: visible)
        }

        preferences.$windowLayer
            .sink { [weak window] layer in window?.apply(layer: layer) }
            .store(in: &cancellables)

        setWidget(visible: preferences.widgetVisible)
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    /// No windows to restore — the widget position lives in `Preferences`.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func setWidget(visible: Bool) {
        guard let window else { return }
        if visible {
            window.show()
        } else {
            window.orderOut(nil)
        }
    }
}
