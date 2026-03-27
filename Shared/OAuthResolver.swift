import Foundation
import Security
import CryptoKit

public enum OAuthError: Error, CustomStringConvertible {
    case keychainItemNotFound
    case keychainError(OSStatus)
    case invalidData
    case tokenNotFound
    case tokenExpired

    public var description: String {
        switch self {
        case .keychainItemNotFound: "No Claude Code credentials found in Keychain"
        case .keychainError(let status): "Keychain error: \(status)"
        case .invalidData: "Could not decode Keychain data"
        case .tokenNotFound: "accessToken not found in credentials JSON"
        case .tokenExpired: "OAuth token has expired"
        }
    }
}

public struct OAuthResolver {
    public static func resolveToken() throws -> String {
        if let envToken = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"] {
            return envToken
        }
        let serviceName = buildServiceName()
        let raw = try readKeychain(service: serviceName)
        return try extractToken(from: raw)
    }

    private static func buildServiceName() -> String {
        let base = "Claude Code-credentials"
        guard let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] else {
            return base
        }
        let hash = sha256Prefix(of: configDir, length: 8)
        return "\(base)-\(hash)"
    }

    private static func sha256Prefix(of input: String, length: Int) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(length))
    }

    private static func readKeychain(service: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { throw OAuthError.keychainItemNotFound }
            throw OAuthError.keychainError(status)
        }
        guard let data = item as? Data, let raw = String(data: data, encoding: .utf8) else {
            throw OAuthError.invalidData
        }
        return raw
    }

    private static func extractToken(from raw: String) throws -> String {
        guard let data = raw.data(using: .utf8) else { throw OAuthError.invalidData }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let oauth: [String: Any]? =
            json?["claudeAiOauth"] as? [String: Any] ??
            json?[".claudeAiOauth"] as? [String: Any]
        guard let oauth, let token = oauth["accessToken"] as? String else {
            throw OAuthError.tokenNotFound
        }
        if let expiresAt = oauth["expiresAt"] as? Double {
            let nowMs = Date().timeIntervalSince1970 * 1000
            if expiresAt <= nowMs { throw OAuthError.tokenExpired }
        }
        return token
    }
}
