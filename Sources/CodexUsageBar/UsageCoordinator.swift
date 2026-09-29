import Foundation

final class UsageCoordinator {
    var onSnapshot: ((UsageSnapshot) -> Void)?
    var onChecked: ((Date) -> Void)?
    var onConnectionStatus: ((String, ConnectionHealth) -> Void)?

    private let monitor: UsageMonitor
    // nil이면 실시간 조회 없이 로컬 기록만 추적한다.
    private let liveFetcher: LiveUsageFetching?
    private let defaults: UserDefaults
    private let cacheKey: String
    private let sourceName: String
    private let liveSuccessStatus: String

    private var lastSnapshot: UsageSnapshot?
    private var lastCheckedAt: Date?
    private var lastLiveCheckedAt: Date?
    private var lastLiveAttemptAt: Date?
    private var liveHealthy = false
    private var liveRefreshInProgress = false
    private var started = false

    // 설정된 경우에만 실시간 조회를 주기적으로 반복한다(Claude).
    private var livePollInterval: TimeInterval?
    private var liveTimer: Timer?

    init(
        monitor: UsageMonitor = UsageMonitor(pollInterval: 20),
        liveFetcher: LiveUsageFetching? = LiveUsageFetcher(),
        defaults: UserDefaults = .standard,
        cacheKey: String = "lastUsageSnapshot",
        sourceName: String = UsageProvider.codex.displayName,
        liveSuccessStatus: String = "Codex 계정 API"
    ) {
        self.monitor = monitor
        self.liveFetcher = liveFetcher
        self.defaults = defaults
        self.cacheKey = cacheKey
        self.sourceName = sourceName
        self.liveSuccessStatus = liveSuccessStatus
    }

    func start() {
        guard !started else { return }
        started = true

        monitor.onSnapshot = { [weak self] snapshot in
            DispatchQueue.main.async {
                self?.applyLocal(snapshot)
            }
        }
        monitor.onChecked = { [weak self] checkedAt in
            DispatchQueue.main.async {
                self?.markChecked(at: checkedAt)
            }
        }
        monitor.onStatus = { [weak self] status, health in
            DispatchQueue.main.async {
                guard let self, !self.liveRefreshInProgress, !self.liveHealthy else { return }
                self.onConnectionStatus?(status, health)
            }
        }

        restoreCachedSnapshot()
        monitor.start()
        if liveFetcher != nil {
            refreshLive(isManual: false)
        }
        scheduleLiveTimer()
    }

    func stop() {
        guard started else { return }
        started = false
        liveTimer?.invalidate()
        liveTimer = nil
        monitor.stop()
    }

    func setLivePollInterval(_ interval: TimeInterval?) {
        guard interval != livePollInterval else { return }
        livePollInterval = interval
        scheduleLiveTimer()
    }

    func requestLocalRefreshIfStale(maxAge: TimeInterval = 25, now: Date = Date()) {
        guard let lastCheckedAt, now.timeIntervalSince(lastCheckedAt) > maxAge else {
            return
        }
        monitor.requestRefresh()
    }

    /// 마지막 실시간 조회가 maxAge보다 오래됐으면 바로 한 번 더 조회한다(앱 전환·메뉴 열기용).
    func refreshLiveIfStale(maxAge: TimeInterval, now: Date = Date()) {
        if let lastLiveAttemptAt, now.timeIntervalSince(lastLiveAttemptAt) < maxAge {
            return
        }
        refreshLive(isManual: false)
    }

    func refreshLive(isManual: Bool) {
        guard let liveFetcher else {
            monitor.requestRefresh()
            return
        }
        guard !liveRefreshInProgress else { return }
        liveRefreshInProgress = true
        lastLiveAttemptAt = Date()
        if isManual || !liveHealthy {
            onConnectionStatus?(
                isManual ? "실시간 계정 새로고침 중…" : "실시간 계정 확인 중…",
                .working
            )
        }

        let started = liveFetcher.fetch(isManual: isManual) { [weak self] result in
            guard let self else { return }
            self.liveRefreshInProgress = false

            switch result {
            case .success(let snapshot):
                self.liveHealthy = true
                self.applyLive(snapshot)
                self.markChecked(at: snapshot.fetchedAt)
                // 다음 조회까지 이 문구가 남으므로 언제 조회했는지 함께 보여준다.
                self.onConnectionStatus?("\(self.liveSuccessStatus) · 마지막 조회 \(UsageFormat.time(Date()))", .ok)
            case .failure(let error):
                self.liveHealthy = false
                self.onConnectionStatus?("\(error.localizedDescription) · 로컬 기록 사용", .degraded)
                if isManual {
                    self.monitor.requestRefresh()
                }
            }
        }

        if !started {
            liveRefreshInProgress = false
            onConnectionStatus?("실시간 계정 조회가 이미 진행 중", .working)
        }
    }

    func applyLocal(_ snapshot: UsageSnapshot) {
        // 주기 실시간 조회가 정상이면 더 거친 로컬 기록으로 덮어쓰지 않는다.
        if livePollInterval != nil, liveHealthy {
            return
        }
        if let lastLiveCheckedAt, snapshot.fetchedAt <= lastLiveCheckedAt {
            return
        }
        apply(snapshot)
    }

    func applyLive(_ snapshot: UsageSnapshot) {
        lastLiveCheckedAt = snapshot.fetchedAt
        apply(snapshot)
    }

    private func scheduleLiveTimer() {
        liveTimer?.invalidate()
        liveTimer = nil
        guard started, liveFetcher != nil, let livePollInterval else { return }

        let timer = Timer(timeInterval: livePollInterval, repeats: true) { [weak self] _ in
            self?.refreshLive(isManual: false)
        }
        timer.tolerance = min(10, livePollInterval * 0.2)
        RunLoop.main.add(timer, forMode: .common)
        liveTimer = timer
    }

    private func apply(_ snapshot: UsageSnapshot) {
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        save(snapshot)
        onSnapshot?(snapshot)
    }

    private func markChecked(at date: Date) {
        lastCheckedAt = date
        onChecked?(date)
    }

    private func restoreCachedSnapshot() {
        guard
            let data = defaults.data(forKey: cacheKey),
            let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data)
        else {
            return
        }
        applyLocal(snapshot.adjustedForCurrentTime())
        onConnectionStatus?("저장된 값 · \(sourceName) 연결 중…", .working)
    }

    private func save(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: cacheKey)
    }
}
