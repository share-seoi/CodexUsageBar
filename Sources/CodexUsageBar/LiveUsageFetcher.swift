import Foundation

enum LiveUsageError: LocalizedError {
    case codexExecutableNotFound
    case launchFailed(String)
    case timedOut
    case processExited
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .codexExecutableNotFound:
            return "Codex 실행 파일을 찾을 수 없음"
        case .launchFailed(let message):
            return "Codex 실시간 조회 실행 실패: \(message)"
        case .timedOut:
            return "Codex 실시간 조회 시간 초과"
        case .processExited:
            return "Codex 실시간 조회 프로세스가 먼저 종료됨"
        case .server(let message):
            return "Codex 실시간 조회 실패: \(message)"
        case .invalidResponse:
            return "Codex 실시간 사용량 응답을 읽을 수 없음"
        }
    }
}

final class LiveUsageFetcher {
    private let queue = DispatchQueue(label: "local.mackim.CodexUsageBar.live-fetch")
    private let timeout: TimeInterval
    private var inFlight = false

    init(timeout: TimeInterval = 15) {
        self.timeout = timeout
    }

    @discardableResult
    func fetch(
        completion: @escaping (Result<UsageSnapshot, Error>) -> Void
    ) -> Bool {
        guard !inFlight else { return false }
        inFlight = true

        queue.async { [weak self] in
            guard let self else { return }
            let result = Result { try self.fetchSynchronously() }
            DispatchQueue.main.async {
                self.inFlight = false
                completion(result)
            }
        }
        return true
    }

    func fetchSynchronously() throws -> UsageSnapshot {
        guard let executablePath = CodexLocator.executablePath() else {
            throw LiveUsageError.codexExecutableNotFound
        }

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let responseState = LiveResponseState()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["app-server"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        let outputHandle = stdout.fileHandleForReading
        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            responseState.consume(data)
        }
        process.terminationHandler = { _ in
            responseState.resolve(.failure(LiveUsageError.processExited))
        }

        do {
            try process.run()
        } catch {
            outputHandle.readabilityHandler = nil
            throw LiveUsageError.launchFailed(error.localizedDescription)
        }

        defer {
            outputHandle.readabilityHandler = nil
            process.terminationHandler = nil
            try? stdin.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        let messages: [[String: Any]] = [
            [
                "method": "initialize",
                "id": 1,
                "params": [
                    "clientInfo": [
                        "name": "codex_usage_bar",
                        "title": "Codex Usage Bar",
                        "version": "1.1.0"
                    ]
                ]
            ],
            ["method": "initialized", "params": [:]],
            ["method": "account/rateLimits/read", "id": 2]
        ]

        for message in messages {
            guard let data = try? JSONSerialization.data(withJSONObject: message) else {
                continue
            }
            var line = data
            line.append(0x0A)
            stdin.fileHandleForWriting.write(line)
        }

        guard responseState.semaphore.wait(timeout: .now() + timeout) == .success else {
            throw LiveUsageError.timedOut
        }

        return try responseState.resolvedResult().get()
    }
}

private final class LiveResponseState {
    let semaphore = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var buffer = Data()
    private var result: Result<UsageSnapshot, Error>?

    func consume(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            lines.append(Data(buffer[..<newline]))
            buffer.removeSubrange(...newline)
        }
        lock.unlock()

        for line in lines {
            handle(line)
        }
    }

    func resolve(_ newResult: Result<UsageSnapshot, Error>) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = newResult
        lock.unlock()
        semaphore.signal()
    }

    func resolvedResult() -> Result<UsageSnapshot, Error> {
        lock.lock()
        defer { lock.unlock() }
        return result ?? .failure(LiveUsageError.invalidResponse)
    }

    private func handle(_ line: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: line),
            let root = object as? [String: Any],
            (root["id"] as? NSNumber)?.intValue == 2
        else {
            return
        }

        if let snapshot = RateLimitParser.parseResponseObject(root, fetchedAt: Date()) {
            resolve(.success(snapshot))
            return
        }

        if
            let error = root["error"] as? [String: Any],
            let message = error["message"] as? String
        {
            resolve(.failure(LiveUsageError.server(message)))
        } else {
            resolve(.failure(LiveUsageError.invalidResponse))
        }
    }
}
