import AppKit
import Foundation

final class CodexLifecycle {
    static let codexBundleIdentifier = "com.openai.codex"

    var onCodexLaunched: (() -> Void)?
    var onCodexTerminated: (() -> Void)?

    private let workspace: NSWorkspace
    private var observing = false

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    var isCodexRunning: Bool {
        Self.containsCodex(
            bundleIdentifiers: workspace.runningApplications
                .filter { !$0.isTerminated }
                .map(\.bundleIdentifier)
        )
    }

    func startObserving() {
        guard !observing else { return }
        observing = true
        let center = workspace.notificationCenter
        center.addObserver(
            self,
            selector: #selector(applicationDidLaunch(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationDidTerminate(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    func stopObserving() {
        guard observing else { return }
        workspace.notificationCenter.removeObserver(self)
        observing = false
    }

    static func containsCodex(bundleIdentifiers: [String?]) -> Bool {
        bundleIdentifiers.contains { $0 == codexBundleIdentifier }
    }

    @objc private func applicationDidLaunch(_ notification: Notification) {
        guard isCodexApplication(notification) else { return }
        onCodexLaunched?()
    }

    @objc private func applicationDidTerminate(_ notification: Notification) {
        guard isCodexApplication(notification) else { return }
        onCodexTerminated?()
    }

    private func isCodexApplication(_ notification: Notification) -> Bool {
        guard
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
        else {
            return false
        }
        return application.bundleIdentifier == Self.codexBundleIdentifier
    }
}
