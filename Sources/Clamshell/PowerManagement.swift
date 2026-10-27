import Foundation
import IOKit

/// Reads the current value of the `disablesleep` power management setting.
///
/// There are two sources of truth and they are not equally good:
///
/// * `IOPMrootDomain` always exposes a `SleepDisabled` boolean, so a single IOKit
///   property fetch gives the live kernel state with no subprocess and no root.
///   That makes it cheap enough to poll on a timer.
/// * `pmset -g` / `pmset -g custom` only *print* `disablesleep` when it is set to
///   `1`. When sleep is allowed the key is absent from the output entirely, so the
///   fallback parser has to treat "no match" as "sleep allowed" rather than as an
///   error. It exists only in case the IOKit property ever disappears.
enum PowerManagement {
    static let pmsetPath = "/usr/bin/pmset"

    /// `true` when lid sleep is blocked (`disablesleep 1`), `false` when the Mac
    /// sleeps normally. `nil` only if both sources failed.
    static func isSleepDisabled() -> Bool? {
        if let value = readFromIORegistry() {
            return value
        }
        return readFromPmset()
    }

    private static func readFromIORegistry() -> Bool? {
        guard let matching = IOServiceMatching("IOPMrootDomain") else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        let property = IORegistryEntryCreateCFProperty(
            service,
            "SleepDisabled" as CFString,
            kCFAllocatorDefault,
            0
        )
        guard let number = property?.takeRetainedValue() as? NSNumber else { return nil }
        return number.boolValue
    }

    private static func readFromPmset() -> Bool? {
        let result = Shell.run(pmsetPath, ["-g", "custom"])
        guard result.succeeded else { return nil }

        // `disablesleep        1` under AC Power / Battery Power, or nothing at all.
        for line in result.stdout.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 2, fields[0] == "disablesleep" else { continue }
            return fields[1] != "0"
        }
        return false
    }

    /// Arguments for the privileged write. Deliberately a fixed, non-interpolated
    /// pair so it can be allow-listed verbatim in sudoers.
    static func arguments(disableSleep: Bool) -> [String] {
        ["-a", "disablesleep", disableSleep ? "1" : "0"]
    }
}
