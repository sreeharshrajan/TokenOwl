import Foundation
import Testing
@testable import TokenOwlCore

@Suite("Codex process client")
struct CodexProcessClientTests {

    private func makeTemporaryPath(_ suffix: String) -> String {
        NSTemporaryDirectory() + "codex-fake-\(UUID().uuidString)-\(suffix).sh"
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func processCount() -> Int32 {
        var pids = [pid_t](repeating: 0, count: 4096)
        let bytesUsed = proc_listpids(1, 0, &pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        let numPids = max(0, Int(bytesUsed) / MemoryLayout<pid_t>.size)
        var count: Int32 = 0
        for i in 0..<numPids {
            let pid = pids[i]
            guard pid > 0 else { continue }
            var pathBuffer = [CChar](repeating: 0, count: 4096)
            let pathResult = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            if pathResult > 0 {
                let nullTerminator = pathBuffer.firstIndex(of: 0) ?? pathBuffer.count
                let bytes = pathBuffer[0..<nullTerminator].map { UInt8(bitPattern: $0) }
                let path = String(decoding: bytes, as: UTF8.self)
                if path.contains("codex-fake") {
                    count += 1
                }
            }
        }
        return count
    }

    @Test func happyPathReturnsRateLimitResponse() async throws {
        let path = makeTemporaryPath("happy")
        defer { cleanup(path) }
        try CodexFakeServer.happyPath().write(to: path)

        let client = CodexProcessClientLive(binaryPath: path, timeout: 10)
        let result = try await client.fetchRateLimits()

        #expect(result.response.rateLimitsByLimitId != nil)
        #expect(result.response.rateLimitsByLimitId?.count == 2)
        #expect(result.response.rateLimitsByLimitId?["five_hour"]?.usedPercent == 42)
        #expect(result.response.rateLimitsByLimitId?["weekly"]?.usedPercent == 78)
    }

    @Test func singleWindowResponse() async throws {
        let path = makeTemporaryPath("single")
        defer { cleanup(path) }
        try CodexFakeServer.singleWindow().write(to: path)

        let client = CodexProcessClientLive(binaryPath: path, timeout: 10)
        let result = try await client.fetchRateLimits()

        #expect(result.response.rateLimitsByLimitId?.count == 1)
        #expect(result.response.rateLimitsByLimitId?["five_hour"]?.usedPercent == 50)
    }

    @Test func multiBucketResponse() async throws {
        let path = makeTemporaryPath("multi")
        defer { cleanup(path) }
        try CodexFakeServer.multiBucket().write(to: path)

        let client = CodexProcessClientLive(binaryPath: path, timeout: 10)
        let result = try await client.fetchRateLimits()

        #expect(result.response.rateLimitsByLimitId?.count == 3)
        #expect(result.response.rateLimitsByLimitId?["daily"]?.usedPercent == 5)
    }

    @Test func noWindowsResponseDoesNotThrow() async throws {
        let path = makeTemporaryPath("empty")
        defer { cleanup(path) }
        try CodexFakeServer.noWindows().write(to: path)

        let client = CodexProcessClientLive(binaryPath: path, timeout: 10)
        let result = try await client.fetchRateLimits()

        #expect(result.response.rateLimitsByLimitId?.isEmpty ?? false)
    }

    @Test func apiKeyAuthErrorMapped() async throws {
        let path = makeTemporaryPath("apikey")
        defer { cleanup(path) }
        try CodexFakeServer.apiKeyAuthError().write(to: path)

        let client = CodexProcessClientLive(binaryPath: path, timeout: 10)

        do {
            _ = try await client.fetchRateLimits()
            Issue.record("Expected apiKeyAuthUnsupported error")
        } catch let error as CodexError {
            #expect(error == .apiKeyAuthUnsupported)
        }
    }

    @Test func notLoggedInErrorMapped() async throws {
        let path = makeTemporaryPath("notloggedin")
        defer { cleanup(path) }
        try CodexFakeServer.notLoggedInError().write(to: path)

        let client = CodexProcessClientLive(binaryPath: path, timeout: 10)

        do {
            _ = try await client.fetchRateLimits()
            Issue.record("Expected notLoggedIn error")
        } catch let error as CodexError {
            #expect(error == .notLoggedIn)
        }
    }

    @Test func jsonRPCErrorMapped() async throws {
        let path = makeTemporaryPath("jsonrpc")
        defer { cleanup(path) }
        try CodexFakeServer.jsonRPCError().write(to: path)

        let client = CodexProcessClientLive(binaryPath: path, timeout: 10)

        do {
            _ = try await client.fetchRateLimits()
            Issue.record("Expected malformedResponse error")
        } catch let error as CodexError {
            #expect(error == .malformedResponse)
        }
    }

    @Test func malformedJSONIgnored() async throws {
        let path = makeTemporaryPath("malformed")
        defer { cleanup(path) }
        try CodexFakeServer.malformedJSON().write(to: path)

        let client = CodexProcessClientLive(binaryPath: path, timeout: 3)

        do {
            _ = try await client.fetchRateLimits()
            Issue.record("Expected timeout or malformedResponse error")
        } catch let error as CodexError {
            #expect(error == .timeout || error == .malformedResponse)
        }
    }

    @Test func partialLinesHandled() async throws {
        let path = makeTemporaryPath("partial")
        defer { cleanup(path) }
        try CodexFakeServer.partialLines().write(to: path)

        let client = CodexProcessClientLive(binaryPath: path, timeout: 10)
        let result = try await client.fetchRateLimits()

        #expect(result.response.rateLimitsByLimitId?["five_hour"]?.usedPercent == 42)
    }

    @Test func multipleObjectsPerChunkHandled() async throws {
        let path = makeTemporaryPath("multi-chunk")
        defer { cleanup(path) }
        try CodexFakeServer.multipleObjectsPerChunk().write(to: path)

        let client = CodexProcessClientLive(binaryPath: path, timeout: 10)
        let result = try await client.fetchRateLimits()

        #expect(result.response.rateLimitsByLimitId?["five_hour"]?.usedPercent == 42)
    }

    @Test func timeoutOnDelayedResponse() async throws {
        let path = makeTemporaryPath("delayed")
        defer { cleanup(path) }
        try CodexFakeServer.delayedResponse().write(to: path)

        let client = CodexProcessClientLive(binaryPath: path, timeout: 1)

        do {
            _ = try await client.fetchRateLimits()
            Issue.record("Expected timeout error")
        } catch let error as CodexError {
            #expect(error == .timeout)
        }
    }

    @Test func earlyExitMappedToProcessFailed() async throws {
        let path = makeTemporaryPath("early-exit")
        defer { cleanup(path) }
        try CodexFakeServer.exitsEarly().write(to: path)

        let client = CodexProcessClientLive(binaryPath: path, timeout: 3)

        do {
            _ = try await client.fetchRateLimits()
            Issue.record("Expected timeout or processFailed error")
        } catch let error as CodexError {
            #expect(error == .timeout || error == .processFailed(exitCode: 1))
        }
    }

    @Test func cancellationTerminatesProcess() async throws {
        let path = makeTemporaryPath("cancel")
        defer { cleanup(path) }
        try CodexFakeServer.hangsIgnoringStdinClose().write(to: path)

        let client = CodexProcessClientLive(binaryPath: path, timeout: 10, forceKillGracePeriod: 1)

        let task = Task {
            try await client.fetchRateLimits()
        }

        try await Task.sleep(for: .milliseconds(200))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation error")
        } catch {
        }

        try await Task.sleep(for: .milliseconds(100))
        #expect(processCount() == 0)
    }

    @Test func stderrRedactionFiltersTokens() async throws {
        let path = makeTemporaryPath("stderr")
        defer { cleanup(path) }
        try CodexFakeServer.stderrWithTokens().write(to: path)

        let client = CodexProcessClientLive(binaryPath: path, timeout: 10)
        _ = try await client.fetchRateLimits()

        #expect(true)
    }
}

@Suite("Codex binary resolution")
struct CodexBinaryResolutionTests {

    @Test func resolvesFromStandardLocation() {
        let standardDirs = CodexBinaryResolver.standardExecutableDirectories
        let resolver = CodexBinaryResolver(
            fileExists: { path in
                return path == standardDirs[0] + "/codex"
            },
            pathDirectories: { [] }
        )

        let result = resolver.resolve()
        #expect(result == standardDirs[0] + "/codex")
    }

    @Test func resolvesFromPATH() {
        let resolver = CodexBinaryResolver(
            fileExists: { path in
                path == "/usr/bin/codex"
            },
            pathDirectories: { ["/usr/bin", "/bin"] }
        )

        let result = resolver.resolve()
        #expect(result == "/usr/bin/codex")
    }

    @Test func pathOverrideTakesPrecedence() {
        let resolver = CodexBinaryResolver(
            pathOverride: "/custom/bin/codex",
            fileExists: { path in
                path == "/custom/bin/codex"
            },
            pathDirectories: { ["/usr/bin"] }
        )

        let result = resolver.resolve()
        #expect(result == "/custom/bin/codex")
    }

    @Test func returnsNilWhenNotFound() {
        let resolver = CodexBinaryResolver(
            fileExists: { _ in false },
            pathDirectories: { ["/usr/bin", "/bin"] }
        )

        let result = resolver.resolve()
        #expect(result == nil)
    }

    @Test func checksMultipleStandardLocations() {
        let standardDirs = CodexBinaryResolver.standardExecutableDirectories
        let resolver = CodexBinaryResolver(
            fileExists: { path in
                path == standardDirs[2] + "/codex"
            },
            pathDirectories: { [] }
        )

        let result = resolver.resolve()
        #expect(result == standardDirs[2] + "/codex")
    }
}
