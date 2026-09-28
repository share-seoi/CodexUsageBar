import AppKit
import Darwin
import Foundation

if CommandLine.arguments.contains("--print-claude-live-usage") {
    ClaudeLiveUsageFetcher().fetch(isManual: true) { result in
        switch result {
        case .success(let snapshot):
            printSnapshot(snapshot, provider: .claude)
            exit(EXIT_SUCCESS)
        case .failure(let error):
            fputs("[CodexUsageBar] \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
    dispatchMain()
} else if CommandLine.arguments.contains("--print-claude-usage") {
    do {
        guard let snapshot = try ClaudeUsageStore().latestSnapshot() else {
            fputs("Claude 사용량 기록을 찾을 수 없습니다.\n", stderr)
            exit(EXIT_FAILURE)
        }
        printSnapshot(snapshot, provider: .claude)
        exit(EXIT_SUCCESS)
    } catch {
        fputs("[CodexUsageBar] \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
} else if CommandLine.arguments.contains("--print-live-usage") {
    do {
        let snapshot = try LiveUsageFetcher().fetchSynchronously()
        printSnapshot(snapshot)
        exit(EXIT_SUCCESS)
    } catch {
        fputs("[CodexUsageBar] \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
} else if CommandLine.arguments.contains("--print-usage") {
    do {
        guard let snapshot = try LocalUsageStore().latestSnapshot() else {
            fputs("Codex 사용량 기록을 찾을 수 없습니다.\n", stderr)
            exit(EXIT_FAILURE)
        }
        printSnapshot(snapshot)
        exit(EXIT_SUCCESS)
    } catch {
        fputs("[CodexUsageBar] \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

private func printSnapshot(_ snapshot: UsageSnapshot, provider: UsageProvider = .codex) {
    let details = snapshot.windows
        .map { "\($0.label)=\($0.remainingPercent)%" }
        .joined(separator: ", ")
    print("\(provider.displayName) 남은 사용량 \(snapshot.overallRemainingPercent)% (\(details))")
}
