import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let activeProviderKey = "lastActiveProvider"
    private static let showBothKey = "showBoth"
    // Claude가 메뉴 막대에 표시 중일 때는 자주, 아닐 때는 드물게 실시간 조회한다.
    private static let claudeActivePollInterval: TimeInterval = 60
    private static let claudeBackgroundPollInterval: TimeInterval = 180
    private static let claudeStaleAge: TimeInterval = 20
    // Codex는 주기 실시간 조회 없이 전환할 때 조회한다. 조회마다 프로세스를 띄우므로 1분에 한 번까지만.
    private static let codexSwitchRefreshAge: TimeInterval = 60

    private let coordinators: [UsageProvider: UsageCoordinator] = [
        .codex: UsageCoordinator(),
        .claude: UsageCoordinator(
            monitor: UsageMonitor(
                pollInterval: 20,
                sourceName: UsageProvider.claude.displayName
            ) { try ClaudeUsageStore().latestSnapshot() },
            liveFetcher: ClaudeLiveUsageFetcher(),
            cacheKey: "lastClaudeUsageSnapshot",
            sourceName: UsageProvider.claude.displayName,
            liveSuccessStatus: "Claude 계정 API"
        )
    ]
    private let lifecycle = AppLifecycle()

    private var statusMenuController: StatusMenuController?
    private var interfaceStarted = false
    private var startupTimeout: DispatchWorkItem?
    private var activeProvider: UsageProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        lifecycle.onLaunched = { [weak self] provider in
            DispatchQueue.main.async {
                self?.startInterfaceIfNeeded()
                // 앱이 켜지면 그 앱의 조회를 시작하고 바로 한 번 실시간 조회한다.
                self?.coordinators[provider]?.start()
            }
        }
        lifecycle.onActivated = { [weak self] provider in
            DispatchQueue.main.async {
                self?.setActiveProvider(provider)
            }
        }
        lifecycle.onTerminated = { [weak self] provider in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let self else { return }
                // Windows 버전처럼 꺼진 앱은 조회하지 않는다. 남아 있는 토큰으로 같은 값을 반복해 받지 않도록.
                if !self.lifecycle.runningProviders.contains(provider) {
                    self.coordinators[provider]?.stop()
                    self.statusMenuController?.setConnectionStatus(
                        "앱 종료됨 · 마지막 기록 표시", health: .degraded, for: provider
                    )
                }
                guard self.lifecycle.isAnyProviderRunning else {
                    NSApp.terminate(nil)
                    return
                }
                self.setActiveProvider(self.resolveActiveProvider())
            }
        }
        lifecycle.startObserving()

        if lifecycle.isAnyProviderRunning {
            startInterfaceIfNeeded()
        } else {
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, !self.lifecycle.isAnyProviderRunning else {
                    self?.startInterfaceIfNeeded()
                    return
                }
                NSApp.terminate(nil)
            }
            startupTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        startupTimeout?.cancel()
        lifecycle.stopObserving()
        coordinators.values.forEach { $0.stop() }
    }

    private func startInterfaceIfNeeded() {
        guard !interfaceStarted else { return }
        interfaceStarted = true
        startupTimeout?.cancel()
        startupTimeout = nil

        let initialProvider = resolveActiveProvider()
        activeProvider = initialProvider
        let menuController = StatusMenuController(
            activeProvider: initialProvider,
            showBoth: UserDefaults.standard.bool(forKey: Self.showBothKey)
        )
        statusMenuController = menuController

        menuController.onRefresh = { [weak self] in
            self?.runningCoordinators.forEach { $0.refreshLive(isManual: true) }
        }
        menuController.onMenuOpened = { [weak self] in
            guard let self else { return }
            self.runningCoordinators.forEach { $0.requestLocalRefreshIfStale() }
            if self.lifecycle.runningProviders.contains(.claude) {
                self.coordinators[.claude]?.refreshLiveIfStale(maxAge: Self.claudeStaleAge)
            }
        }
        menuController.onShowBothChanged = { [weak self] showBoth in
            guard let self else { return }
            UserDefaults.standard.set(showBoth, forKey: Self.showBothKey)
            self.updateClaudePolling(for: self.activeProvider ?? .codex)
        }
        menuController.onQuit = {
            NSApp.terminate(nil)
        }

        for (provider, coordinator) in coordinators {
            coordinator.onSnapshot = { [weak menuController] snapshot in
                menuController?.render(snapshot, for: provider)
            }
            coordinator.onChecked = { [weak menuController] date in
                menuController?.markChecked(at: date, for: provider)
            }
            coordinator.onConnectionStatus = { [weak menuController] status, health in
                menuController?.setConnectionStatus(status, health: health, for: provider)
            }
        }
        updateClaudePolling(for: initialProvider)
        let running = lifecycle.runningProviders
        for (provider, coordinator) in coordinators {
            if running.contains(provider) {
                coordinator.start()
            } else {
                coordinator.showCachedSnapshot(status: "앱 꺼짐 · 마지막 기록 표시")
            }
        }
    }

    private var runningCoordinators: [UsageCoordinator] {
        let running = lifecycle.runningProviders
        return coordinators.filter { running.contains($0.key) }.map { $0.value }
    }

    private func setActiveProvider(_ provider: UsageProvider) {
        startInterfaceIfNeeded()
        activeProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: Self.activeProviderKey)
        statusMenuController?.setActiveProvider(provider)
        updateClaudePolling(for: provider)
        if provider == .claude {
            coordinators[.claude]?.refreshLiveIfStale(maxAge: Self.claudeStaleAge)
        } else {
            coordinators[.codex]?.refreshLiveIfStale(maxAge: Self.codexSwitchRefreshAge)
        }
    }

    private func updateClaudePolling(for provider: UsageProvider) {
        // "둘 다 표시"면 Claude가 늘 메뉴 막대에 있으므로 표시 중일 때와 같은 간격을 쓴다.
        let claudeShown = provider == .claude || UserDefaults.standard.bool(forKey: Self.showBothKey)
        coordinators[.claude]?.setLivePollInterval(
            claudeShown ? Self.claudeActivePollInterval : Self.claudeBackgroundPollInterval
        )
    }

    private func resolveActiveProvider() -> UsageProvider {
        let saved = UserDefaults.standard.string(forKey: Self.activeProviderKey)
            .flatMap(UsageProvider.init(rawValue:))
        return AppLifecycle.preferredProvider(
            frontmost: lifecycle.frontmostProvider,
            running: lifecycle.runningProviders,
            previous: activeProvider ?? saved
        )
    }
}
