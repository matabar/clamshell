import AppKit
import Combine
import SwiftUI

/// Menu bar presence and the single shared menu, which is also what the widget
/// shows on right-click.
///
/// The widget has no window chrome and the app has no Dock icon, so this is the
/// only way to reach quit, the window layer switch and the passwordless setup —
/// and the coloured glyph keeps the state readable while the widget is buried
/// behind other windows on the desktop layer.
@MainActor
final class MenuBarController: NSObject {
    let menu = NSMenu()

    private let statusItem: NSStatusItem
    private let controller: SleepController
    private let preferences: Preferences
    private var cancellables = Set<AnyCancellable>()

    /// Called when the user asks to show or hide the widget window.
    var onWidgetVisibilityChange: ((Bool) -> Void)?

    private let stateItem = NSMenuItem()
    private let blockItem = NSMenuItem()
    private let showWidgetItem = NSMenuItem()
    private let layerItem = NSMenuItem()
    private let passwordlessItem = NSMenuItem()
    private let launchAtLoginItem = NSMenuItem()

    init(controller: SleepController, preferences: Preferences = .shared) {
        self.controller = controller
        self.preferences = preferences
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        buildMenu()
        configureStatusItem()
        observe()
        refreshAppearance()
    }

    // MARK: - Status item

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Clamshell"
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true

        if wantsMenu {
            // Attaching the menu makes the next click open it; `performClick`
            // blocks until it closes, so detaching afterwards is safe.
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            controller.toggle()
        }
    }

    private func observe() {
        // `objectWillChange` fires before the value lands, so the hop through the
        // run loop is what makes the refresh see the new state.
        controller.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshAppearance() }
            .store(in: &cancellables)

        preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshAppearance() }
            .store(in: &cancellables)
    }

    private func refreshAppearance() {
        statusItem.button?.image = statusImage()
        statusItem.button?.toolTip = "Clamshell — \(controller.statusDescription)"
    }

    private func statusImage() -> NSImage? {
        let alerting = controller.errorMessage != nil || !controller.isReadable
        let name = alerting
            ? "exclamationmark.triangle.fill"
            : (controller.isBlocked ? "sun.max.fill" : "moon.zzz.fill")
        let color: NSColor = alerting
            ? NSColor(Color.clamshellAmber)
            : NSColor(controller.isBlocked ? Color.clamshellRed : Color.clamshellGreen)

        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Lid sleep")?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = false
        return image
    }

    // MARK: - Menu

    private func buildMenu() {
        menu.delegate = self

        stateItem.isEnabled = false
        menu.addItem(stateItem)

        blockItem.title = "Block Lid Sleep"
        blockItem.target = self
        blockItem.action = #selector(toggleBlocked)
        menu.addItem(blockItem)

        menu.addItem(.separator())

        showWidgetItem.title = "Show Widget"
        showWidgetItem.target = self
        showWidgetItem.action = #selector(toggleWidgetVisible)
        menu.addItem(showWidgetItem)

        layerItem.title = "Window Layer"
        let layerMenu = NSMenu()
        for layer in WindowLayer.allCases {
            let item = NSMenuItem(
                title: layer.title,
                action: #selector(selectLayer(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = layer.rawValue
            layerMenu.addItem(item)
        }
        layerItem.submenu = layerMenu
        menu.addItem(layerItem)

        menu.addItem(.separator())

        passwordlessItem.target = self
        passwordlessItem.action = #selector(togglePasswordless)
        menu.addItem(passwordlessItem)

        launchAtLoginItem.title = "Launch at Login"
        launchAtLoginItem.target = self
        launchAtLoginItem.action = #selector(toggleLaunchAtLogin)
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let quit = NSMenuItem(title: "Quit Clamshell", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func syncMenu() {
        if let errorMessage = controller.errorMessage {
            stateItem.title = errorMessage
        } else if !controller.isReadable {
            stateItem.title = "Sleep setting unavailable"
        } else {
            stateItem.title = controller.isBlocked ? "Lid sleep blocked" : "Sleep enabled"
        }

        blockItem.state = controller.isBlocked ? .on : .off
        blockItem.isEnabled = !controller.isBusy

        showWidgetItem.state = preferences.widgetVisible ? .on : .off

        layerItem.submenu?.items.forEach { item in
            item.state = (item.representedObject as? String) == preferences.windowLayer.rawValue
                ? .on
                : .off
        }

        passwordlessItem.title = controller.passwordlessEnabled
            ? "Require Password to Toggle…"
            : "Toggle Without Password…"
        passwordlessItem.state = controller.passwordlessEnabled ? .on : .off
        passwordlessItem.isEnabled = !controller.isBusy
        passwordlessItem.toolTip = controller.passwordlessEnabled
            ? "Removes \(Privileges.sudoersRulePath)."
            : "Installs a sudoers rule allowing only the two pmset commands this app runs."

        launchAtLoginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        if LaunchAtLogin.requiresApproval {
            launchAtLoginItem.toolTip = "Approve Clamshell in System Settings › General › Login Items."
        } else {
            launchAtLoginItem.toolTip = nil
        }
    }

    // MARK: - Actions

    @objc private func toggleBlocked() {
        controller.toggle()
    }

    @objc private func toggleWidgetVisible() {
        let visible = !preferences.widgetVisible
        preferences.widgetVisible = visible
        onWidgetVisibilityChange?(visible)
    }

    @objc private func selectLayer(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let layer = WindowLayer(rawValue: raw)
        else { return }
        preferences.windowLayer = layer
    }

    @objc private func togglePasswordless() {
        if controller.passwordlessEnabled {
            controller.removePasswordless()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Toggle without a password?"
        alert.informativeText = """
        Clamshell will install this rule at \(Privileges.sudoersRulePath):

        \(Privileges.sudoersRule)

        It grants exactly these two commands and nothing else. You will be asked \
        to authenticate once to install it, and can remove it from this menu at \
        any time.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        controller.installPasswordless()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.set(!LaunchAtLogin.isEnabled)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change the login item"
            alert.informativeText = """
            \(error.localizedDescription)

            macOS only registers login items for apps in a stable location. Run \
            `make install` to move Clamshell.app to /Applications and try again.
            """
            alert.alertStyle = .warning
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        syncMenu()
    }

    @objc private func refreshNow() {
        Task {
            await controller.refresh()
            await controller.refreshPasswordlessState()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension MenuBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        syncMenu()
    }
}
