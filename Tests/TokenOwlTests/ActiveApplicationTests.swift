import XCTest
@testable import TokenOwlCore

final class ActiveApplicationTests: XCTestCase {
    func testAutomaticPeriodSwitchesOnlyWhenFiveHourQuotaIsExhausted() {
        XCTAssertEqual(HighlightFilter.automaticPeriod(fiveHourRemainingPercent: 100), .fiveHours)
        XCTAssertEqual(HighlightFilter.automaticPeriod(fiveHourRemainingPercent: 1), .fiveHours)
        XCTAssertEqual(HighlightFilter.automaticPeriod(fiveHourRemainingPercent: 0), .weekly)
        XCTAssertEqual(HighlightFilter.automaticPeriod(fiveHourRemainingPercent: -1), .weekly)
        XCTAssertEqual(HighlightFilter.automaticPeriod(fiveHourRemainingPercent: nil), .fiveHours)
    }

    func testMatchesOnlySupportedDesktopApplications() {
        XCTAssertEqual(AIEditor.foregroundEditor(bundleIdentifier: "com.openai.codex"), .codex)
        XCTAssertEqual(AIEditor.foregroundEditor(bundleIdentifier: "com.google.antigravity"), .antigravity)
        XCTAssertEqual(AIEditor.foregroundEditor(bundleIdentifier: "com.google.antigravity-ide"), .antigravity)
        XCTAssertNil(AIEditor.foregroundEditor(bundleIdentifier: "com.apple.Terminal"))
        XCTAssertEqual(AIEditor.foregroundEditor(bundleIdentifier: "com.microsoft.VSCode"), .codex)
        XCTAssertEqual(AIEditor.foregroundEditor(bundleIdentifier: "com.microsoft.VSCodeInsiders"), .codex)
        XCTAssertNil(AIEditor.foregroundEditor(bundleIdentifier: "com.microsoft.VSCode.helper"))
        XCTAssertNil(AIEditor.foregroundEditor(bundleIdentifier: "com.example.editor"))
        XCTAssertNil(AIEditor.foregroundEditor(bundleIdentifier: nil))
    }

    func testSelectedPeriodUsesItsOwnLimitAndDoesNotBorrowMissingPeriod() {
        let snapshot = ProviderSnapshot(editor: .codex, fetchedAt: Date(), accountEmail: nil,
            tierDisplayName: nil, credentialSourceDisplayName: nil, metrics: [
                ProviderMetric(id: "primary", label: "5 hours", remainingPercent: 80, resetAt: nil),
                ProviderMetric(id: "secondary", label: "Weekly", remainingPercent: 20, resetAt: nil)
            ], headlineRemainingPercent: 20)
        XCTAssertEqual(snapshot.metric(for: .fiveHours)?.remainingPercent, 80)
        XCTAssertEqual(snapshot.metric(for: .weekly)?.remainingPercent, 20)
        let missing = ProviderSnapshot(editor: .codex, fetchedAt: Date(), accountEmail: nil,
            tierDisplayName: nil, credentialSourceDisplayName: nil,
            metrics: [snapshot.metrics[0]], headlineRemainingPercent: 80)
        XCTAssertNil(missing.metric(for: .weekly))
    }
}
