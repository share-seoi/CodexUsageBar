import Foundation

final class UsageMonitor {
    var onSnapshot: ((UsageSnapshot) -> Void)?
    var onStatus: ((String) -> Void)?

    private let store: LocalUsageStore
    private let pollInterval: TimeInterval
    private let queue = DispatchQueue(label: "local.mackim.CodexUsageBar.local-monitor")
    private var timer: DispatchSourceTimer?
    private var running = false
    private var scanning = false
    private var lastSnapshot: UsageSnapshot?

    init(store: LocalUsageStore = LocalUsageStore(), pollInterval: TimeInterval = 20) {
        self.store = store
        self.pollInterval = pollInterval
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.running else { return }
            self.running = true
            self.installTimer()
            self.scan()
        }
    }

    func stop() {
        queue.sync {
            running = false
            timer?.cancel()
            timer = nil
        }
    }

    func requestRefresh() {
        queue.async { [weak self] in
            self?.scan()
        }
    }

    private func installTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + pollInterval,
            repeating: pollInterval,
            leeway: .seconds(2)
        )
        timer.setEventHandler { [weak self] in
            self?.scan()
        }
        self.timer = timer
        timer.resume()
    }

    private func scan() {
        guard running, !scanning else { return }
        scanning = true
        defer { scanning = false }

        do {
            if let snapshot = try store.latestSnapshot() {
                if snapshot != lastSnapshot {
                    lastSnapshot = snapshot
                    onSnapshot?(snapshot)
                }
                onStatus?("로컬 기록 · 20초마다 확인")
            } else {
                onStatus?("Codex 사용 기록 대기 중")
            }
        } catch {
            onStatus?(error.localizedDescription)
        }
    }
}
