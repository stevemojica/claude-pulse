import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Unix domain socket server for real-time agent session communication.
/// Uses raw POSIX sockets + DispatchSource — zero external dependencies.
public final class SocketServer: @unchecked Sendable {
    private let socketPath: String
    private var listenFd: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private var connections: [Int32: ClientConnection] = [:]
    private let queue = DispatchQueue(label: "com.claudepulse.socket", qos: .userInitiated)
    private let lock = NSLock()
    private weak var sessionManager: SessionManager?

    public init(sessionManager: SessionManager) throws {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudePulse", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.socketPath = dir.appendingPathComponent("pulse.sock").path
        self.sessionManager = sessionManager
    }

    public func start() {
        queue.async { [weak self] in
            self?.startListening()
        }
    }

    public func stop() {
        listenSource?.cancel()
        listenSource = nil

        lock.lock()
        let fds = Array(connections.keys)
        connections.removeAll()
        lock.unlock()

        for fd in fds { close(fd) }

        if listenFd >= 0 {
            close(listenFd)
            listenFd = -1
        }
        unlink(socketPath)
    }

    // MARK: - Listening

    private func startListening() {
        // Clean up stale socket file
        unlink(socketPath)

        listenFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFd >= 0 else {
            print("[ClaudePulse] Failed to create socket: \(String(cString: strerror(errno)))")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            print("[ClaudePulse] Socket path too long")
            close(listenFd)
            return
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                for (i, byte) in pathBytes.enumerated() { dest[i] = byte }
            }
        }

        let addrLen = socklen_t(MemoryLayout.offset(of: \sockaddr_un.sun_path)! + pathBytes.count)
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenFd, $0, addrLen)
            }
        }
        guard bindResult == 0 else {
            print("[ClaudePulse] Failed to bind: \(String(cString: strerror(errno)))")
            close(listenFd)
            return
        }

        // Set socket file to owner-only permissions (0600)
        chmod(socketPath, 0o600)

        guard listen(listenFd, 16) == 0 else {
            print("[ClaudePulse] Failed to listen: \(String(cString: strerror(errno)))")
            close(listenFd)
            return
        }

        // Set non-blocking
        let flags = fcntl(listenFd, F_GETFL)
        fcntl(listenFd, F_SETFL, flags | O_NONBLOCK)

        listenSource = DispatchSource.makeReadSource(fileDescriptor: listenFd, queue: queue)
        listenSource?.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        let fd = listenFd
        listenSource?.setCancelHandler {
            if fd >= 0 { close(fd) }
        }
        listenSource?.resume()

        print("[ClaudePulse] Socket server listening on \(socketPath)")
    }

    private func acceptConnection() {
        var clientAddr = sockaddr_un()
        var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let clientFd = withUnsafeMutablePointer(to: &clientAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                accept(listenFd, $0, &clientLen)
            }
        }
        guard clientFd >= 0 else { return }

        // Validate peer credentials (must be same user)
        #if canImport(Darwin)
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(clientFd, &uid, &gid) == 0 && uid == getuid() else {
            print("[ClaudePulse] Rejected connection from different user")
            close(clientFd)
            return
        }
        #endif

        let conn = ClientConnection(fd: clientFd, server: self)
        lock.lock()
        connections[clientFd] = conn
        lock.unlock()
        conn.start(on: queue)
    }

    // MARK: - Message Handling

    func handleMessage(_ message: SessionMessage, from clientFd: Int32) {
        guard SecurityPolicy.validateMessageContent(message) else {
            print("[ClaudePulse] Rejected message: failed security validation")
            return
        }
        Task { @MainActor [weak self] in
            self?.processMessage(message, clientFd: clientFd)
        }
    }

    @MainActor
    private func processMessage(_ message: SessionMessage, clientFd: Int32) {
        guard let sm = sessionManager else { return }
        let agent = AgentType(rawValue: message.agent ?? "claude_code") ?? .claudeCode

        switch message.type {
        case .sessionStart:
            guard let id = UUID(uuidString: message.sessionId) else { return }
            let terminal = TerminalInfo(
                pid: message.data?.pid,
                bundleIdentifier: message.data?.bundleIdentifier,
                tty: message.data?.tty
            )
            let session = AgentSession(
                id: id, agentType: agent, status: .working,
                terminalInfo: terminal,
                workingDirectory: message.data?.workingDirectory,
                isPassive: false
            )
            sm.addSession(session)

        case .statusUpdate:
            guard let id = UUID(uuidString: message.sessionId) else { return }
            let status = SessionStatus(rawValue: message.data?.status ?? "working") ?? .working
            sm.updateStatus(id: id, status: status, task: message.data?.task)

        case .permissionRequest:
            guard let id = UUID(uuidString: message.sessionId),
                  let toolName = message.data?.toolName else { return }
            let prompt = PermissionPrompt(
                toolName: toolName,
                description: message.data?.toolDescription ?? "",
                arguments: message.data?.arguments
            ) { [weak self] allowed in
                self?.sendPermissionResponse(sessionId: message.sessionId, allowed: allowed, to: clientFd)
            }
            sm.setPermissionPrompt(id: id, prompt: prompt)

        case .question:
            guard let id = UUID(uuidString: message.sessionId),
                  let text = message.data?.questionText else { return }
            sm.setQuestion(id: id, question: text)

        case .completed:
            guard let id = UUID(uuidString: message.sessionId) else { return }
            sm.updateStatus(id: id, status: .completed, task: message.data?.task)

        case .error:
            guard let id = UUID(uuidString: message.sessionId) else { return }
            sm.updateStatus(id: id, status: .errored, task: message.data?.errorMessage)
        }
    }

    private func sendPermissionResponse(sessionId: String, allowed: Bool, to clientFd: Int32) {
        let response = SessionResponse(sessionId: sessionId, type: .permissionResponse, allowed: allowed)
        guard let data = try? ProtocolValidator.encode(response) else { return }
        queue.async {
            _ = data.withUnsafeBytes { ptr in
                write(clientFd, ptr.baseAddress!, ptr.count)
            }
        }
    }

    func clientDisconnected(fd: Int32) {
        lock.lock()
        connections.removeValue(forKey: fd)
        lock.unlock()
        close(fd)
    }
}

// MARK: - Client Connection

private final class ClientConnection {
    let fd: Int32
    weak var server: SocketServer?
    private var readSource: DispatchSourceRead?
    private var buffer = Data()

    init(fd: Int32, server: SocketServer) {
        self.fd = fd
        self.server = server
    }

    func start(on queue: DispatchQueue) {
        let flags = fcntl(fd, F_GETFL)
        fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        readSource?.setEventHandler { [weak self] in
            self?.readAvailable()
        }
        readSource?.setCancelHandler {
            // fd is closed by server.clientDisconnected — do not double-close
        }
        readSource?.resume()
    }

    private func readAvailable() {
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(fd, &buf, buf.count)
        if n <= 0 {
            readSource?.cancel()
            server?.clientDisconnected(fd: fd)
            return
        }
        buffer.append(contentsOf: buf[0..<n])

        // Process complete newline-delimited messages
        while let newlineIdx = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newlineIdx]
            buffer = Data(buffer[(newlineIdx + 1)...])

            guard !lineData.isEmpty else { continue }
            do {
                let message = try ProtocolValidator.decode(Data(lineData))
                server?.handleMessage(message, from: fd)
            } catch {
                print("[ClaudePulse] Invalid message: \(error)")
            }
        }

        // Prevent buffer overflow
        if buffer.count > ProtocolValidator.maxMessageSize {
            buffer.removeAll()
        }
    }
}
