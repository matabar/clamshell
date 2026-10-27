import AppKit
import Combine
import Foundation

/// Single source of truth for the UI.
///
/// The displayed state always comes from a real read of the system (see
/// `PowerManagement`), never from what the app last wrote — so a `pmset` run from
/// a terminal, another tool, or a different user session shows up here within one
/// poll interval.
@MainActor
final class SleepController: ObservableObject {
    /// `true` when lid sleep is blocked: the Mac stays awake with the lid closed.
    @Published private(set) var isBlocked = false
    /// A privileged write is in flight — usually the authentication dialog is up.
    @Published private(set) var isBusy = false
    /// Last real failure, cleared automatically. Cancelling authentication is not a failure.
    @Published private(set) var errorMessage: String?
    /// Whether toggling currently happens without an authentication prompt.
    @Published private(set) var passwordlessEnabled = false
    /// `false` if the system state could not be read at all.
    @Published private(set) var isReadable = true

    private let pollInterval: Duration = .seconds(2)
    private let errorLifetime: Duration = .seconds(6)

    private static let privilegedQueue = DispatchQueue(label: "com.matabar.clamshell.privileged")
    private static let readQueue = DispatchQueue(label: "com.matabar.clamshell.read")

    private var pollTask: Task<Void, Never>?
    private var errorTask: Task<Void, Never>?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    var statusDescription: String {
        if let errorMessage { return errorMessage }
        if isBusy { return "Waiting for authorization…" }
        if !isReadable { return "Cannot read the current sleep setting." }
        return isBlocked
            ? "Lid sleep blocked — the Mac stays awake with the lid closed."
            : "Sleep enabled — normal Mac behaviour."
    }

    // MARK: - Lifecycle

    func start() {
        Task {
            await refresh()
            await refreshPasswordlessState()
        }
        startPolling()
        observeSystemEvents()
    }

    func stop() {
        pollTask?.cancel()
        errorTask?.cancel()
        observers.forEach { $0.center.removeObserver($0.token) }
        observers.removeAll()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.pollInterval else { return }
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled else { return }
                // Never read underneath a pending write — the dialog owns the state.
                if !self.isBusy { await self.refresh() }
            }
        }
    }

    private func observeSystemEvents() {
        let refreshOnMain: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { await self?.refresh() }
        }
        let sources: [(NotificationCenter, Notification.Name)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
            (NotificationCenter.default, NSApplication.didBecomeActiveNotification)
        ]
        for (center, name) in sources {
            let token = center.addObserver(
                forName: name,
                object: nil,
                queue: .main,
                using: refreshOnMain
            )
            observers.append((center, token))
        }
    }

    // MARK: - Reading

    func refresh() async {
        let value = await withCheckedContinuation { continuation in
            Self.readQueue.async {
                continuation.resume(returning: PowerManagement.isSleepDisabled())
            }
        }
        guard !isBusy else { return }
        if let value {
            isReadable = true
            if isBlocked != value { isBlocked = value }
        } else {
            isReadable = false
        }
    }

    func refreshPasswordlessState() async {
        passwordlessEnabled = await withCheckedContinuation { continuation in
            Self.readQueue.async {
                continuation.resume(returning: Privileges.passwordlessAvailable())
            }
        }
    }

    // MARK: - Writing

    func toggle() {
        setBlocked(!isBlocked)
    }

    func setBlocked(_ blocked: Bool) {
        guard !isBusy else { return }
        isBusy = true
        clearError()

        Task { [weak self] in
            do {
                try await Self.onPrivilegedQueue { try Privileges.setSleepDisabled(blocked) }
            } catch PrivilegeError.cancelled {
                // The user dismissed the dialog. Leave the state exactly as it was.
            } catch {
                self?.present(error)
            }
            await self?.finishWrite()
        }
    }

    func installPasswordless() {
        runPrivilegedAction { try Privileges.installPasswordlessRule() }
    }

    func removePasswordless() {
        runPrivilegedAction { try Privileges.removePasswordlessRule() }
    }

    private func runPrivilegedAction(_ action: @escaping () throws -> Void) {
        guard !isBusy else { return }
        isBusy = true
        clearError()

        Task { [weak self] in
            do {
                try await Self.onPrivilegedQueue(action)
            } catch PrivilegeError.cancelled {
                // No-op.
            } catch {
                self?.present(error)
            }
            await self?.finishWrite()
        }
    }

    private func finishWrite() async {
        isBusy = false
        await refresh()
        await refreshPasswordlessState()
    }

    private static func onPrivilegedQueue(_ work: @escaping () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            privilegedQueue.async {
                do {
                    try work()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Errors

    private func present(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        errorTask?.cancel()
        errorTask = Task { [weak self] in
            guard let lifetime = self?.errorLifetime else { return }
            try? await Task.sleep(for: lifetime)
            guard !Task.isCancelled else { return }
            self?.errorMessage = nil
        }
    }

    private func clearError() {
        errorTask?.cancel()
        errorMessage = nil
    }

    #if DEBUG
    /// Fixed state for previews and offscreen rendering. Never polls or writes.
    static func preview(
        blocked: Bool,
        busy: Bool = false,
        error: String? = nil
    ) -> SleepController {
        let controller = SleepController()
        controller.isBlocked = blocked
        controller.isBusy = busy
        controller.errorMessage = error
        return controller
    }
    #endif
}
