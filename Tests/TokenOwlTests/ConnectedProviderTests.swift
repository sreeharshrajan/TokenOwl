import Foundation
import Testing
@testable import TokenOwlCore

@Suite("Connected editor providers")
struct ConnectedProviderTests {
    @Test func realCodexSchemaPreservesWindowsAndResetTimes() throws {
        let response = try JSONDecoder().decode(CodexRateLimitResponse.self, from: Data("""
        {"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1730947200},"secondary":{"usedPercent":80,"windowDurationMins":10080,"resetsAt":1730950800}}}}
        """.utf8))
        let summary = CodexQuotaSummary(response: response)
        #expect(summary.windows.count == 2)
        #expect(summary.mostConstrainedPercent == 20)
        #expect(summary.windows.first?.resetsAt == Date(timeIntervalSince1970: 1730947200))
    }

    @Test func missingUsageIsRejectedRatherThanShowingFullQuota() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(CodexRateLimitResponse.self, from: Data("{\"rateLimitsByLimitId\":{\"bad\":{}}}".utf8))
        }
    }

    @Test func defaultRegistryConnectsAllEditors() {
        let registry = QuotaProviderRegistry()
        for editor in AIEditor.allCases { #expect(registry.hasAdapter(for: editor)) }
    }
}
