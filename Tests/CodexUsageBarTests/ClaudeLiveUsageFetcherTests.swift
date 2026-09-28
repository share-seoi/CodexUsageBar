import Foundation
import XCTest
@testable import CodexUsageBar

final class ClaudeLiveUsageFetcherTests: XCTestCase {
    func testParsesUsageResponseWithResetTimes() throws {
        let json = """
        {
          "five_hour": { "utilization": 37.4, "resets_at": "2026-09-28T15:00:00.123456+00:00" },
          "seven_day": { "utilization": 12.0, "resets_at": "2026-10-02T03:00:00+00:00" },
          "seven_day_opus": null
        }
        """
        let fetchedAt = Date(timeIntervalSince1970: 1_790_600_000)

        let snapshot = try XCTUnwrap(
            ClaudeLiveUsageFetcher.parseUsage(Data(json.utf8), fetchedAt: fetchedAt, planType: "max")
        )

        XCTAssertEqual(snapshot.planType, "max")
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
        XCTAssertEqual(snapshot.windows.map(\.label), ["5시간 한도", "주간 한도"])
        XCTAssertEqual(snapshot.windows.map(\.remainingPercent), [63, 88])
        XCTAssertEqual(
            snapshot.windows.first?.resetsAt?.timeIntervalSince1970 ?? 0,
            1_790_607_600,
            accuracy: 1
        )
        XCTAssertEqual(snapshot.windows.last?.resetsAt?.timeIntervalSince1970, 1_790_910_000)
    }

    func testWindowWithoutResetTimeIsStillShown() throws {
        let json = #"{"five_hour":{"utilization":0,"resets_at":null},"seven_day":null}"#
        let snapshot = try XCTUnwrap(
            ClaudeLiveUsageFetcher.parseUsage(Data(json.utf8), fetchedAt: Date(), planType: nil)
        )
        XCTAssertEqual(snapshot.overallRemainingPercent, 100)
        XCTAssertNil(snapshot.windows.first?.resetsAt)
    }

    func testErrorResponseIsNotASnapshot() {
        let json = #"{"error":{"type":"rate_limit_error","message":"Rate limited."}}"#
        XCTAssertNil(ClaudeLiveUsageFetcher.parseUsage(Data(json.utf8), fetchedAt: Date(), planType: nil))
    }

    func testParsesClaudeCodeCredentials() throws {
        let json = """
        {"claudeAiOauth":{"accessToken":"test-token","refreshToken":"test-refresh",\
        "expiresAt":1790600000000,"scopes":["user:inference"],"subscriptionType":"max"}}
        """
        let credentials = try XCTUnwrap(ClaudeCredentials.parse(Data(json.utf8)))

        XCTAssertEqual(credentials.accessToken, "test-token")
        XCTAssertEqual(credentials.subscriptionType, "max")
        XCTAssertFalse(credentials.isExpired(now: Date(timeIntervalSince1970: 1_790_590_000)))
        XCTAssertTrue(credentials.isExpired(now: Date(timeIntervalSince1970: 1_790_599_990)))
    }

    func testMissingAccessTokenIsRejected() {
        XCTAssertNil(ClaudeCredentials.parse(Data(#"{"claudeAiOauth":{}}"#.utf8)))
    }
}
