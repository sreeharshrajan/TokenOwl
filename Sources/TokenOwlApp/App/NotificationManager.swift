import Foundation
import Observation
import UserNotifications
import ServiceManagement
import TokenOwlCore

@MainActor @Observable
final class NotificationManager {
    private let delegate = QuotaNotificationDelegate()
    private(set) var status = "Checking permission…"
    private(set) var authorized = false
    private(set) var canRequest = false
    private var center: UNUserNotificationCenter? {
        // The SwiftPM executable alone is not an installed macOS application.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return UNUserNotificationCenter.current()
    }
    func updatePermission() async {
        guard let center else { status = "Install TokenOwl.app to enable notifications."; return }
        center.delegate = delegate
        let settings = await center.notificationSettings()
        authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        canRequest = settings.authorizationStatus == .notDetermined
        status = authorized ? "Notifications allowed" : canRequest ? "Permission has not been requested" : "Notifications denied. Enable them in System Settings."
    }
    func requestPermission() async {
        await updatePermission()
        guard canRequest, let center else { return }
        do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
        catch { status = "Notification permission request failed."; return }
        await updatePermission()
    }
    func deliver(_ alerts: [QuotaAlert]) async {
        guard authorized, let center else { return }
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = "\(alert.editor.displayName) quota warning"
            content.body = "\(alert.metric.label): \(alert.metric.remainingPercent)% remaining."
            if let reset = alert.metric.resetAt {
                content.body += " Resets \(reset.formatted(date: .abbreviated, time: .shortened))."
            }
            content.sound = .default
            do { try await center.add(UNNotificationRequest(identifier: alert.identifier, content: content, trigger: nil)) }
            catch { status = "Notification delivery failed. Check System Settings." }
        }
    }
    private(set) var loginEnabled = SMAppService.mainApp.status == .enabled
    var loginStatus: String {
        SMAppService.mainApp.status == .requiresApproval ? "Allow TokenOwl in System Settings → Login Items." : ""
    }
    private(set) var loginError: String?
    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginError = nil
        } catch { loginError = "Login item could not be updated. Install TokenOwl.app and check System Settings." }
    }
}

private final class QuotaNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
