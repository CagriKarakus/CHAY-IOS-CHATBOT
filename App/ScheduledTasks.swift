import AppIntents
import Foundation
import Observation
import UserNotifications

/// Belirli saatlerde çalıştırılacak bir komut (ör. sabah haber özeti).
struct ScheduledTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var prompt: String
    /// `nil` = Ayarlar'daki seçili model.
    var modelID: UUID?
    var hour = 7
    var minute = 0
    /// Takvim günleri (1 = Pazar … 7 = Cumartesi); boşsa her gün.
    var weekdays: [Int] = []
    /// Saatinde bildirim gönderilsin; dokununca görev çalışır.
    var remind = true
    var enabled = true

    var timeText: String {
        let date = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    var daysText: String {
        guard !weekdays.isEmpty, weekdays.count < 7 else { return L("Every day", "Her gün") }
        let symbols = Calendar.current.shortWeekdaySymbols
        return ScheduledTask.orderedWeekdays.filter(weekdays.contains).map { symbols[$0 - 1] }.joined(separator: ", ")
    }

    /// Haftanın ilk gününden başlayarak günler (Türkiye'de Pazartesi).
    static var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    /// Kestirmeden veya bildirimden çalıştırılır: yeni sohbette görevin modeliyle gönderilir.
    var request: ShortcutRequest {
        ShortcutRequest(prompt: prompt, modelID: modelID)
    }
}

/// Zamanlanmış görevler (UserDefaults'ta; Kestirmeler eylemi de buradan okur) ve hatırlatma bildirimleri.
@Observable @MainActor
final class ScheduledTaskLibrary {
    nonisolated static let storageKey = "scheduled.tasks"
    nonisolated static let taskIDKey = "scheduledTaskID"
    private static let notificationPrefix = "scheduled."

    private(set) var tasks: [ScheduledTask] = []

    init() {
        tasks = Self.load()
    }

    nonisolated static func load() -> [ScheduledTask] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ScheduledTask].self, from: data)
        else { return [] }
        return decoded
    }

    func save(_ task: ScheduledTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
        persist()
        if task.remind && task.enabled {
            TurnNotifications.requestPermissionIfNeeded()
        }
    }

    func delete(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        persist()
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].enabled = enabled
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        rescheduleNotifications()
    }

    /// Tüm hatırlatmaları görevlere göre yeniden kurar.
    private func rescheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        let tasks = self.tasks
        let prefix = Self.notificationPrefix
        Task {
            let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for task in tasks where task.enabled && task.remind {
                let content = UNMutableNotificationContent()
                content.title = task.name
                content.body = L("Tap to run: ", "Çalıştırmak için dokun: ") + task.prompt
                content.sound = .default
                content.userInfo = [Self.taskIDKey: task.id.uuidString]
                let days = task.weekdays.isEmpty || task.weekdays.count == 7 ? [nil] : task.weekdays.map(Optional.some)
                for day in days {
                    var components = DateComponents(hour: task.hour, minute: task.minute)
                    components.weekday = day
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    let id = prefix + task.id.uuidString + "." + (day.map(String.init) ?? "daily")
                    try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                }
            }
        }
    }
}

/// Bildirime dokununca görevi çalıştırır; uygulama açıkken de bildirimi gösterir.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo[ScheduledTaskLibrary.taskIDKey] as? String,
              let task = ScheduledTaskLibrary.load().first(where: { $0.id.uuidString == id })
        else { return }
        await MainActor.run { ShortcutInbox.put(task.request) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

// MARK: - Kestirmeler

/// Kestirmeler'de seçilebilen zamanlanmış görev.
struct ScheduledTaskEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "CHAY Task"
    static let defaultQuery = ScheduledTaskQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ScheduledTaskQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ScheduledTaskEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ScheduledTaskEntity] {
        ScheduledTaskLibrary.load().map { ScheduledTaskEntity(id: $0.id, name: $0.name) }
    }
}

/// "CHAY görevini çalıştır": Kestirmeler > Otomasyon > Günün Saati ile tam otomatik çalıştırmak için.
struct RunScheduledTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Run CHAY Task"
    static let description = IntentDescription("Opens CHAY and runs one of your scheduled tasks in a new chat.")
    static let openAppWhenRun = true

    @Parameter(title: "Task")
    var task: ScheduledTaskEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$task)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let saved = ScheduledTaskLibrary.load().first(where: { $0.id == task.id }) else {
            throw $task.needsValueError()
        }
        ShortcutInbox.put(saved.request)
        return .result()
    }
}
