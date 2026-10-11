import Foundation
import AppKit
import ServiceManagement
import TokenOwlCore

@main struct AcceptanceProbe {
    @MainActor static func main() async {
        let manager = NotificationManager()
        await manager.updatePermission()
        print("notification-status=\(manager.status)")
        print("authorized=\(manager.authorized); canRequest=\(manager.canRequest)")
        print("login-status-raw=\(SMAppService.mainApp.status.rawValue); loginEnabled=\(manager.loginEnabled)")
        print("permission requests=0; login mutations=0; real provider calls=0")
        var assertions = 0
        for editor in [AIEditor.antigravity, .codex] {
            for threshold in [50, 25, 10, 5] {
                var evaluator = QuotaAlertEvaluator()
                var prefs = QuotaAlertPreferences()
                prefs.thresholds = [threshold]
                func sample(_ percent: Int, _ time: Double, _ reset: Double = 1000) -> ProviderSnapshot {
                    ProviderSnapshot(editor: editor, fetchedAt: Date(timeIntervalSince1970: time),
                        accountEmail: "fixture@example.invalid", tierDisplayName: nil, credentialSourceDisplayName: "fixture",
                        metrics: [ProviderMetric(id: "fixture.primary", label: "5 hours", remainingPercent: percent,
                            resetAt: Date(timeIntervalSince1970: reset))], headlineRemainingPercent: percent)
                }
                let baseline = evaluator.evaluate(sample(threshold + 1, 1), preferences: prefs)
                let crossing = evaluator.evaluate(sample(threshold, 2), preferences: prefs)
                let duplicate = evaluator.evaluate(sample(threshold, 2), preferences: prefs)
                let rebound = evaluator.evaluate(sample(threshold + 1, 3), preferences: prefs)
                let recrossing = evaluator.evaluate(sample(threshold - 1, 4), preferences: prefs)
                let reset = evaluator.evaluate(sample(threshold + 1, 5, 2000), preferences: prefs)
                let rearmed = evaluator.evaluate(sample(threshold, 6, 2000), preferences: prefs)
                precondition(baseline.isEmpty && crossing.map(\.threshold) == [threshold] && duplicate.isEmpty
                    && rebound.isEmpty && recrossing.isEmpty && reset.isEmpty && rearmed.map(\.threshold) == [threshold])
                assertions += 7
                print("PASS fixture editor=\(editor.rawValue) threshold=\(threshold) once-per-window; reset-rearmed")
            }
        }
        print("PASS \(assertions) deterministic assertions; banners not submitted")
    }
}
