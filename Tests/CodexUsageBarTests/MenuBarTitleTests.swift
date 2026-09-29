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

    func testSingleWeeklyWindowIsLabeled() {
        let snapshot = UsageSnapshot(
            windows: [UsageWindow(label: "주간 한도", usedPercent: 40, windowDurationMinutes: 10_080, resetsAt: nil)],
            planType: nil,
            fetchedAt: Date()
        )
        XCTAssertEqual(snapshot.menuBarTitle, "W 60%")
    }

    func testCodexPlusSessionShowsBothWindows() {
        let line = """
        {"timestamp":"2026-09-29T08:00:00.000Z","type":"event_msg","payload":{"type":"token_count",\
        "rate_limits":{"primary":{"used_percent":20,"window_minutes":300,"resets_at":1790700000},\
        "secondary":{"used_percent":55,"window_minutes":10080,"resets_at":1791000000},"plan_type":"plus"}}}
        """
        let snapshot = RateLimitParser.parseSessionEventLine(Data(line.utf8))
        XCTAssertEqual(snapshot?.menuBarTitle, "5h 80% · W 45%")
    }

    func testWindowWithoutDurationHasNoLabel() {
        let snapshot = UsageSnapshot(
            windows: [UsageWindow(label: "개인 한도", usedPercent: 10, windowDurationMinutes: nil, resetsAt: nil)],
            planType: nil,
            fetchedAt: Date()
        )
        XCTAssertEqual(snapshot.menuBarTitle, "90%")
    }
}
