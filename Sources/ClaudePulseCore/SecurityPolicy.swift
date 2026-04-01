import Foundation

/// Security validation utilities for the Claude Pulse socket server and data handling.
public enum SecurityPolicy {

    /// Validate that a socket file has owner-only permissions (0600).
    public static func validateSocketPermissions(at path: String) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let posix = attrs[.posixPermissions] as? Int else { return false }
        // 0600 = owner read/write only
        return posix & 0o077 == 0
    }

    /// Set secure permissions on a file (owner read/write only).
    public static func setSecurePermissions(at path: String) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: path
        )
    }

    /// Sanitize a string for safe display (remove control characters).
    public static func sanitize(_ string: String) -> String {
        string.unicodeScalars
            .filter { !$0.properties.isDefaultIgnorableCodePoint && ($0.value >= 32 || $0 == "\n" || $0 == "\t") }
            .map { String($0) }
            .joined()
    }

    /// Validate that a JSON message doesn't contain obviously malicious content.
    /// This is defense-in-depth — the Codable parser already prevents injection,
    /// but we add an extra layer of validation for display strings.
    public static func validateMessageContent(_ message: SessionMessage) -> Bool {
        // Check tool name doesn't contain shell metacharacters
        if let toolName = message.data?.toolName {
            let forbidden: CharacterSet = .init(charactersIn: ";|&`$(){}[]!<>")
            if toolName.unicodeScalars.contains(where: { forbidden.contains($0) }) {
                return false
            }
        }

        // Check session ID is a valid UUID
        if UUID(uuidString: message.sessionId) == nil {
            return false
        }

        return true
    }
}
