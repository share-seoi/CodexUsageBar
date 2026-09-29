import Foundation
import XCTest
@testable import CodexUsageBar

final class UsageCoordinatorTests: XCTestCase {
    func testOlderLocalSnapshotDoesNotReplaceLiveSnapshot() {
        let coordinator = makeCoordinator()
        let live = snapshot(usedPercent: 30, fetchedAt: 200)
        let staleLocal = snapshot(usedPercent: 80, fetchedAt: 100)
        var emitted: [UsageSnapshot] = []
        coordinator.onSnapshot = { emitted.append($0) }

        coordinator.applyLive(live)
        coordinator.applyLocal(staleLocal)

        XCTAssertEqual(emitted, [live])
    }

    func testNewerLocalSnapshotCanReplaceLiveSnapshot() {
        let coordinator = makeCoordinator()
        let live = snapshot(usedPercent: 30, fetchedAt: 100)
        let newerLocal = snapshot(usedPercent: 40, fetchedAt: 200)
        var emitted: [UsageSnapshot] = []
        coordinator.onSnapshot = { emitted.append($0) }

        coordinator.applyLive(live)
        coordinator.applyLocal(newerLocal)

        XCTAssertEqual(emitted, [live, newerLocal])
    }

    private func makeCoordinator() -> UsageCoordinator {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        return UsageCoordinator(
            monitor: UsageMonitor(pollInterval: 3_600) { nil },
            defaults: defaults,
            cacheKey: UUID().uuidString
        )
    }

    private func snapshot(usedPercent: Int, fetchedAt: TimeInterval) -> UsageSnapshot {
        UsageSnapshot(
            windows: [
                UsageWindow(
                    label: "주간 한도",
                    usedPercent: usedPercent,
                    windowDurationMinutes: 10_080,
                    resetsAt: nil
                )
            ],
            planType: "pro",
            fetchedAt: Date(timeIntervalSince1970: fetchedAt)
        )
    }
}

final class UsageCoordinatorLivePollingTests: XCTestCase {
    func testHealthyLivePollingIsNotOverriddenByLocalHistory() {
        let fetcher = StubLiveFetcher(result: .success(snapshot(usedPercent: 10, fetchedAt: 100)))
        let coordinator = UsageCoordinator(
            monitor: UsageMonitor(pollInterval: 3_600) { nil },
            liveFetcher: fetcher,
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            cacheKey: UUID().uuidString
        )
        var emitted: [UsageSnapshot] = []
        coordinator.onSnapshot = { emitted.append($0) }
        coordinator.setLivePollInterval(60)

        coordinator.refreshLive(isManual: false)
        coordinator.applyLocal(snapshot(usedPercent: 50, fetchedAt: 200))

        XCTAssertEqual(emitted.map(\.overallRemainingPercent), [90])
    }

    func testLocalHistoryIsUsedWhenLiveFetchFails() {
        let fetcher = StubLiveFetcher(result: .failure(ClaudeLiveUsageError.tokenExpired))
        let coordinator = UsageCoordinator(
            monitor: UsageMonitor(pollInterval: 3_600) { nil },
            liveFetcher: fetcher,
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            cacheKey: UUID().uuidString
        )
        var emitted: [UsageSnapshot] = []
        var statuses: [String] = []
        coordinator.onSnapshot = { emitted.append($0) }
        coordinator.onConnectionStatus = { status, _ in statuses.append(status) }
        coordinator.setLivePollInterval(60)

        coordinator.refreshLive(isManual: false)
        coordinator.applyLocal(snapshot(usedPercent: 50, fetchedAt: 200))

        XCTAssertEqual(emitted.map(\.overallRemainingPercent), [50])
        XCTAssertTrue(statuses.last?.hasSuffix("로컬 기록 사용") ?? false)
    }

    func testSwitchRefreshWorksWithoutPollingAndSkipsWithinMaxAge() {
        let fetcher = StubLiveFetcher(result: .success(snapshot(usedPercent: 10, fetchedAt: 100)))
        let coordinator = UsageCoordinator(
            monitor: UsageMonitor(pollInterval: 3_600) { nil },
            liveFetcher: fetcher,
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            cacheKey: UUID().uuidString,
            liveSuccessStatus: "Codex 계정 API"
        )
        var statuses: [String] = []
        coordinator.onConnectionStatus = { status, _ in statuses.append(status) }

        coordinator.refreshLiveIfStale(maxAge: 60)
        coordinator.refreshLiveIfStale(maxAge: 60)

        XCTAssertEqual(fetcher.calls, 1)
        XCTAssertTrue(statuses.last?.hasPrefix("Codex 계정 API · 마지막 조회 ") ?? false)
    }

    func testClosedCodexChecksLocalHistoryWithoutLiveLookupUntilAppStarts() {
        let fetcher = StubLiveFetcher(result: .success(snapshot(usedPercent: 10, fetchedAt: 100)))
        let coordinator = UsageCoordinator(
            monitor: UsageMonitor(pollInterval: 3_600) { nil },
            liveFetcher: fetcher,
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            cacheKey: UUID().uuidString
        )

        coordinator.startBackground(localInterval: 60)
        coordinator.refreshLiveIfStale(maxAge: 60)
        XCTAssertEqual(fetcher.calls, 0)

        // 앱이 켜지면 실시간 조회를 바로 한 번 한다.
        coordinator.start()
        XCTAssertEqual(fetcher.calls, 1)

        // 다시 꺼지면 실시간 조회는 멈춘다.
        coordinator.startBackground(localInterval: 60)
        coordinator.refreshLiveIfStale(maxAge: 0)
        XCTAssertEqual(fetcher.calls, 1)
        coordinator.stop()
    }

    func testClosedAppShowsCachedValueWithoutLookup() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let cacheKey = UUID().uuidString
        let writer = UsageCoordinator(
            monitor: UsageMonitor(pollInterval: 3_600) { nil },
            liveFetcher: nil,
            defaults: defaults,
            cacheKey: cacheKey
        )
        writer.applyLocal(snapshot(usedPercent: 30, fetchedAt: 100))

        let fetcher = StubLiveFetcher(result: .success(snapshot(usedPercent: 10, fetchedAt: 200)))
        let coordinator = UsageCoordinator(
            monitor: UsageMonitor(pollInterval: 3_600) { nil },
            liveFetcher: fetcher,
            defaults: defaults,
            cacheKey: cacheKey
        )
        var emitted: [UsageSnapshot] = []
        var statuses: [String] = []
        coordinator.onSnapshot = { emitted.append($0) }
        coordinator.onConnectionStatus = { status, _ in statuses.append(status) }

        coordinator.showCachedSnapshot(status: "앱 꺼짐 · 마지막 기록 표시")

        XCTAssertEqual(emitted.map(\.overallRemainingPercent), [70])
        XCTAssertEqual(statuses, ["앱 꺼짐 · 마지막 기록 표시"])
        XCTAssertEqual(fetcher.calls, 0)
    }

    private func snapshot(usedPercent: Int, fetchedAt: TimeInterval) -> UsageSnapshot {
        UsageSnapshot(
            windows: [
                UsageWindow(
                    label: "5시간 한도",
                    usedPercent: usedPercent,
                    windowDurationMinutes: 300,
                    resetsAt: nil
                )
            ],
            planType: nil,
            fetchedAt: Date(timeIntervalSince1970: fetchedAt)
        )
    }
}

private final class StubLiveFetcher: LiveUsageFetching {
    let result: Result<UsageSnapshot, Error>
    private(set) var calls = 0

    init(result: Result<UsageSnapshot, Error>) {
        self.result = result
    }

    func fetch(
        isManual: Bool,
        completion: @escaping (Result<UsageSnapshot, Error>) -> Void
    ) -> Bool {
        calls += 1
        completion(result)
        return true
    }
}
