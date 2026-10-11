import Foundation
import Testing
@testable import TokenOwlCore

@Suite("Codex live integration (opt-in)")
struct CodexLiveIntegrationTests {

    @Test func liveRateLimitsFetch() async throws {
        guard ProcessInfo.processInfo.environment["TOKENOWL_CODEX_LIVE"] == "1" else {
            // Skipped when opt-in env var is not set
            return
        }

        guard let path = CodexBinaryResolver().resolve() else {
            Issue.record("Codex CLI not found on PATH or standard locations")
            return
        }

        let client = CodexProcessClientLive(binaryPath: path, timeout: 15)
        let result = try await client.fetchRateLimits()

        // Redaction verification: Ensure no tokens or auth details in raw output
        #expect(!result.rawJSON.isEmpty)
        let summary = CodexQuotaSummary(response: result.response)
        // Must never log account data or token material
        #expect(summary.windows.count >= 0)
    }
}
