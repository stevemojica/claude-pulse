import Foundation

// MARK: - Wire Protocol

/// Messages sent over the Unix socket, newline-delimited JSON.
public struct SessionMessage: Codable, Sendable {
    public let type: MessageType
    public let sessionId: String
    public let agent: String?
    public let data: MessageData?

    public enum MessageType: String, Codable, Sendable {
        case sessionStart = "session_start"
        case statusUpdate = "status_update"
        case permissionRequest = "permission_request"
        case question = "question"
        case completed = "completed"
        case error = "error"
    }

    public struct MessageData: Codable, Sendable {
        // session_start
        public var pid: Int32?
        public var tty: String?
        public var workingDirectory: String?
        public var bundleIdentifier: String?

        // status_update
        public var status: String?
        public var task: String?

        // permission_request
        public var toolName: String?
        public var toolDescription: String?
        public var arguments: String?

        // question
        public var questionText: String?

        // error
        public var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case pid, tty, workingDirectory = "working_directory"
            case bundleIdentifier = "bundle_identifier"
            case status, task
            case toolName = "tool_name", toolDescription = "tool_description", arguments
            case questionText = "question_text"
            case errorMessage = "error_message"
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, sessionId = "session_id", agent, data
    }
}

/// Response sent back to the agent (e.g., permission decision).
public struct SessionResponse: Codable, Sendable {
    public let sessionId: String
    public let type: ResponseType
    public let allowed: Bool?

    public enum ResponseType: String, Codable, Sendable {
        case permissionResponse = "permission_response"
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id", type, allowed
    }
}

// MARK: - Security Validation

public enum ProtocolValidator {
    /// Maximum allowed message size (64KB).
    public static let maxMessageSize = 65_536

    /// Validate and decode a raw JSON line.
    public static func decode(_ data: Data) throws -> SessionMessage {
        guard data.count <= maxMessageSize else {
            throw ProtocolError.messageTooLarge(data.count)
        }
        return try JSONDecoder().decode(SessionMessage.self, from: data)
    }

    /// Encode a response to JSON data with newline terminator.
    public static func encode(_ response: SessionResponse) throws -> Data {
        var data = try JSONEncoder().encode(response)
        data.append(0x0A) // newline
        return data
    }

    public enum ProtocolError: Error, CustomStringConvertible {
        case messageTooLarge(Int)
        case invalidJSON(String)

        public var description: String {
            switch self {
            case .messageTooLarge(let size):
                return "Message too large: \(size) bytes (max \(maxMessageSize))"
            case .invalidJSON(let detail):
                return "Invalid JSON: \(detail)"
            }
        }
    }
}
