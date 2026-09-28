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

    init(result: Result<UsageSnapshot, Error>) {
        self.result = result
    }

    func fetch(
        isManual: Bool,
        completion: @escaping (Result<UsageSnapshot, Error>) -> Void
    ) -> Bool {
        completion(result)
        return true
    }
}
