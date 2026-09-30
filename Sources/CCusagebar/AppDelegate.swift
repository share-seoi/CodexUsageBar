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
    // Codex 앱이 꺼져 있어도 Claude에서 부른 Codex CLI 등이 로컬 기록을 남기므로 이 간격으로 확인한다.
    // 두 앱이 모두 꺼지면 이 앱 자체가 종료되므로 그때는 확인하지 않는다.
    private static let codexClosedLocalInterval: TimeInterval = 60

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
    // 연결 상태가 바뀔 때만 로그에 남기려고 마지막 상태를 기억한다.
    private var lastLoggedHealth: [UsageProvider: ConnectionHealth] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppInfo.migrateLegacyDefaults()
        NSSetUncaughtExceptionHandler { exception in
            Log.write("처리되지 않은 예외: \(exception.name.rawValue) \(exception.reason ?? "")\n\(exception.callStackSymbols.joined(separator: "\n"))")
            Log.flush()
        }
        let runningAtStart = lifecycle.runningProviders.map(\.displayName).sorted()
        Log.write("시작 v\(AppInfo.version) · 실행 중인 앱: \(runningAtStart.isEmpty ? "없음" : runningAtStart.joined(separator: ", "))")
        lifecycle.onLaunched = { [weak self] provider in
            Log.write("\(provider.displayName) 앱 실행됨")
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
            Log.write("\(provider.displayName) 앱 종료됨")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let self else { return }
                if !self.lifecycle.runningProviders.contains(provider) {
                    self.pause(provider, status: "앱 종료됨 · 마지막 기록 표시")
                }
                guard self.lifecycle.isAnyProviderRunning else {
                    Log.write("Codex·Claude 모두 꺼짐 · 함께 종료")
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
                Log.write("Codex·Claude가 실행 중이 아님 · 종료")
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
        Log.write("종료")
        Log.flush()
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
            // 로컬 기록 확인은 가볍고, 꺼진 Codex도 1분 확인 중이므로 모두 요청한다.
            self.coordinators.values.forEach { $0.requestLocalRefreshIfStale() }
            if self.lifecycle.runningProviders.contains(.claude) {
                self.coordinators[.claude]?.refreshLiveIfStale(maxAge: Self.claudeStaleAge)
            }
        }
        menuController.onShowBothChanged = { [weak self] showBoth in
            guard let self else { return }
            UserDefaults.standard.set(showBoth, forKey: Self.showBothKey)
            Log.write("둘 다 표시 \(showBoth ? "켬" : "끔")")
            self.updateClaudePolling(for: self.activeProvider ?? .codex)
        }
        menuController.onQuit = {
            Log.write("메뉴에서 종료 선택")
            NSApp.terminate(nil)
        }

        for (provider, coordinator) in coordinators {
            coordinator.onSnapshot = { [weak menuController] snapshot in
                menuController?.render(snapshot, for: provider)
            }
            coordinator.onChecked = { [weak menuController] date in
                menuController?.markChecked(at: date, for: provider)
            }
            coordinator.onConnectionStatus = { [weak self] status, health in
                self?.setConnectionStatus(status, health: health, for: provider)
            }
        }
        updateClaudePolling(for: initialProvider)
        let running = lifecycle.runningProviders
        for (provider, coordinator) in coordinators {
            if running.contains(provider) {
                coordinator.start()
            } else {
                pause(provider, status: "앱 꺼짐 · 마지막 기록 표시")
            }
        }
    }

    /// 꺼진 앱의 조회를 줄인다. Claude는 남은 토큰으로 같은 값을 반복해 받지 않도록 멈추고,
    /// Codex는 실시간 조회만 멈추고 로컬 기록은 1분마다 계속 확인한다.
    private func pause(_ provider: UsageProvider, status: String) {
        guard let coordinator = coordinators[provider] else { return }
        switch provider {
        case .claude:
            coordinator.stop()
            coordinator.showCachedSnapshot(status: status)
            setConnectionStatus(status, health: .degraded, for: provider)
        case .codex:
            coordinator.startBackground(localInterval: Self.codexClosedLocalInterval)
        }
    }

    private func setConnectionStatus(_ status: String, health: ConnectionHealth, for provider: UsageProvider) {
        statusMenuController?.setConnectionStatus(status, health: health, for: provider)
        // 상태 문구는 조회마다 바뀌므로(마지막 조회 시각) 건강 상태가 바뀔 때만 남긴다.
        // 문구에는 오류 설명만 들어가고 토큰이나 응답 본문은 없다.
        // "확인 중"(working)은 조회할 때마다 잠깐 거치므로 빼고, 결과 상태가 바뀔 때만 남긴다.
        guard health != .working, lastLoggedHealth[provider] != health else { return }
        lastLoggedHealth[provider] = health
        Log.write("\(provider.displayName) 연결 \(health) · \(status)")
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
