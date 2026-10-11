import Foundation
import Testing
@testable import TokenOwlCore

struct QuotaAlertTests {
    func snapshot(_ percent: Int, editor: AIEditor = .antigravity, reset: Double = 1000, time: Double = 1) -> ProviderSnapshot {
        ProviderSnapshot(editor: editor, fetchedAt: Date(timeIntervalSince1970: time), accountEmail: nil,
                         tierDisplayName: nil, credentialSourceDisplayName: nil,
                         metrics: [ProviderMetric(id: "model-window", label: "Model · Five hours", remainingPercent: percent,
                                                  resetAt: Date(timeIntervalSince1970: reset))], headlineRemainingPercent: percent)
    }
    @Test func firstLaunchBelowThresholdDoesNotReplay() {
        var evaluator = QuotaAlertEvaluator()
        #expect(evaluator.evaluate(snapshot(4), preferences: QuotaAlertPreferences()).isEmpty)
        #expect(evaluator.evaluate(snapshot(3, time: 2), preferences: QuotaAlertPreferences()).isEmpty)
    }
    @Test func crossingsAndDuplicates() {
        var evaluator = QuotaAlertEvaluator(); let preferences = QuotaAlertPreferences()
        #expect(preferences.thresholds == [10])
        #expect(evaluator.evaluate(snapshot(26), preferences: preferences).isEmpty)
        #expect(evaluator.evaluate(snapshot(24, time: 2), preferences: preferences).isEmpty)
        #expect(evaluator.evaluate(snapshot(9, time: 3), preferences: preferences).map(\.threshold) == [10])
        #expect(evaluator.evaluate(snapshot(30, time: 4), preferences: preferences).isEmpty)
        #expect(evaluator.evaluate(snapshot(9, time: 5), preferences: preferences).isEmpty)
    }
    @Test func severeOnlyAndReset() {
        var evaluator = QuotaAlertEvaluator(); var preferences = QuotaAlertPreferences()
        preferences.thresholds = [50,25,10,5]
        _ = evaluator.evaluate(snapshot(60), preferences: preferences)
        #expect(evaluator.evaluate(snapshot(4, time: 2), preferences: preferences).map(\.threshold) == [5])
        #expect(evaluator.evaluate(snapshot(60, reset: 2000, time: 3), preferences: preferences).isEmpty)
        #expect(evaluator.evaluate(snapshot(24, reset: 2000, time: 4), preferences: preferences).map(\.threshold) == [25])
    }
    @Test func disabledDeniedAndStale() {
        var evaluator = QuotaAlertEvaluator(); var preferences = QuotaAlertPreferences()
        #expect(evaluator.evaluate(snapshot(4), preferences: preferences, stale: true).isEmpty)
        #expect(evaluator.evaluate(snapshot(4), preferences: preferences, verified: false).isEmpty)
        #expect(evaluator.evaluate(snapshot(26), preferences: preferences).isEmpty)
        preferences.thresholds = [10]
        #expect(evaluator.evaluate(snapshot(24, time: 2), preferences: preferences).isEmpty)
        #expect(evaluator.evaluate(snapshot(9, time: 3), preferences: preferences, permissionGranted: false).isEmpty)
        #expect(evaluator.evaluate(snapshot(8, time: 4), preferences: preferences).isEmpty)
    }
    @Test func isolationAndMonitoring() {
        var evaluator = QuotaAlertEvaluator(); var preferences = QuotaAlertPreferences()
        preferences.thresholds = [25]
        _ = evaluator.evaluate(snapshot(26), preferences: preferences)
        #expect(evaluator.evaluate(snapshot(24, editor: .codex), preferences: preferences).isEmpty)
        #expect(evaluator.evaluate(snapshot(24, time: 2), preferences: preferences).count == 1)
        #expect(!preferences.monitors(.codex, selected: .antigravity))
        preferences.backgroundCodex = true
        #expect(preferences.monitors(.codex, selected: .antigravity))
        preferences.codexEnabled = false
        #expect(!preferences.monitors(.codex, selected: .antigravity))
        #expect(preferences.monitors(.codex, selected: .codex))
    }
    @Test func preferencesRoundTrip() throws {
        let preferences = QuotaAlertPreferences()
        #expect(try JSONDecoder().decode(QuotaAlertPreferences.self, from: JSONEncoder().encode(preferences)) == preferences)
    }
}

struct HTTPRetryTests {
    @Test func boundedExponentialBackoffAndServerDeadline() {
        #expect(HTTPRetry.delay(attempt: 0, retryAfter: nil) == 2)
        #expect(HTTPRetry.delay(attempt: 1, retryAfter: nil) == 4)
        #expect(HTTPRetry.delay(attempt: 2, retryAfter: nil) == nil)
        #expect(HTTPRetry.delay(attempt: 0, retryAfter: 12) == 12)
        #expect(HTTPRetry.delay(attempt: 0, retryAfter: 120) == nil)
        #expect(HTTPRetry.delay(attempt: 0, retryAfter: .infinity) == nil)
    }
}

private final class RateLimitURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil,
                                       headerFields: ["Retry-After": request.url!.lastPathComponent])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private actor RetryRecorder {
    var delays: [TimeInterval] = []
    func append(_ delay: TimeInterval) { delays.append(delay) }
}

struct HTTPRateLimitIntegrationTests {
    @Test func retriesAreBoundedAndLongDeadlineIsRespected() async throws {
        for (hint, expectedRetries) in [("0", 2), ("120", 0)] {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [RateLimitURLProtocol.self]
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let recorder = RetryRecorder()
            let result = try await HTTPRetry.data(for: URLRequest(url: URL(string: "https://quota.invalid/\(hint)")!),
                                                 session: session, sleep: { await recorder.append($0) })
            #expect((result.1 as? HTTPURLResponse)?.statusCode == 429)
            #expect(await recorder.delays.count == expectedRetries)
        }
    }
}

struct CodexIdentityTests {
    @Test func accountMetadataIsReadWithoutTokens() throws {
        #expect(try CodexProcessClientLive.accountEmail(from: #"{"result":{"account":{"type":"chatgpt","email":"fixture@example.com"}}}"#) == "fixture@example.com")
        #expect(throws: CodexError.notLoggedIn) {
            try CodexProcessClientLive.accountEmail(from: #"{"result":{"account":null}}"#)
        }
        #expect(throws: CodexError.apiKeyAuthUnsupported) {
            try CodexProcessClientLive.accountEmail(from: #"{"result":{"account":{"type":"apiKey"}}}"#)
        }
        #expect(try CodexProcessClientLive.accountEmail(from: #"{"result":{"account":{"type":"chatgpt","email":null}}}"#) == nil)
    }
}
