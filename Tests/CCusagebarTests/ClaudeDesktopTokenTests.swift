import CommonCrypto
import Foundation
import XCTest
@testable import CCusagebar

final class ClaudeDesktopTokenTests: XCTestCase {
    func testDecryptsElectronSafeStorageBlob() throws {
        let password = Data("test-password".utf8)
        let plaintext = Data(#"{"a":{"token":"desktop-token","expiresAt":1790600000000}}"#.utf8)

        let decrypted = try ClaudeDesktopToken.decrypt(encrypt(plaintext, password: password), password: password)

        XCTAssertEqual(decrypted, plaintext)
    }

    func testRejectsBlobWithoutVersionPrefix() {
        XCTAssertThrowsError(try ClaudeDesktopToken.decrypt(Data("garbage".utf8), password: Data("p".utf8)))
    }

    func testPicksLatestValidToken() throws {
        let json = """
        {
          "old": {"token":"old-token","expiresAt":1790500000000},
          "new": {"token":"new-token","expiresAt":1790700000000},
          "empty": {"expiresAt":1790800000000}
        }
        """
        let entries = ClaudeDesktopToken.parseEntries(Data(json.utf8))
        XCTAssertEqual(entries.count, 2)

        let now = Date(timeIntervalSince1970: 1_790_600_000)
        XCTAssertEqual(ClaudeDesktopToken.pick(entries, now: now)?.accessToken, "new-token")

        let later = Date(timeIntervalSince1970: 1_790_800_000)
        let fallback = try XCTUnwrap(ClaudeDesktopToken.pick(entries, now: later))
        XCTAssertEqual(fallback.accessToken, "new-token")
        XCTAssertTrue(fallback.isExpired(now: later))
    }

    private func encrypt(_ plaintext: Data, password: Data) -> Data {
        let salt = Data("saltysalt".utf8)
        var key = Data(count: kCCKeySizeAES128)
        _ = key.withUnsafeMutableBytes { keyBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self), password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                        keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), kCCKeySizeAES128
                    )
                }
            }
        }
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(count: plaintext.count + kCCBlockSizeAES128)
        var written = 0
        let capacity = output.count
        _ = output.withUnsafeMutableBytes { outputBytes in
            plaintext.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, kCCKeySizeAES128, ivBytes.baseAddress,
                            inputBytes.baseAddress, plaintext.count,
                            outputBytes.baseAddress, capacity, &written
                        )
                    }
                }
            }
        }
        return Data("v10".utf8) + output.prefix(written)
    }
}
