import BackgroundTasks
import Foundation

/// iOS 26+: kullanıcının başlattığı cevap, uygulamadan çıkılınca da sürsün diye "devam eden arka plan görevi".
/// iOS ilerlemeyi kendi arayüzünde gösterir. Görev başlatılamazsa veya iOS durdurursa eski davranış geçerlidir
/// (yaklaşık 30 sn ek süre, uygulamaya dönünce kaldığı yerden devam).
@MainActor
final class ContinuedTurn {
    /// Info.plist'te `BGTaskSchedulerPermittedIdentifiers`: "dev.cagri.aiassistant.turn.*" ve Sideloadly'nin
    /// değiştirdiği kimlik için "dev.cagri.aiassistant.<takım kodu>.turn.*".
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
        let bundleID = Bundle.main.bundleIdentifier ?? "?"
        // Yükleme aracı uygulamanın kimliğini değiştirdiyse (ör. sonuna ekleme) görev adı da ona göre denenir.
        let prefixes = [prefix, bundleID + ".turn."].reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        var identifier: String?
        for candidate in prefixes.map({ $0 + UUID().uuidString }) {
            let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: candidate, using: .main) { task in
                MainActor.assumeIsolated { turn.attach(task) }
            }
            if registered {
                identifier = candidate
                break
            }
        }
        guard let identifier else {
            record(L("iOS refused to register the task (app ID: \(bundleID))",
                     "iOS görevi kaydetmeyi reddetti (uygulama kimliği: \(bundleID))"))
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
        // Toplam iş bilinmediği için her adımda bir birim ilerler; toplam da büyüyerek oran %95'i geçmez.
        // Sayı hiç durmasın: iOS ilerlemesi değişmeyen görevi takılmış sayabilir.
        completed += 1
        guard #available(iOS 26, *), let continued = task as? BGContinuedProcessingTask else { return }
        continued.progress.totalUnitCount = max(100, completed * 100 / 95 + 1)
        continued.progress.completedUnitCount = completed
        if let subtitle {
            continued.updateTitle(continued.title, subtitle: subtitle)
        }
    }

    func finish(success: Bool) {
        guard result == nil else { return }
        result = success
        if #available(iOS 26, *), let continued = task as? BGContinuedProcessingTask {
            continued.progress.completedUnitCount = continued.progress.totalUnitCount
        }
        task?.setTaskCompleted(success: success)
        task = nil
    }
}
