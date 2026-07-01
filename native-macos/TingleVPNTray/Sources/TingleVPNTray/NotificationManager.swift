import Foundation
import UserNotifications

final class NotificationManager {
    private var didRequestAuthorization = false
    private var isSupportedRuntime: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    func requestAuthorizationIfNeeded() async {
        guard isSupportedRuntime else { return }
        if didRequestAuthorization { return }
        didRequestAuthorization = true
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func notifyPeerConnected(displayName: String) async {
        guard isSupportedRuntime else { return }
        let content = UNMutableNotificationContent()
        content.title = "Novo peer conectado"
        content.body = "\(displayName) conectou ao TingleVPN."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func notifyPeerDisconnected(displayName: String) async {
        guard isSupportedRuntime else { return }
        let content = UNMutableNotificationContent()
        content.title = "Peer desconectado"
        content.body = "\(displayName) desconectou do TingleVPN."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
