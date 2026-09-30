import AppKit
import Foundation

enum UsageProvider: String, CaseIterable, Codable {
    case codex
    case claude

    var bundleIdentifier: String {
        switch self {
        case .codex:
            return "com.openai.codex"
        case .claude:
            return "com.anthropic.claudefordesktop"
        }
    }

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        }
    }

    init?(bundleIdentifier: String?) {
        guard
            let provider = Self.allCases.first(where: { $0.bundleIdentifier == bundleIdentifier })
        else {
            return nil
        }
        self = provider
    }
}

final class AppLifecycle {
    var onLaunched: ((UsageProvider) -> Void)?
    var onTerminated: ((UsageProvider) -> Void)?
    var onActivated: ((UsageProvider) -> Void)?

    private let workspace: NSWorkspace
    private var observing = false

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    var runningProviders: Set<UsageProvider> {
        Self.providers(
            in: workspace.runningApplications
                .filter { !$0.isTerminated }
                .map(\.bundleIdentifier)
        )
    }

    var isAnyProviderRunning: Bool {
        !runningProviders.isEmpty
    }

    var frontmostProvider: UsageProvider? {
        UsageProvider(bundleIdentifier: workspace.frontmostApplication?.bundleIdentifier)
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
        center.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    func stopObserving() {
        guard observing else { return }
        workspace.notificationCenter.removeObserver(self)
        observing = false
    }

    static func providers(in bundleIdentifiers: [String?]) -> Set<UsageProvider> {
        Set(bundleIdentifiers.compactMap(UsageProvider.init(bundleIdentifier:)))
    }

    /// 메뉴 막대에 보여줄 앱: 앞에 있는 앱 → 직전에 보던 앱 → 실행 중인 앱 순서.
    static func preferredProvider(
        frontmost: UsageProvider?,
        running: Set<UsageProvider>,
        previous: UsageProvider?
    ) -> UsageProvider {
        if let frontmost {
            return frontmost
        }
        if let previous, running.isEmpty || running.contains(previous) {
            return previous
        }
        return UsageProvider.allCases.first(where: running.contains) ?? previous ?? .codex
    }

    @objc private func applicationDidLaunch(_ notification: Notification) {
        guard let provider = provider(in: notification) else { return }
        onLaunched?(provider)
    }

    @objc private func applicationDidTerminate(_ notification: Notification) {
        guard let provider = provider(in: notification) else { return }
        onTerminated?(provider)
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        guard let provider = provider(in: notification) else { return }
        onActivated?(provider)
    }

    private func provider(in notification: Notification) -> UsageProvider? {
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication
        return UsageProvider(bundleIdentifier: application?.bundleIdentifier)
    }
}
