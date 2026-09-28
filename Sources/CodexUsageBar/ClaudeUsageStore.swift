import Foundation

enum ClaudeUsageStoreError: LocalizedError {
    case historyNotFound
    case invalidHistory

    var errorDescription: String? {
        switch self {
        case .historyNotFound:
            return "Claude 사용량 기록 파일을 찾을 수 없음"
        case .invalidHistory:
            return "Claude 사용량 기록을 읽을 수 없음"
        }
    }
}

/// Claude 데스크톱 앱이 직접 기록하는 `plan-usage-history.json`에서 최신 사용률을 읽는다.
/// 로그인 토큰이나 네트워크 요청을 사용하지 않는다.
struct ClaudeUsageStore {
    private static let fiveHourMinutes = 300
    private static let sevenDayMinutes = 10_080

    private let historyURL: URL

    init(
        fileManager: FileManager = .default,
        historyURL: URL? = nil
    ) {
        self.historyURL = historyURL
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
    }

    func latestSnapshot(now: Date = Date()) throws -> UsageSnapshot? {
        let data: Data
        do {
            data = try Data(contentsOf: historyURL)
        } catch {
            throw ClaudeUsageStoreError.historyNotFound
        }
        return try Self.parseHistory(data, now: now)
    }

    static func parseHistory(_ data: Data, now: Date = Date()) throws -> UsageSnapshot? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let root = object as? [String: Any],
            let samples = root["samples"] as? [[String: Any]]
        else {
            throw ClaudeUsageStoreError.invalidHistory
        }

        let latest = samples
            .compactMap { sample -> (Date, [String: Any])? in
                guard
                    let milliseconds = (sample["t"] as? NSNumber)?.doubleValue,
                    let usage = sample["u"] as? [String: Any]
                else {
                    return nil
                }
                return (Date(timeIntervalSince1970: milliseconds / 1_000), usage)
            }
            .max { $0.0 < $1.0 }

        guard let (sampledAt, usage) = latest else {
            return nil
        }

        let windows = [
            window(usage["fh"], label: "5시간 한도", minutes: fiveHourMinutes, sampledAt: sampledAt, now: now),
            window(usage["sd"], label: "주간 한도", minutes: sevenDayMinutes, sampledAt: sampledAt, now: now)
        ].compactMap { $0 }

        guard !windows.isEmpty else {
            return nil
        }

        return UsageSnapshot(windows: windows, planType: nil, fetchedAt: sampledAt)
    }

    // 기록에는 초기화 시각이 없으므로, 기록 이후 한도 길이만큼 지났다면 그 구간은 이미 초기화된 것으로 본다.
    private static func window(
        _ value: Any?,
        label: String,
        minutes: Int,
        sampledAt: Date,
        now: Date
    ) -> UsageWindow? {
        guard let utilization = (value as? NSNumber)?.doubleValue else {
            return nil
        }
        let expired = now.timeIntervalSince(sampledAt) >= TimeInterval(minutes * 60)
        return UsageWindow(
            label: label,
            usedPercent: expired ? 0 : Int(utilization.rounded()),
            windowDurationMinutes: minutes,
            resetsAt: nil
        )
    }
}
