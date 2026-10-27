import Foundation
import ServiceManagement

/// Login item registration via `SMAppService`.
///
/// Registration is rejected for ad-hoc signed builds launched from a build
/// directory, which is exactly how this app is used before `make install`. The
/// failure is surfaced to the menu rather than swallowed, so the item can explain
/// itself instead of silently doing nothing.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
