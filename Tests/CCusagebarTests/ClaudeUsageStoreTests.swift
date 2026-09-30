import Foundation
import XCTest
@testable import CCusagebar

final class ClaudeUsageStoreTests: XCTestCase {
    private let history = """
    {
      "version": 2,
      "samples": [
        { "t": 1790598357750, "org": "org-1", "u": { "fh": 5, "sd": 1 } },
        { "t": 1790601957750, "org": "org-1", "u": { "fh": 42, "sd": 17.6 } },
        { "t": 1790599557750, "org": "org-1", "u": { "fh": 3, "sd": 1 } }
      ]
    }
    """

    func testUsesNewestSampleAndReportsRemainingPercent() throws {
        let sampledAt = Date(timeIntervalSince1970: 1_790_601_957.75)
        let snapshot = try XCTUnwrap(
            ClaudeUsageStore.parseHistory(Data(history.utf8), now: sampledAt.addingTimeInterval(60))
        )

        XCTAssertEqual(snapshot.fetchedAt, sampledAt)
        XCTAssertEqual(snapshot.windows.map(\.label), ["5시간 한도", "주간 한도"])
        XCTAssertEqual(snapshot.windows.map(\.remainingPercent), [58, 82])
        XCTAssertEqual(snapshot.overallRemainingPercent, 58)
        XCTAssertNil(snapshot.planType)
    }

    func testFiveHourWindowIsResetWhenSampleIsOlderThanFiveHours() throws {
        let sampledAt = Date(timeIntervalSince1970: 1_790_601_957.75)
        let snapshot = try XCTUnwrap(
            ClaudeUsageStore.parseHistory(
                Data(history.utf8),
                now: sampledAt.addingTimeInterval(6 * 3_600)
            )
        )

        XCTAssertEqual(snapshot.windows.map(\.remainingPercent), [100, 82])
    }

    func testEmptyHistoryHasNoSnapshot() throws {
        let empty = #"{"version":2,"samples":[]}"#
        XCTAssertNil(try ClaudeUsageStore.parseHistory(Data(empty.utf8)))
    }

    func testInvalidHistoryThrows() {
        XCTAssertThrowsError(try ClaudeUsageStore.parseHistory(Data("nope".utf8)))
    }
}
