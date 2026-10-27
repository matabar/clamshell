import AppKit
import Foundation

enum PrivilegeError: LocalizedError {
    /// The user dismissed the macOS authentication dialog. Not an error worth showing.
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Authentication cancelled."
        case .failed(let message): return message
        }
    }
}

/// Everything that needs root. Two routes, tried in order:
///
/// 1. `sudo -n` — silent, available only once the user opts in to the narrow
///    `/etc/sudoers.d/clamshell` rule below.
/// 2. AppleScript `do shell script … with administrator privileges` — the native
///    macOS authentication dialog, attributed to this app. Credentials are cached
///    by the AppleScript component for ~5 minutes, so rapid toggles only prompt once.
///
/// The privileged command is a fixed argument vector built in `PowerManagement`;
/// nothing user-supplied is ever interpolated into a shell or AppleScript string.
enum Privileges {
    static let sudoPath = "/usr/bin/sudo"
    static let sudoersRulePath = "/etc/sudoers.d/clamshell"

    // MARK: - Toggling

    static func setSleepDisabled(_ disabled: Bool) throws {
        let arguments = PowerManagement.arguments(disableSleep: disabled)

        if passwordlessAvailable() {
            let result = Shell.run(sudoPath, ["-n", PowerManagement.pmsetPath] + arguments)
            if result.succeeded { return }
            // Fall through to the dialog: the rule may have been removed since we checked.
        }

        let command = ([PowerManagement.pmsetPath] + arguments).joined(separator: " ")
        try runWithAdministratorPrivileges(command)
    }

    // MARK: - Passwordless rule

    /// `sudo -l <command>` exits 0 only when that exact command is permitted, and
    /// `-n` keeps it from ever prompting. This is the real test — it also catches a
    /// rule installed by some other means (nix-darwin, a hand-written sudoers file).
    static func passwordlessAvailable() -> Bool {
        let probe = [PowerManagement.pmsetPath] + PowerManagement.arguments(disableSleep: true)
        return Shell.run(sudoPath, ["-n", "-l"] + probe).succeeded
    }

    static var sudoersRuleInstalled: Bool {
        FileManager.default.fileExists(atPath: sudoersRulePath)
    }

    static var sudoersRule: String {
        let user = NSUserName()
        return "\(user) ALL=(root) NOPASSWD: "
            + "\(PowerManagement.pmsetPath) -a disablesleep 0, "
            + "\(PowerManagement.pmsetPath) -a disablesleep 1"
    }

    static func installPasswordlessRule() throws {
        // Usernames are normally [a-z0-9._-]; refuse anything that could alter the
        // meaning of the sudoers line rather than trying to quote it.
        let user = NSUserName()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard !user.isEmpty, user.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw PrivilegeError.failed("Unsupported characters in user name “\(user)”.")
        }

        // Staged into a temp file and validated with `visudo -c` before it is
        // installed, so a malformed rule can never lock sudo out.
        let script = """
        set -e
        umask 077
        stage="$(/usr/bin/mktemp /tmp/clamshell-sudoers.XXXXXXXX)"
        trap '/bin/rm -f "$stage"' EXIT
        /bin/cat > "$stage" <<'CLAMSHELL_RULE'
        \(sudoersRule)
        CLAMSHELL_RULE
        /usr/sbin/visudo -c -f "$stage" >/dev/null
        /usr/bin/install -m 0440 -o root -g wheel "$stage" \(sudoersRulePath)
        """
        try runPrivileged(script: script)
    }

    static func removePasswordlessRule() throws {
        try runPrivileged(script: "/bin/rm -f \(sudoersRulePath)")
    }

    // MARK: - Administrator plumbing

    /// Runs a multi-line shell script as root. The script travels base64-encoded
    /// inside the AppleScript source, so there is no intermediate file on disk for
    /// anything to tamper with between authentication and execution.
    private static func runPrivileged(script: String) throws {
        let encoded = Data(script.utf8).base64EncodedString()
        try runWithAdministratorPrivileges("echo \(encoded) | /usr/bin/base64 -D | /bin/sh")
    }

    private static func runWithAdministratorPrivileges(_ command: String) throws {
        let source = "do shell script \"\(escapeForAppleScript(command))\" with administrator privileges"

        guard let script = NSAppleScript(source: source) else {
            throw PrivilegeError.failed("Could not compile the authorization script.")
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)

        guard let errorInfo else { return }

        let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
        if code == -128 {
            throw PrivilegeError.cancelled
        }

        let message = (errorInfo[NSAppleScript.errorMessage] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw PrivilegeError.failed(
            message?.isEmpty == false ? message! : "Authorization failed (error \(code))."
        )
    }

    private static func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
