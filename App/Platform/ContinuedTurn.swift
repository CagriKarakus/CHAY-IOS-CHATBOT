import BackgroundTasks
import Foundation

/// iOS 26+: kullanıcının başlattığı cevap, uygulamadan çıkılınca da sürsün diye "devam eden arka plan görevi".
/// iOS ilerlemeyi kendi arayüzünde gösterir. Görev başlatılamazsa veya iOS durdurursa eski davranış geçerlidir
/// (yaklaşık 30 sn ek süre, uygulamaya dönünce kaldığı yerden devam).
@MainActor
final class ContinuedTurn {
    /// Info.plist'te `BGTaskSchedulerPermittedIdentifiers`: "dev.cagri.aiassistant.turn.*".
    private static let prefix = "dev.cagri.aiassistant.turn."
    private static let statusKey = "background.continuedStatus"

    /// Son denemenin sonucu (Ayarlar'da gösterilir; görev başlamazsa nedenini görmek için).
    static var lastStatus: String? {
        UserDefaults.standard.string(forKey: statusKey)
    }

    private static func record(_ status: String) {
        let time = Date.now.formatted(date: .abbreviated, time: .shortened)
        UserDefaults.standard.set("\(time): \(status)", forKey: statusKey)
    }

    private var task: BGTask?
    /// Görev iOS tarafından başlatılmadan cevap bittiyse sonucu.
    private var result: Bool?
    private var completed: Int64 = 0
    private var lastUpdate = Date.distantPast

    /// Görevi başlatır (uygulama öndeyken çağrılmalı). iOS 26 öncesinde veya iOS reddederse `nil`.
    static func start(title: String) -> ContinuedTurn? {
        guard #available(iOS 26, *) else {
            record(L("Not available before iOS 26", "iOS 26 öncesinde kullanılamaz"))
            return nil
        }
        let turn = ContinuedTurn()
        let identifier = prefix + UUID().uuidString
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated { turn.attach(task) }
        }
        guard registered else {
            record(L("iOS refused to register the task", "iOS görevi kaydetmeyi reddetti"))
            return nil
        }
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: title,
            subtitle: L("Preparing the answer…", "Cevap hazırlanıyor…")
        )
        // Hemen başlayamıyorsa sıraya girmesin; o durumda eski davranış geçerli.
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            let code = (error as NSError).code
            record(L("iOS didn't start the task (error \(code): \(error.localizedDescription))",
                     "iOS görevi başlatmadı (hata \(code): \(error.localizedDescription))"))
            return nil
        }
        record(L("Started", "Başlatıldı"))
        return turn
    }

    private func attach(_ task: BGTask) {
        if let result {
            task.setTaskCompleted(success: result)
            return
        }
        self.task = task
        task.expirationHandler = { [weak self] in
            // iOS veya kullanıcı durdurdu: istek kesilince cevap uygulamaya dönünce sürer.
            Task { @MainActor in
                Self.record(L("Stopped by iOS or from the progress view", "iOS veya ilerleme göstergesinden durduruldu"))
                self?.finish(success: false)
            }
        }
        if #available(iOS 26, *), let continued = task as? BGContinuedProcessingTask {
            continued.progress.totalUnitCount = 100
            continued.progress.completedUnitCount = completed
        }
        // İlerleme bildirmeyen görevleri iOS durdurur; model uzun süre sessiz kalsa da (düşünme,
        // uzun sayfa yazma, yavaş araç) ilerleme düzenli artsın.
        Task { [weak self] in
            while let self, self.task != nil {
                self.advance()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// İlerlemeyi ilerletir; `subtitle` verilirse sistem arayüzündeki alt başlığı değiştirir.
    /// Metin akışında saniyede birden sık güncellemez.
    func advance(_ subtitle: String? = nil) {
        guard subtitle != nil || Date.now.timeIntervalSince(lastUpdate) > 1 else { return }
        lastUpdate = .now
        // Toplam iş bilinmediği için ilerleme %95'e kadar yavaşça artar.
        completed = min(completed + max((95 - completed) / 10, 1), 95)
        guard #available(iOS 26, *), let continued = task as? BGContinuedProcessingTask else { return }
        continued.progress.completedUnitCount = completed
        if let subtitle {
            continued.updateTitle(continued.title, subtitle: subtitle)
        }
    }

    func finish(success: Bool) {
        guard result == nil else { return }
        result = success
        if #available(iOS 26, *), let continued = task as? BGContinuedProcessingTask {
            continued.progress.completedUnitCount = 100
        }
        task?.setTaskCompleted(success: success)
        task = nil
    }
}
