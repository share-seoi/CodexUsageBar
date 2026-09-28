import Foundation

final class UsageMonitor {
    var onSnapshot: ((UsageSnapshot) -> Void)?
    var onChecked: ((Date) -> Void)?
    var onStatus: ((String, ConnectionHealth) -> Void)?

    private let loadSnapshot: () throws -> UsageSnapshot?
    private let pollInterval: TimeInterval
    private let sourceName: String
    private let queue = DispatchQueue(label: "local.mackim.CodexUsageBar.local-monitor")
    private var timer: DispatchSourceTimer?
    private var running = false
    private var scanning = false
    private var lastSnapshot: UsageSnapshot?

    init(store: LocalUsageStore = LocalUsageStore(), pollInterval: TimeInterval = 20) {
        self.loadSnapshot = { try store.latestSnapshot() }
        self.pollInterval = pollInterval
        self.sourceName = UsageProvider.codex.displayName
    }

    init(
        pollInterval: TimeInterval,
        sourceName: String = UsageProvider.codex.displayName,
        loadSnapshot: @escaping () throws -> UsageSnapshot?
    ) {
        self.loadSnapshot = loadSnapshot
        self.pollInterval = pollInterval
        self.sourceName = sourceName
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
            if let snapshot = try loadSnapshot() {
                if snapshot != lastSnapshot {
                    lastSnapshot = snapshot
                    onSnapshot?(snapshot)
                }
                onChecked?(Date())
                onStatus?("로컬 기록 · 20초마다 확인", .ok)
            } else {
                onStatus?("\(sourceName) 사용 기록 대기 중", .working)
            }
        } catch {
            onStatus?(error.localizedDescription, .error)
        }
    }
}
