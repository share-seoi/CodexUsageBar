import Foundation

/// 앱 이름과 예전 이름(Codex Usage Bar)에서 넘어올 때 옮길 설정.
enum AppInfo {
    static let name = "CCusagebar"

    private static let legacyDefaultsDomain = "local.mackim.CodexUsageBar"
    private static let migratedKey = "migratedLegacyDefaults"
    private static let legacyKeys = ["lastActiveProvider", "lastUsageSnapshot", "lastClaudeUsageSnapshot", "showBoth"]

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// 번들 ID가 바뀌어 설정 저장소도 새로 생기므로, 예전 앱의 마지막 사용량·표시 설정을 한 번만 옮겨 온다.
    static func migrateLegacyDefaults(
        to defaults: UserDefaults = .standard,
        from legacyDefaults: UserDefaults? = UserDefaults(suiteName: legacyDefaultsDomain),
        log: (String) -> Void = Log.write
    ) {
        guard !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)
        guard let legacy = legacyDefaults else { return }
        var moved: [String] = []
        for key in legacyKeys where defaults.object(forKey: key) == nil {
            if let value = legacy.object(forKey: key) {
                defaults.set(value, forKey: key)
                moved.append(key)
            }
        }
        if !moved.isEmpty {
            log("예전 Codex Usage Bar 설정을 옮김: \(moved.joined(separator: ", "))")
        }
    }
}

/// 시작·종료·앱 실행/종료·연결 상태 전환 같은 드문 사건만 ~/Library/Logs/CCusagebar/log.txt에 한 줄씩 남긴다.
/// 주기 작업마다 쓰지 않으며, 256KB를 넘으면 log.old.txt 하나로 돌린다. 토큰이나 HTTP 본문은 기록하지 않는다.
/// Windows 버전(%LOCALAPPDATA%\CCusagebar\log.txt)과 같은 형식이다.
enum Log {
    private static let maxBytes: UInt64 = 256 * 1024
    private static let queue = DispatchQueue(label: "local.mackim.CCusagebar.log")
    private static let processID = ProcessInfo.processInfo.processIdentifier

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/\(AppInfo.name)", isDirectory: true)
    }

    static var fileURL: URL {
        directory.appendingPathComponent("log.txt")
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    static func write(_ message: String) {
        let now = Date()
        queue.async {
            let line = "\(timestampFormatter.string(from: now)) [\(processID)] "
                + message.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "\n    ")
                + "\n"
            append(line)
        }
    }

    /// 종료 직전처럼 곧 프로세스가 끝날 때는 기록이 끝날 때까지 기다린다.
    static func flush() {
        queue.sync {}
    }

    private static func append(_ line: String) {
        // 기록 실패로 앱이 멈추면 안 되므로 오류는 무시한다.
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if let size = (try? fileManager.attributesOfItem(atPath: fileURL.path))?[.size] as? UInt64, size > maxBytes {
                let old = directory.appendingPathComponent("log.old.txt")
                try? fileManager.removeItem(at: old)
                try fileManager.moveItem(at: fileURL, to: old)
            }
            let data = Data(line.utf8)
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: fileURL)
            }
        } catch {
        }
    }
}
