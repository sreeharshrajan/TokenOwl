import Foundation

public struct CodexProcessResult: Sendable {
    public let response: CodexRateLimitResponse
    public let rawJSON: String

    public init(response: CodexRateLimitResponse, rawJSON: String) {
        self.response = response
        self.rawJSON = rawJSON
    }
}

public protocol CodexProcessClient: Sendable {
    func fetchRateLimits() async throws -> CodexProcessResult
}

public struct CodexBinaryResolver: Sendable {
    private let pathOverride: String?
    private let fileExists: @Sendable (String) -> Bool
    private let pathDirectories: @Sendable () -> [String]

    public init(
        pathOverride: String? = nil,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        pathDirectories: @escaping @Sendable () -> [String] = {
            (ProcessInfo.processInfo.environment["PATH"] ?? "")
                .split(separator: ":")
                .map(String.init)
        }
    ) {
        self.pathOverride = pathOverride
        self.fileExists = fileExists
        self.pathDirectories = pathDirectories
    }

    public func resolve() -> String? {
        if let override = pathOverride, !override.isEmpty, fileExists(override) {
            return override
        }

        let executableName = "codex"
        var directories = pathDirectories()
        directories.append(contentsOf: Self.standardExecutableDirectories)

        for directory in directories {
            let candidate = directory + "/" + executableName
            if fileExists(candidate) {
                return candidate
            }
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        for root in [".vscode/extensions", ".vscode-insiders/extensions"] {
            let directory = home.appendingPathComponent(root)
            let extensions = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            for name in extensions.sorted().reversed() where name.hasPrefix("openai.chatgpt-") {
                let candidate = directory.appendingPathComponent(name).appendingPathComponent("bin/macos-\(Self.architecture)/codex").path
                if fileExists(candidate) { return candidate }
            }
        }
        for candidate in ["/Applications/Codex.app/Contents/Resources/codex", home.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex").path] {
            if fileExists(candidate) { return candidate }
        }
        return nil
    }

    private static var architecture: String {
        #if arch(arm64)
        "aarch64"
        #else
        "x86_64"
        #endif
    }

    public static let standardExecutableDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "~/.npm-global/bin",
        "~/.local/bin",
    ].map { ($0 as NSString).expandingTildeInPath }
}

final class CodexSessionState: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private let maxStderrBytes: Int = 65536
    private var continuations: [String: CheckedContinuation<CodexProcessResult, Error>] = [:]
    private var isFinished = false

    func registerContinuation(id: String, continuation: CheckedContinuation<CodexProcessResult, Error>) {
        lock.lock()
        defer { lock.unlock() }
        if isFinished {
            continuation.resume(throwing: CodexError.malformedResponse)
        } else {
            continuations[id] = continuation
        }
    }

    func appendStdout(_ data: Data) {
        lock.lock()
        stdoutBuffer.append(data)
        var lines: [String] = []
        while let newlineIndex = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineData = stdoutBuffer[..<newlineIndex]
            stdoutBuffer = Data(stdoutBuffer[stdoutBuffer.index(after: newlineIndex)...])
            if !lineData.isEmpty, let line = String(data: lineData, encoding: .utf8) {
                lines.append(line)
            }
        }
        lock.unlock()

        for line in lines {
            handleStdoutLine(line)
        }
    }

    func appendStderr(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        if stderrBuffer.count < maxStderrBytes {
            let take = min(data.count, maxStderrBytes - stderrBuffer.count)
            stderrBuffer.append(data.prefix(take))
        }
    }

    var collectedStderr: String {
        lock.lock()
        defer { lock.unlock() }
        let raw = String(decoding: stderrBuffer, as: UTF8.self)
        return RedactedLogger.redact(raw)
    }

    private func handleStdoutLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        guard let idValue = json["id"] else {
            // Notification or unknown non-response event
            return
        }

        let id = "\(idValue)"

        lock.lock()
        let continuation = continuations.removeValue(forKey: id)
        lock.unlock()

        guard let continuation else {
            return
        }

        if let errorDict = json["error"] as? [String: Any] {
            let code = errorDict["code"] as? Int ?? -1
            let message = errorDict["message"] as? String ?? "Unknown error"
            continuation.resume(throwing: CodexProcessClientLive.mapJSONRPCError(code: code, message: message))
            return
        }

        if let resultDict = json["result"] as? [String: Any] {
            do {
                let resultData = try JSONSerialization.data(withJSONObject: resultDict)
                let response = try JSONDecoder().decode(CodexRateLimitResponse.self, from: resultData)
                continuation.resume(returning: CodexProcessResult(response: response, rawJSON: line))
            } catch {
                continuation.resume(throwing: CodexError.malformedResponse)
            }
            return
        }

        continuation.resume(throwing: CodexError.malformedResponse)
    }

    func flushRemainingBuffer() {
        lock.lock()
        let remaining = stdoutBuffer
        stdoutBuffer.removeAll()
        lock.unlock()

        if !remaining.isEmpty, let line = String(data: remaining, encoding: .utf8) {
            handleStdoutLine(line)
        }
    }

    func finish(with error: Error) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let pending = continuations
        continuations.removeAll()
        lock.unlock()

        for (_, cont) in pending {
            cont.resume(throwing: error)
        }
    }
}

public actor CodexProcessClientLive: CodexProcessClient {
    private let binaryPath: String
    private let timeout: TimeInterval
    private let forceKillGracePeriod: TimeInterval

    public init(
        binaryPath: String,
        timeout: TimeInterval = 10,
        forceKillGracePeriod: TimeInterval = 2
    ) {
        signal(SIGPIPE, SIG_IGN)
        self.binaryPath = binaryPath
        self.timeout = timeout
        self.forceKillGracePeriod = forceKillGracePeriod
    }

    public func fetchRateLimits() async throws -> CodexProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["app-server"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let session = CodexSessionState()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty {
                session.appendStdout(chunk)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty {
                session.appendStderr(chunk)
            }
        }

        do {
            try process.run()
        } catch {
            throw CodexError.processFailed(exitCode: -1)
        }

        let pid = process.processIdentifier

        process.terminationHandler = { proc in
            session.flushRemainingBuffer()
            let exitCode = proc.terminationStatus
            if exitCode != 0 {
                session.finish(with: CodexError.processFailed(exitCode: exitCode))
            } else {
                session.finish(with: CodexError.malformedResponse)
            }
        }

        let forceGrace = self.forceKillGracePeriod

        @Sendable func cleanup() async {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil

            try? stdinPipe.fileHandleForWriting.close()

            if process.isRunning {
                process.terminate()
                let graceDeadline = Date().addingTimeInterval(forceGrace)
                while process.isRunning && Date() < graceDeadline {
                    try? await Task.sleep(for: .milliseconds(25))
                }
                if process.isRunning {
                    kill(pid, SIGKILL)
                    process.waitUntilExit()
                }
            } else {
                process.waitUntilExit()
            }

            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()

            let stderr = session.collectedStderr
            if !stderr.isEmpty {
                RedactedLogger.log("Codex stderr: \(stderr)")
            }
        }

        return try await withTaskCancellationHandler {
            let result: CodexProcessResult
            do {
                result = try await withTimeout(self.timeout) {
                    let initReq = CodexProcessClientLive.makeJSONRPCRequest(
                        id: "0",
                        method: "initialize",
                        params: [
                            "clientInfo": ["name": "TokenOwl", "version": "1.0"],
                            "capabilities": [:]
                        ]
                    ) + "\n"
                    _ = try await withTaskCancellationHandler {
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CodexProcessResult, Error>) in
                            session.registerContinuation(id: "0", continuation: continuation)
                            do { try stdinPipe.fileHandleForWriting.write(contentsOf: Data(initReq.utf8)) }
                            catch { session.finish(with: CodexError.processFailed(exitCode: -1)) }
                        }
                    } onCancel: { session.finish(with: CodexError.timeout) }

                    let initNotif = CodexProcessClientLive.makeJSONRPCNotification(
                        method: "initialized",
                        params: [:]
                    ) + "\n"
                    if let data = initNotif.data(using: .utf8) {
                        try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
                    }

                    let readReq = CodexProcessClientLive.makeJSONRPCRequest(
                        id: "1",
                        method: "account/rateLimits/read",
                        params: [:]
                    ) + "\n"
                    return try await withTaskCancellationHandler {
                        try await withCheckedThrowingContinuation { continuation in
                            session.registerContinuation(id: "1", continuation: continuation)
                            do {
                                try stdinPipe.fileHandleForWriting.write(contentsOf: Data(readReq.utf8))
                            } catch { session.finish(with: CodexError.processFailed(exitCode: -1)) }
                        }
                    } onCancel: {
                        session.finish(with: CodexError.timeout)
                    }
                }
            } catch {
                await cleanup()
                throw error
            }

            await cleanup()
            return result
        } onCancel: {
            process.terminate()
            Task.detached {
                try? await Task.sleep(for: .seconds(forceGrace))
                if process.isRunning {
                    kill(pid, SIGKILL)
                    process.waitUntilExit()
                }
            }
        }
    }

    static func makeJSONRPCRequest(id: String, method: String, params: [String: Any]) -> String {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        let data = try! JSONSerialization.data(withJSONObject: request, options: [.withoutEscapingSlashes])
        return String(data: data, encoding: .utf8)!
    }

    static func makeJSONRPCNotification(method: String, params: [String: Any]) -> String {
        let notification: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]
        let data = try! JSONSerialization.data(withJSONObject: notification, options: [.withoutEscapingSlashes])
        return String(data: data, encoding: .utf8)!
    }

    static func mapJSONRPCError(code: Int, message: String) -> CodexError {
        if message.localizedCaseInsensitiveContains("api key") ||
            message.localizedCaseInsensitiveContains("api-key") ||
            message.localizedCaseInsensitiveContains("apikey") {
            return .apiKeyAuthUnsupported
        }
        if message.localizedCaseInsensitiveContains("not logged in") ||
            message.localizedCaseInsensitiveContains("not authenticated") ||
            message.localizedCaseInsensitiveContains("login") {
            return .notLoggedIn
        }
        return .malformedResponse
    }
}

func withTimeout<T: Sendable>(
    _ timeout: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    guard timeout > 0 else { throw CodexError.timeout }
    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(timeout))
            throw CodexError.timeout
        }
        guard let first = try await group.next() else {
            throw CodexError.timeout
        }
        group.cancelAll()
        return first
    }
}
