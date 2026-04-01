import Foundation

/// Watches Claude Code's JSONL conversation logs for sessions not using the socket hook.
/// This is a fallback — provides status updates but no interactive permission relay.
public final class LogWatcher: @unchecked Sendable {
    private let sessionManager: SessionManager
    private var watchedFiles: [String: FileState] = [:]
    private var timer: Timer?
    private let claudeDir: String
    private let lock = NSLock()

    private struct FileState {
        var lastOffset: UInt64
        var sessionId: UUID
    }

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
        self.claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects").path
    }

    public func start() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scanForChanges()
            self.timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.scanForChanges()
            }
        }
    }

    public func stop() {
        DispatchQueue.main.async { [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
        }
    }

    private func scanForChanges() {
        guard FileManager.default.fileExists(atPath: claudeDir) else { return }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: claudeDir) else { return }

        let cutoff = Date().addingTimeInterval(-3600)

        while let relativePath = enumerator.nextObject() as? String {
            guard relativePath.hasSuffix(".jsonl") else { continue }
            let fullPath = (claudeDir as NSString).appendingPathComponent(relativePath)

            guard let attrs = try? fm.attributesOfItem(atPath: fullPath),
                  let modDate = attrs[.modificationDate] as? Date,
                  modDate > cutoff else { continue }

            processFile(at: fullPath)
        }
    }

    private func processFile(at path: String) {
        let fileSize: UInt64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            fileSize = attrs[.size] as? UInt64 ?? 0
        } catch { return }

        lock.lock()
        let existingState = watchedFiles[path]
        lock.unlock()

        if let state = existingState {
            if fileSize > state.lastOffset {
                readNewContent(path: path, from: state.lastOffset, sessionId: state.sessionId)
                lock.lock()
                watchedFiles[path]?.lastOffset = fileSize
                lock.unlock()
            }
        } else {
            let sessionId = UUID()
            let projectName = extractProjectName(from: path)
            let workDir = extractWorkingDir(from: path)

            lock.lock()
            watchedFiles[path] = FileState(lastOffset: max(fileSize, 1024) - 1024, sessionId: sessionId)
            lock.unlock()

            Task { @MainActor [weak self] in
                guard let self else { return }
                let session = AgentSession(
                    id: sessionId,
                    agentType: .claudeCode,
                    status: .working,
                    currentTask: projectName,
                    conversationPath: path,
                    workingDirectory: workDir,
                    isPassive: true
                )
                self.sessionManager.addSession(session)
            }

            readNewContent(path: path, from: max(fileSize, 1024) - 1024, sessionId: sessionId)

            lock.lock()
            watchedFiles[path]?.lastOffset = fileSize
            lock.unlock()
        }
    }

    private func readNewContent(path: String, from offset: UInt64, sessionId: UUID) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }
        handle.seek(toFileOffset: offset)
        guard let data = try? handle.availableData, !data.isEmpty else { return }
        guard let text = String(data: data, encoding: .utf8) else { return }

        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        for line in lines.suffix(10) {
            parseLogLine(line, sessionId: sessionId)
        }
    }

    private func parseLogLine(_ line: String, sessionId: UUID) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let message = json["message"] as? [String: Any],
           let role = message["role"] as? String {
            if role == "assistant" {
                if let content = message["content"] as? [[String: Any]] {
                    for block in content {
                        if block["type"] as? String == "tool_use" {
                            let toolName = block["name"] as? String ?? "tool"
                            Task { @MainActor [weak self] in
                                self?.sessionManager.updateStatus(id: sessionId, status: .working, task: toolName)
                            }
                            return
                        }
                    }
                }
                Task { @MainActor [weak self] in
                    self?.sessionManager.updateStatus(id: sessionId, status: .working, task: "Responding")
                }
            } else if role == "user" {
                Task { @MainActor [weak self] in
                    self?.sessionManager.updateStatus(id: sessionId, status: .working, task: "Processing")
                }
            }
        }

        if let message = json["message"] as? [String: Any],
           let stopReason = message["stop_reason"] as? String,
           stopReason == "end_turn" {
            Task { @MainActor [weak self] in
                self?.sessionManager.updateStatus(id: sessionId, status: .idle)
            }
        }
    }

    private func extractProjectName(from path: String) -> String {
        let components = path.components(separatedBy: "/")
        if components.count >= 2 {
            return components[components.count - 2]
        }
        return "Unknown Project"
    }

    private func extractWorkingDir(from path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path),
              let data = try? handle.readData(ofLength: 4096),
              let text = String(data: data, encoding: .utf8) else { return nil }
        try? handle.close()

        if let firstLine = text.components(separatedBy: "\n").first,
           let lineData = firstLine.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
           let cwd = json["cwd"] as? String {
            return cwd
        }
        return nil
    }
}
