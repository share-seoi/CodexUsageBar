import Foundation
import Security

enum ClaudeLiveUsageError: LocalizedError {
    case credentialsNotFound
    case keychainDenied
    case keychainFailed(OSStatus)
    case invalidCredentials
    case tokenExpired
    case unauthorized
    case rateLimited(until: Date)
    case http(Int)
    case network(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .credentialsNotFound:
            return "Claude 로그인 정보가 키체인에 없음"
        case .keychainDenied:
            return "키체인 접근이 거부됨 (지금 새로고침으로 다시 요청)"
        case .keychainFailed(let status):
            return "키체인을 읽을 수 없음 (\(status))"
        case .invalidCredentials:
            return "Claude 로그인 정보를 읽을 수 없음"
        case .tokenExpired:
            return "Claude 로그인 토큰 만료 (Claude Code 사용 시 자동 갱신)"
        case .unauthorized:
            return "Claude 사용량 조회 권한 없음"
        case .rateLimited(let until):
            return "Claude 조회 제한 · \(Self.timeFormatter.string(from: until)) 이후 재시도"
        case .http(let status):
            return "Claude 사용량 조회 실패 (HTTP \(status))"
        case .network(let message):
            return "Claude 사용량 조회 실패: \(message)"
        case .invalidResponse:
            return "Claude 사용량 응답을 읽을 수 없음"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
        return formatter
    }()
}

struct ClaudeCredentials: Equatable {
    let accessToken: String
    let expiresAt: Date?
    let subscriptionType: String?

    func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now.addingTimeInterval(60)
    }

    static func parse(_ data: Data) -> ClaudeCredentials? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let root = object as? [String: Any]
        else {
            return nil
        }

        let oauth = root["claudeAiOauth"] as? [String: Any] ?? root
        guard let token = oauth["accessToken"] as? String, !token.isEmpty else {
            return nil
        }

        let expiresAt = (oauth["expiresAt"] as? NSNumber).map {
            Date(timeIntervalSince1970: $0.doubleValue / 1_000)
        }
        return ClaudeCredentials(
            accessToken: token,
            expiresAt: expiresAt,
            subscriptionType: oauth["subscriptionType"] as? String
        )
    }
}

/// Claude Code가 키체인에 저장한 로그인 토큰을 읽기만 해서, 사용량 탭과 같은 API로 5시간/주간 사용률을 조회한다.
/// 토큰을 갱신하거나 키체인에 쓰지 않는다(갱신하면 Claude Code 쪽 로그인이 풀릴 수 있음).
final class ClaudeLiveUsageFetcher: LiveUsageFetching {
    static let keychainService = "Claude Code-credentials"
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let queue = DispatchQueue(label: "local.mackim.CodexUsageBar.claude-live-fetch")
    private let session: URLSession
    private var inFlight = false

    // queue에서만 접근한다.
    private var cachedCredentials: ClaudeCredentials?
    private var keychainDenied = false
    private var retryAfter: Date?
    private var rateLimitBackoff: TimeInterval = 120

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// 거부된 키체인 요청은 사용자가 직접 새로고침했을 때만 다시 시도한다.
    @discardableResult
    func fetch(
        isManual: Bool,
        completion: @escaping (Result<UsageSnapshot, Error>) -> Void
    ) -> Bool {
        guard !inFlight else { return false }
        inFlight = true

        let finish: (Result<UsageSnapshot, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                self?.inFlight = false
                completion(result)
            }
        }

        queue.async { [weak self] in
            guard let self else { return }
            if isManual {
                self.keychainDenied = false
            }
            self.performFetch(finish: finish)
        }
        return true
    }

    private func performFetch(finish: @escaping (Result<UsageSnapshot, Error>) -> Void) {
        if let retryAfter, retryAfter > Date() {
            finish(.failure(ClaudeLiveUsageError.rateLimited(until: retryAfter)))
            return
        }

        let credentials: ClaudeCredentials
        do {
            credentials = try currentCredentials()
        } catch {
            finish(.failure(error))
            return
        }

        var request = URLRequest(url: Self.usageURL, timeoutInterval: 15)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexUsageBar/1.2", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            self.queue.async {
                finish(self.handle(
                    data: data,
                    response: response,
                    error: error,
                    planType: credentials.subscriptionType
                ))
            }
        }.resume()
    }

    private func handle(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        planType: String?
    ) -> Result<UsageSnapshot, Error> {
        if let error {
            return .failure(ClaudeLiveUsageError.network(error.localizedDescription))
        }
        guard let http = response as? HTTPURLResponse else {
            return .failure(ClaudeLiveUsageError.invalidResponse)
        }

        switch http.statusCode {
        case 200:
            retryAfter = nil
            rateLimitBackoff = 120
            guard
                let data,
                let snapshot = Self.parseUsage(data, fetchedAt: Date(), planType: planType)
            else {
                return .failure(ClaudeLiveUsageError.invalidResponse)
            }
            return .success(snapshot)
        case 401, 403:
            // Claude Code가 토큰을 새로 받았을 수 있으므로 다음 조회 때 키체인을 다시 읽는다.
            cachedCredentials = nil
            return .failure(ClaudeLiveUsageError.unauthorized)
        case 429:
            let headerDelay = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            let delay = headerDelay ?? rateLimitBackoff
            rateLimitBackoff = min(rateLimitBackoff * 2, 900)
            let until = Date().addingTimeInterval(delay)
            retryAfter = until
            return .failure(ClaudeLiveUsageError.rateLimited(until: until))
        default:
            return .failure(ClaudeLiveUsageError.http(http.statusCode))
        }
    }

    private func currentCredentials() throws -> ClaudeCredentials {
        if let cachedCredentials, !cachedCredentials.isExpired() {
            return cachedCredentials
        }
        guard !keychainDenied else {
            throw ClaudeLiveUsageError.keychainDenied
        }

        let data: Data
        do {
            data = try Self.readKeychainItem()
        } catch ClaudeLiveUsageError.keychainDenied {
            // 거부 후 주기 조회마다 확인 창이 다시 뜨지 않도록 수동 새로고침 전까지 멈춘다.
            keychainDenied = true
            throw ClaudeLiveUsageError.keychainDenied
        }

        guard let credentials = ClaudeCredentials.parse(data) else {
            throw ClaudeLiveUsageError.invalidCredentials
        }
        guard !credentials.isExpired() else {
            cachedCredentials = nil
            throw ClaudeLiveUsageError.tokenExpired
        }
        cachedCredentials = credentials
        return credentials
    }

    private static func readKeychainItem() throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw ClaudeLiveUsageError.invalidCredentials
            }
            return data
        case errSecItemNotFound:
            throw ClaudeLiveUsageError.credentialsNotFound
        case errSecAuthFailed, errSecUserCanceled:
            throw ClaudeLiveUsageError.keychainDenied
        default:
            throw ClaudeLiveUsageError.keychainFailed(status)
        }
    }

    static func parseUsage(_ data: Data, fetchedAt: Date, planType: String?) -> UsageSnapshot? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let root = object as? [String: Any]
        else {
            return nil
        }

        let windows = [
            window(root["five_hour"], label: "5시간 한도", minutes: 300),
            window(root["seven_day"], label: "주간 한도", minutes: 10_080)
        ].compactMap { $0 }

        guard !windows.isEmpty else {
            return nil
        }
        return UsageSnapshot(windows: windows, planType: planType, fetchedAt: fetchedAt)
    }

    private static func window(_ value: Any?, label: String, minutes: Int) -> UsageWindow? {
        guard
            let dictionary = value as? [String: Any],
            let utilization = (dictionary["utilization"] as? NSNumber)?.doubleValue
        else {
            return nil
        }

        return UsageWindow(
            label: label,
            usedPercent: Int(utilization.rounded()),
            windowDurationMinutes: minutes,
            resetsAt: (dictionary["resets_at"] as? String).flatMap(parseDate)
        )
    }

    private static func parseDate(_ string: String) -> Date? {
        if let date = fractionalDateFormatter.date(from: string) ?? plainDateFormatter.date(from: string) {
            return date
        }
        // 마이크로초 등 긴 소수 초는 잘라내고 다시 읽는다.
        let trimmed = string.replacingOccurrences(
            of: #"\.\d+"#,
            with: "",
            options: .regularExpression
        )
        return plainDateFormatter.date(from: trimmed)
    }

    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
