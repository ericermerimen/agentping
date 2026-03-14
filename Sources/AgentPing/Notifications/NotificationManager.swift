import UserNotifications
import AgentPingCore

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private var onSessionTapped: ((String) -> Void)?

    func setup(onSessionTapped: @escaping (String) -> Void) {
        self.onSessionTapped = onSessionTapped
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func sendNeedsInput(session: Session) {
        guard session.notifications else { return }

        let content = UNMutableNotificationContent()
        content.title = "Agent needs input"
        content.body = "\(session.name ?? "Session") in \(session.app ?? "unknown") is waiting for you"
        content.sound = .default
        content.userInfo = ["sessionId": session.id]

        let request = UNNotificationRequest(
            identifier: "needs-input-\(session.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func sendError(session: Session) {
        guard session.notifications else { return }

        let content = UNMutableNotificationContent()
        content.title = "Agent hit an error"
        content.body = "\(session.name ?? "Session") in \(session.app ?? "unknown") encountered an error"
        content.sound = .default
        content.userInfo = ["sessionId": session.id]

        let request = UNNotificationRequest(
            identifier: "error-\(session.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func sendContextWarning(session: Session, percent: Double) {
        guard session.notifications else { return }

        let content = UNMutableNotificationContent()
        content.title = "Context window \(Int(percent * 100))%"
        content.body = "\(session.name ?? "Session") is running low on context. Consider starting a new session."
        content.sound = .default
        content.userInfo = ["sessionId": session.id]

        let request = UNNotificationRequest(
            identifier: "context-warning-\(session.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func sendReady(session: Session) {
        guard session.notifications else { return }

        let content = UNMutableNotificationContent()
        content.title = "Agent ready"
        content.body = "\(session.name ?? "Session") in \(session.app ?? "unknown") finished and is ready for review"
        content.sound = .default
        content.userInfo = ["sessionId": session.id]

        let request = UNNotificationRequest(
            identifier: "ready-\(session.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func sendDone(session: Session) {
        guard session.notifications else { return }

        let content = UNMutableNotificationContent()
        content.title = "Agent finished"
        content.body = "\(session.name ?? "Session") in \(session.app ?? "unknown") completed its task"
        content.sound = .default
        content.userInfo = ["sessionId": session.id]

        let request = UNNotificationRequest(
            identifier: "done-\(session.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let sessionId = response.notification.request.content.userInfo["sessionId"] as? String {
            onSessionTapped?(sessionId)
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
