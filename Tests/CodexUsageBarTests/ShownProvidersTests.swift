import XCTest
@testable import CodexUsageBar

final class ShownProvidersTests: XCTestCase {
    func testAutoSwitchShowsOnlyActiveApp() {
        let shown = UsageBoardModel.shownProviders(showBoth: false, active: .claude) { _ in true }
        XCTAssertEqual(shown, [.claude])
    }

    func testShowBothPutsCodexLeftOfClaude() {
        let shown = UsageBoardModel.shownProviders(showBoth: true, active: .claude) { _ in true }
        XCTAssertEqual(shown, [.codex, .claude])
    }

    func testShowBothWaitsForBothSnapshots() {
        let shown = UsageBoardModel.shownProviders(showBoth: true, active: .codex) { $0 == .codex }
        XCTAssertEqual(shown, [.codex])
    }
}
