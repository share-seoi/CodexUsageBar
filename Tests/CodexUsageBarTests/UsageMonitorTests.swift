import Foundation
import XCTest
@testable import CodexUsageBar

final class UsageMonitorTests: XCTestCase {
    func testRefreshReportsNewCheckTimeEvenWhenSnapshotIsUnchanged() {
        let snapshot = UsageSnapshot(
            windows: [
                UsageWindow(
                    label: "주간 한도",
                    usedPercent: 25,
                    windowDurationMinutes: 10_080,
                    resetsAt: nil
                )
            ],
            planType: "pro",
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let checkedTwice = expectation(description: "checked twice")
        checkedTwice.expectedFulfillmentCount = 2
        let snapshotOnce = expectation(description: "unchanged snapshot emitted once")
        snapshotOnce.expectedFulfillmentCount = 1

        var monitor: UsageMonitor!
        var checkCount = 0
        monitor = UsageMonitor(pollInterval: 3_600) { snapshot }
        monitor.onSnapshot = { _ in
            snapshotOnce.fulfill()
        }
        monitor.onChecked = { _ in
            checkCount += 1
            checkedTwice.fulfill()
            if checkCount == 1 {
                monitor.requestRefresh()
            }
        }

        monitor.start()
        wait(for: [snapshotOnce, checkedTwice], timeout: 2)
        monitor.stop()
    }
}
