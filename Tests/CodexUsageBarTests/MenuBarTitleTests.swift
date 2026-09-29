import Foundation
import XCTest
@testable import CodexUsageBar

final class MenuBarTitleTests: XCTestCase {
    func testShowsEveryWindowWhenThereAreSeveral() {
        let snapshot = UsageSnapshot(
            windows: [
                UsageWindow(label: "5시간 한도", usedPercent: 37, windowDurationMinutes: 300, resetsAt: nil),
                UsageWindow(label: "주간 한도", usedPercent: 12, windowDurationMinutes: 10_080, resetsAt: nil)
            ],
            planType: nil,
            fetchedAt: Date()
        )
        XCTAssertEqual(snapshot.menuBarTitle, "5h 63% · W 88%")
        XCTAssertEqual(snapshot.menuBarToolTip, "5시간 한도 63% 남음, 주간 한도 88% 남음")
    }

    func testSingleWindowShowsOnlyPercent() {
        let snapshot = UsageSnapshot(
            windows: [UsageWindow(label: "주간 한도", usedPercent: 40, windowDurationMinutes: 10_080, resetsAt: nil)],
            planType: nil,
            fetchedAt: Date()
        )
        XCTAssertEqual(snapshot.menuBarTitle, "60%")
    }
}
