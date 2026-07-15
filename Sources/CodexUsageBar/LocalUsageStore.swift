import Foundation
import SQLite3

enum LocalUsageStoreError: LocalizedError {
    case stateDatabaseNotFound
    case databaseOpenFailed
    case queryFailed

    var errorDescription: String? {
        switch self {
        case .stateDatabaseNotFound:
            return "Codex 상태 DB를 찾을 수 없음"
        case .databaseOpenFailed:
            return "Codex 상태 DB를 열 수 없음"
        case .queryFailed:
            return "최근 Codex 세션을 찾을 수 없음"
        }
    }
}

struct LocalUsageStore {
    private let fileManager: FileManager
    private let codexHome: URL
    private let maximumTailBytes: UInt64 = 512 * 1_024

    init(
        fileManager: FileManager = .default,
        codexHome: URL? = nil
    ) {
        self.fileManager = fileManager
        self.codexHome = codexHome
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    func latestSnapshot() throws -> UsageSnapshot? {
        let paths = try recentRolloutPaths(limit: 12)

        for path in paths {
            if let snapshot = try? latestSnapshot(in: URL(fileURLWithPath: path)) {
                return snapshot.adjustedForCurrentTime()
            }
        }

        return nil
    }

    private func recentRolloutPaths(limit: Int) throws -> [String] {
        guard let databaseURL = stateDatabaseURL() else {
            throw LocalUsageStoreError.stateDatabaseNotFound
        }

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
              let database else {
            sqlite3_close(database)
            throw LocalUsageStoreError.databaseOpenFailed
        }
        defer { sqlite3_close(database) }

        sqlite3_busy_timeout(database, 250)

        let sql = """
        SELECT rollout_path
        FROM threads
        WHERE rollout_path IS NOT NULL AND rollout_path != ''
        ORDER BY recency_at_ms DESC, updated_at_ms DESC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw LocalUsageStoreError.queryFailed
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(limit))

        var paths: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0) else { continue }
            paths.append(String(cString: text))
        }

        guard !paths.isEmpty else {
            throw LocalUsageStoreError.queryFailed
        }
        return paths
    }

    private func stateDatabaseURL() -> URL? {
        let preferred = codexHome.appendingPathComponent("state_5.sqlite")
        if fileManager.fileExists(atPath: preferred.path) {
            return preferred
        }

        guard let files = try? fileManager.contentsOfDirectory(
            at: codexHome,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return files
            .filter { $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" }
            .max {
                let leftValues = try? $0.resourceValues(forKeys: [.contentModificationDateKey])
                let rightValues = try? $1.resourceValues(forKeys: [.contentModificationDateKey])
                let left = leftValues?.contentModificationDate ?? .distantPast
                let right = rightValues?.contentModificationDate ?? .distantPast
                return left < right
            }
    }

    private func latestSnapshot(in fileURL: URL) throws -> UsageSnapshot? {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        let offset = fileSize > maximumTailBytes ? fileSize - maximumTailBytes : 0
        try handle.seek(toOffset: offset)
        guard var data = try handle.readToEnd(), !data.isEmpty else {
            return nil
        }

        if offset > 0, let firstNewline = data.firstIndex(of: 0x0A) {
            data.removeSubrange(...firstNewline)
        }

        let marker = Data("\"rate_limits\"".utf8)
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true).reversed() {
            let lineData = Data(line)
            guard lineData.range(of: marker) != nil else { continue }
            if let snapshot = RateLimitParser.parseSessionEventLine(lineData) {
                return snapshot
            }
        }

        return nil
    }
}
