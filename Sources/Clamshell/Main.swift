import AppKit

@main
struct ClamshellApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        // Menu bar extra plus a desktop widget: no Dock icon, no main menu.
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
