import CommonCrypto
import Foundation
import Security

/// Claude 데스크톱 앱이 저장한 로그인 토큰(config.json의 oauth:tokenCacheV2)을 읽기만 한다.
/// Electron safeStorage(macOS) 형식: 키체인 "Claude Safe Storage" 암호 → PBKDF2 → "v10" AES-128-CBC.
/// 토큰 갱신은 Claude 앱이 하므로 여기서는 갱신하거나 파일·키체인에 쓰지 않는다.
enum ClaudeDesktopToken {
    static let keychainService = "Claude Safe Storage"
    static let cacheKey = "oauth:tokenCacheV2"

    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/config.json")
    }

    /// 데스크톱 앱 로그인 정보가 없으면 nil. 만료되지 않은 토큰 중 가장 늦게 만료되는 것을 고르고,
    /// 모두 만료됐으면 가장 최근 것을 돌려준다.
    static func read() throws -> ClaudeCredentials? {
        guard
            let data = try? Data(contentsOf: configURL),
            let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let blob = config[cacheKey] as? String,
            !blob.isEmpty
        else {
            return nil
        }

        let password = try readKeychainPassword()
        let plaintext = try decrypt(encryptedBytes(blob), password: password)
        let entries = parseEntries(plaintext)
        guard !entries.isEmpty else {
            throw ClaudeLiveUsageError.invalidCredentials
        }
        return pick(entries)
    }

    static func pick(_ entries: [ClaudeCredentials], now: Date = Date()) -> ClaudeCredentials? {
        let valid = entries.filter { !$0.isExpired(now: now) }
        if !valid.isEmpty {
            return valid.max { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
        }
        return entries.max { ($0.expiresAt ?? .distantPast) < ($1.expiresAt ?? .distantPast) }
    }

    /// 복호화된 캐시: { "<계정/범위 키>": { "token": "...", "expiresAt": <ms>, ... }, ... }
    static func parseEntries(_ data: Data) -> [ClaudeCredentials] {
        guard let cache = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return cache.values.compactMap { value in
            guard
                let entry = value as? [String: Any],
                let token = (entry["token"] ?? entry["accessToken"]) as? String,
                !token.isEmpty
            else {
                return nil
            }
            let expiresAt = (entry["expiresAt"] as? NSNumber).map {
                Date(timeIntervalSince1970: $0.doubleValue / 1_000)
            }
            return ClaudeCredentials(
                accessToken: token,
                expiresAt: expiresAt,
                subscriptionType: entry["subscriptionType"] as? String
            )
        }
    }

    /// config.json에는 base64로 저장된다. 혹시 원본 바이트 문자열이면 그대로 쓴다.
    private static func encryptedBytes(_ blob: String) -> Data {
        if let decoded = Data(base64Encoded: blob), decoded.starts(with: Data("v1".utf8)) {
            return decoded
        }
        return Data(blob.utf8)
    }

    static func decrypt(_ blob: Data, password: Data) throws -> Data {
        let prefix = Data("v10".utf8)
        guard blob.count > prefix.count, blob.starts(with: prefix) else {
            throw ClaudeLiveUsageError.desktopFormat
        }
        let cipher = blob.dropFirst(prefix.count)

        let salt = Data("saltysalt".utf8)
        var key = Data(count: kCCKeySizeAES128)
        let deriveStatus = key.withUnsafeMutableBytes { keyBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                        password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        kCCKeySizeAES128
                    )
                }
            }
        }
        guard deriveStatus == kCCSuccess else {
            throw ClaudeLiveUsageError.desktopFormat
        }

        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(count: cipher.count + kCCBlockSizeAES128)
        var written = 0
        let outputCapacity = output.count
        let status = output.withUnsafeMutableBytes { outputBytes in
            cipher.withUnsafeBytes { cipherBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, kCCKeySizeAES128,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress, cipher.count,
                            outputBytes.baseAddress, outputCapacity,
                            &written
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            throw ClaudeLiveUsageError.desktopFormat
        }
        return output.prefix(written)
    }

    private static func readKeychainPassword() throws -> Data {
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
}
