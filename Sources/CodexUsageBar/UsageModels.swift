import Foundation

struct UsageWindow: Codable, Equatable {
    let label: String
    let usedPercent: Int
    let windowDurationMinutes: Int?
    let resetsAt: Date?

    var remainingPercent: Int {
        max(0, min(100, 100 - usedPercent))
    }

    /// 메뉴 막대에 쓰는 짧은 이름 (5시간 → "5h", 주간 → "W").
    /// 한도 길이를 모르면("개인 한도" 등) 메뉴 막대에 넣기엔 길어서 nil.
    var shortLabel: String? {
        guard let minutes = windowDurationMinutes, minutes > 0 else {
            return nil
        }
        if minutes % 10_080 == 0 {
            return minutes == 10_080 ? "W" : "\(minutes / 10_080)W"
        }
        if minutes % 1_440 == 0 {
            return "\(minutes / 1_440)d"
        }
        if minutes % 60 == 0 {
            return "\(minutes / 60)h"
        }
        return "\(minutes)m"
    }
}

struct UsageSnapshot: Codable, Equatable {
    let windows: [UsageWindow]
    let planType: String?
    let fetchedAt: Date

    var overallRemainingPercent: Int {
        windows.map(\.remainingPercent).min() ?? 0
    }

    /// 한도마다 이름표를 붙여 보여준다: 주간만 있으면 "W 88%", 둘이면 "5h 63% · W 88%".
    var menuBarTitle: String {
        windows
            .map { window in
                let percent = "\(window.remainingPercent)%"
                return window.shortLabel.map { "\($0) \(percent)" } ?? percent
            }
            .joined(separator: " · ")
    }

    var menuBarToolTip: String {
        windows
            .map { "\($0.label) \($0.remainingPercent)% 남음" }
            .joined(separator: ", ")
    }

    func adjustedForCurrentTime(_ now: Date = Date()) -> UsageSnapshot {
        let adjustedWindows = windows.map { window in
            guard let resetsAt = window.resetsAt, resetsAt <= now else {
                return window
            }
            return UsageWindow(
                label: window.label,
                usedPercent: 0,
                windowDurationMinutes: window.windowDurationMinutes,
                resetsAt: nil
            )
        }

        return UsageSnapshot(
            windows: adjustedWindows,
            planType: planType,
            fetchedAt: fetchedAt
        )
    }
}

enum RateLimitParser {
    static func parseResponseLine(_ data: Data, fetchedAt: Date = Date()) -> UsageSnapshot? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let root = object as? [String: Any]
        else {
            return nil
        }

        return parseResponseObject(root, fetchedAt: fetchedAt)
    }

    static func parseResponseObject(
        _ root: [String: Any],
        fetchedAt: Date = Date()
    ) -> UsageSnapshot? {
        guard
            let result = root["result"] as? [String: Any],
            let snapshot = preferredSnapshot(in: result)
        else {
            return nil
        }

        var windows: [UsageWindow] = []
        if let primary = parseWindow(snapshot["primary"], fallbackLabel: "기본 한도") {
            windows.append(primary)
        }
        if let secondary = parseWindow(snapshot["secondary"], fallbackLabel: "보조 한도") {
            windows.append(secondary)
        }

        if windows.isEmpty,
           let individual = snapshot["individualLimit"] as? [String: Any],
           let remaining = intValue(individual["remainingPercent"]) {
            let resetsAt = intValue(individual["resetsAt"]).map {
                Date(timeIntervalSince1970: TimeInterval($0))
            }
            windows.append(
                UsageWindow(
                    label: "개인 한도",
                    usedPercent: 100 - remaining,
                    windowDurationMinutes: nil,
                    resetsAt: resetsAt
                )
            )
        }

        guard !windows.isEmpty else {
            return nil
        }

        windows.sort {
            ($0.windowDurationMinutes ?? Int.max) < ($1.windowDurationMinutes ?? Int.max)
        }

        return UsageSnapshot(
            windows: windows,
            planType: snapshot["planType"] as? String,
            fetchedAt: fetchedAt
        )
    }

    static func parseSessionEventLine(_ data: Data) -> UsageSnapshot? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let root = object as? [String: Any],
            let payload = root["payload"] as? [String: Any],
            payload["type"] as? String == "token_count",
            let snapshot = payload["rate_limits"] as? [String: Any]
        else {
            return nil
        }

        var windows: [UsageWindow] = []
        if let primary = parseSessionWindow(snapshot["primary"], fallbackLabel: "기본 한도") {
            windows.append(primary)
        }
        if let secondary = parseSessionWindow(snapshot["secondary"], fallbackLabel: "보조 한도") {
            windows.append(secondary)
        }

        guard !windows.isEmpty else {
            return nil
        }

        windows.sort {
            ($0.windowDurationMinutes ?? Int.max) < ($1.windowDurationMinutes ?? Int.max)
        }

        let fetchedAt = (root["timestamp"] as? String)
            .flatMap { sessionTimestampFormatter.date(from: $0) } ?? Date()

        return UsageSnapshot(
            windows: windows,
            planType: snapshot["plan_type"] as? String,
            fetchedAt: fetchedAt
        )
    }

    private static func preferredSnapshot(in result: [String: Any]) -> [String: Any]? {
        if
            let buckets = result["rateLimitsByLimitId"] as? [String: Any],
            let codex = buckets["codex"] as? [String: Any]
        {
            return codex
        }

        return result["rateLimits"] as? [String: Any]
    }

    private static func parseWindow(_ value: Any?, fallbackLabel: String) -> UsageWindow? {
        guard
            let dictionary = value as? [String: Any],
            let usedPercent = intValue(dictionary["usedPercent"])
        else {
            return nil
        }

        let duration = intValue(dictionary["windowDurationMins"])
        let resetsAt = intValue(dictionary["resetsAt"]).map {
            Date(timeIntervalSince1970: TimeInterval($0))
        }

        return UsageWindow(
            label: label(for: duration, fallback: fallbackLabel),
            usedPercent: usedPercent,
            windowDurationMinutes: duration,
            resetsAt: resetsAt
        )
    }

    private static func parseSessionWindow(_ value: Any?, fallbackLabel: String) -> UsageWindow? {
        guard
            let dictionary = value as? [String: Any],
            let usedPercent = intValue(dictionary["used_percent"])
        else {
            return nil
        }

        let duration = intValue(dictionary["window_minutes"])
        let resetsAt = intValue(dictionary["resets_at"]).map {
            Date(timeIntervalSince1970: TimeInterval($0))
        }

        return UsageWindow(
            label: label(for: duration, fallback: fallbackLabel),
            usedPercent: usedPercent,
            windowDurationMinutes: duration,
            resetsAt: resetsAt
        )
    }

    private static func label(for duration: Int?, fallback: String) -> String {
        guard let duration else {
            return fallback
        }

        switch duration {
        case 300:
            return "5시간 한도"
        case 1_440:
            return "일일 한도"
        case 10_080:
            return "주간 한도"
        default:
            if duration.isMultiple(of: 1_440) {
                return "\(duration / 1_440)일 한도"
            }
            if duration.isMultiple(of: 60) {
                return "\(duration / 60)시간 한도"
            }
            return fallback
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let value = value as? Int {
            return value
        }
        return nil
    }

    private static let sessionTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
