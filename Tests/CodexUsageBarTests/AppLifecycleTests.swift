import XCTest
@testable import CodexUsageBar

final class AppLifecycleTests: XCTestCase {
    func testRecognizesCodexAndClaudeBundleIdentifiers() {
        XCTAssertEqual(
            AppLifecycle.providers(
                in: ["com.apple.finder", "com.openai.codex", "com.anthropic.claudefordesktop"]
            ),
            [.codex, .claude]
        )
    }

    func testDoesNotMistakeUsageBarForTrackedApp() {
        XCTAssertTrue(
            AppLifecycle.providers(in: ["local.mackim.CodexUsageBar", nil]).isEmpty
        )
    }

    func testFrontmostTrackedAppWins() {
        XCTAssertEqual(
            AppLifecycle.preferredProvider(
                frontmost: .claude,
                running: [.codex, .claude],
                previous: .codex
            ),
            .claude
        )
    }

    func testKeepsPreviousAppWhileAnotherAppIsFrontmost() {
        XCTAssertEqual(
            AppLifecycle.preferredProvider(
                frontmost: nil,
                running: [.codex, .claude],
                previous: .claude
            ),
            .claude
        )
    }

    func testSwitchesToRemainingAppWhenPreviousAppQuits() {
        XCTAssertEqual(
            AppLifecycle.preferredProvider(
                frontmost: nil,
                running: [.codex],
                previous: .claude
            ),
            .codex
        )
    }
}
