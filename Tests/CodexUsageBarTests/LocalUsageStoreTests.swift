import Foundation
import XCTest
@testable import CodexUsageBar

final class LocalUsageStoreTests: XCTestCase {
    func testChoosesNewestRateLimitEventAcrossRecentPaths() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let older = directory.appendingPathComponent("older.jsonl")
        let newer = directory.appendingPathComponent("newer.jsonl")
        try sessionEvent(timestamp: "2026-07-16T01:00:00.000Z", usedPercent: 12)
            .write(to: older, atomically: true, encoding: .utf8)
        try sessionEvent(timestamp: "2026-07-16T02:00:00.000Z", usedPercent: 34)
            .write(to: newer, atomically: true, encoding: .utf8)

        let snapshot = try XCTUnwrap(
            LocalUsageStore(codexHome: directory)
                .newestSnapshot(in: [older.path, newer.path])
        )

        XCTAssertEqual(snapshot.windows.first?.usedPercent, 34)
        XCTAssertEqual(snapshot.overallRemainingPercent, 66)
    }

    private func sessionEvent(timestamp: String, usedPercent: Int) -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":\(usedPercent),"window_minutes":10080,"resets_at":1880000000},"secondary":null,"plan_type":"pro"}}}
        """
    }
}
