import Foundation
import XCTest
@testable import CCusagebar

final class LegacyDefaultsTests: XCTestCase {
    func testMigrationCopiesMissingKeysOnce() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let legacy = UserDefaults(suiteName: UUID().uuidString)!
        legacy.set("codex", forKey: "lastActiveProvider")
        legacy.set(true, forKey: "showBoth")
        defaults.set(false, forKey: "showBoth")
        var logged: [String] = []

        AppInfo.migrateLegacyDefaults(to: defaults, from: legacy) { logged.append($0) }

        XCTAssertEqual(defaults.string(forKey: "lastActiveProvider"), "codex")
        XCTAssertFalse(defaults.bool(forKey: "showBoth"), "새 앱에 이미 있는 값은 덮어쓰지 않는다")
        XCTAssertEqual(logged, ["예전 Codex Usage Bar 설정을 옮김: lastActiveProvider"])

        legacy.set("claude", forKey: "lastActiveProvider")
        defaults.removeObject(forKey: "lastActiveProvider")
        AppInfo.migrateLegacyDefaults(to: defaults, from: legacy) { logged.append($0) }
        XCTAssertNil(defaults.string(forKey: "lastActiveProvider"), "두 번째 실행에서는 옮기지 않는다")
    }
}
