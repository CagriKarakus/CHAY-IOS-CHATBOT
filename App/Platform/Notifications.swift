import Foundation
import UserNotifications

/// Uygulama arka plandayken cevabın durumu için yerel bildirimler.
enum TurnNotifications {
    private static let stillRunningID = "turn.stillRunning"
    private static let finishedID = "turn.finished"

    /// İlk mesajda bir kez izin ister (zaten sorulduysa bir şey yapmaz).
    static func requestPermissionIfNeeded() {
        Task {
            let center = UNUserNotificationCenter.current()
            guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    /// Kullanıcı bildirimleri kapatmış mı.
    static func areDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// iOS arka plan süresi (~30 sn) dolmadan önce kullanıcıyı uygulamaya geri çağırır.
    static func scheduleStillRunning(after seconds: TimeInterval = 20) {
        let content = UNMutableNotificationContent()
        content.title = "CHAY"
        content.body = L("Your answer is still being prepared. Open CHAY so it isn't interrupted.",
                         "Cevabın hâlâ hazırlanıyor. Yarıda kesilmemesi için CHAY'ı aç.")
        content.sound = .default
        add(stillRunningID, content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false))
    }

    /// Cevap uygulama arka plandayken tamamlandı.
    static func notifyFinished(title: String) {
        cancelStillRunning()
        let content = UNMutableNotificationContent()
        content.title = L("Answer ready", "Cevap hazır")
        content.body = title
        content.sound = .default
        // Aynı anda birden çok cevap bitebilir; biri diğerinin bildirimini silmesin.
        add("\(finishedID).\(UUID().uuidString)", content, trigger: nil)
    }

    static func cancelStillRunning() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [stillRunningID])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [stillRunningID])
    }

    private static func add(_ id: String, _ content: UNMutableNotificationContent, trigger: UNNotificationTrigger?) {
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
