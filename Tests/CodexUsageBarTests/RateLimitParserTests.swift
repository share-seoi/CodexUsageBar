import Foundation
import XCTest
@testable import CodexUsageBar

final class RateLimitParserTests: XCTestCase {
    func testParsesCodexBucketAndUsesMostConstrainedRemainingPercentage() throws {
        let json = """
        {
          "id": 2,
          "result": {
            "rateLimits": {
              "primary": { "usedPercent": 1, "windowDurationMins": 300, "resetsAt": 1780000000 }
            },
            "rateLimitsByLimitId": {
              "codex": {
                "primary": { "usedPercent": 35, "windowDurationMins": 300, "resetsAt": 1780000000 },
                "secondary": { "usedPercent": 60, "windowDurationMins": 10080, "resetsAt": 1780500000 },
                "planType": "pro"
              }
            }
          }
        }
        """

        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = try XCTUnwrap(
            RateLimitParser.parseResponseLine(Data(json.utf8), fetchedAt: fetchedAt)
        )

        XCTAssertEqual(snapshot.planType, "pro")
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
        XCTAssertEqual(snapshot.overallRemainingPercent, 40)
        XCTAssertEqual(snapshot.windows.map(\.label), ["5시간 한도", "주간 한도"])
        XCTAssertEqual(snapshot.windows.map(\.remainingPercent), [65, 40])
    }

    func testFallsBackToLegacyRateLimitSnapshot() throws {
        let json = """
        {
          "id": 2,
          "result": {
            "rateLimits": {
              "primary": { "usedPercent": 12, "windowDurationMins": 10080, "resetsAt": null },
              "planType": "plus"
            }
          }
        }
        """

        let snapshot = try XCTUnwrap(RateLimitParser.parseResponseLine(Data(json.utf8)))
        XCTAssertEqual(snapshot.overallRemainingPercent, 88)
        XCTAssertEqual(snapshot.windows.first?.label, "주간 한도")
        XCTAssertEqual(snapshot.planType, "plus")
    }

    func testParsesLocalSessionRateLimitEvent() throws {
        let json = """
        {
          "timestamp": "2026-07-15T05:30:17.678Z",
          "type": "event_msg",
          "payload": {
            "type": "token_count",
            "rate_limits": {
              "limit_id": "codex",
              "primary": {
                "used_percent": 23.0,
                "window_minutes": 10080,
                "resets_at": 1880000000
              },
              "secondary": null,
              "plan_type": "pro"
            }
          }
        }
        """

        let snapshot = try XCTUnwrap(
            RateLimitParser.parseSessionEventLine(Data(json.utf8))
        )
        XCTAssertEqual(snapshot.overallRemainingPercent, 77)
        XCTAssertEqual(snapshot.windows.first?.label, "주간 한도")
        XCTAssertEqual(snapshot.planType, "pro")
    }

    func testExpiredWindowIsShownAsFullyReset() {
        let snapshot = UsageSnapshot(
            windows: [
                UsageWindow(
                    label: "5시간 한도",
                    usedPercent: 90,
                    windowDurationMinutes: 300,
                    resetsAt: Date(timeIntervalSince1970: 100)
                )
            ],
            planType: "pro",
            fetchedAt: Date(timeIntervalSince1970: 50)
        )

        let adjusted = snapshot.adjustedForCurrentTime(Date(timeIntervalSince1970: 200))
        XCTAssertEqual(adjusted.overallRemainingPercent, 100)
        XCTAssertNil(adjusted.windows.first?.resetsAt)
    }
}
