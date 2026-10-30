import AgentCore
import Foundation
import Observation

/// Sağlayıcı ve model bazında toplam token kullanımı ve Tavily arama sayısı (cihazda, UserDefaults'ta).
@Observable @MainActor
final class UsageTracker {
    struct Totals: Codable, Equatable {
        var promptTokens = 0
        var completionTokens = 0
        /// Model çağrısı sayısı (bir cevap, araç kullanımına göre birkaç çağrı yapabilir).
        var requests = 0

        var totalTokens: Int { promptTokens + completionTokens }

        static func + (lhs: Totals, rhs: Totals) -> Totals {
            Totals(
                promptTokens: lhs.promptTokens + rhs.promptTokens,
                completionTokens: lhs.completionTokens + rhs.completionTokens,
                requests: lhs.requests + rhs.requests
            )
        }
    }

    /// Bir modelin içinde bulunulan gün ve aydaki tokenları (limitler için).
    private struct PeriodUsage: Codable {
        var day = ""
        var dayTokens = 0
        var month = ""
        var monthTokens = 0
    }

    private struct Snapshot: Codable {
        /// Anahtar: "<provider id>|<model adı>".
        var models: [String: Totals] = [:]
        var tavilySearches = 0
        /// Tavily dışındaki servislerin arama sayıları (`SearchProvider.rawValue`); eski kayıtlarda yok.
        var otherSearches: [String: Int]?
        /// Sağlayıcının bildirdiği günlük kalan token (anahtar: provider id); eski kayıtlarda yok.
        var dailyRemaining: [String: DailyRemaining]?
        /// Sağlayıcıların kendi yaptığı web aramaları; eski kayıtlarda yok.
        var providerSearches: Int?
        /// Model başına günlük/aylık token (anahtar: model id); eski kayıtlarda yok.
        var periods: [String: PeriodUsage]?
        var since = Date()
    }

    private static let storageKey = "usage.totals"
    private var snapshot: Snapshot

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = decoded
        } else {
            snapshot = Snapshot()
        }
    }

    var tavilySearches: Int { snapshot.tavilySearches }

    /// Bu cihazdan, verilen servisle yapılan başarılı arama sayısı.
    func searches(with provider: SearchProvider) -> Int {
        provider == .tavily ? snapshot.tavilySearches : snapshot.otherSearches?[provider.rawValue] ?? 0
    }
    var since: Date { snapshot.since }

    func totals(providerID: UUID, model: String) -> Totals {
        snapshot.models[Self.key(providerID, model)] ?? Totals()
    }

    func totals(providerID: UUID) -> Totals {
        snapshot.models
            .filter { $0.key.hasPrefix(providerID.uuidString + "|") }
            .values
            .reduce(Totals(), +)
    }

    func record(_ usage: TokenUsage, providerID: UUID, model: String, modelID: UUID? = nil) {
        var totals = totals(providerID: providerID, model: model)
        totals.promptTokens += usage.promptTokens
        totals.completionTokens += usage.completionTokens
        totals.requests += 1
        snapshot.models[Self.key(providerID, model)] = totals

        if let modelID {
            let now = Date.now
            var period = snapshot.periods?[modelID.uuidString] ?? PeriodUsage()
            if period.day != Self.dayKey(now) {
                period.day = Self.dayKey(now)
                period.dayTokens = 0
            }
            if period.month != Self.monthKey(now) {
                period.month = Self.monthKey(now)
                period.monthTokens = 0
            }
            period.dayTokens += usage.promptTokens + usage.completionTokens
            period.monthTokens += usage.promptTokens + usage.completionTokens
            snapshot.periods = snapshot.periods ?? [:]
            snapshot.periods?[modelID.uuidString] = period
        }
        save()
    }

    /// Modelin bugün veya bu ay kullandığı token (giriş + çıkış).
    func tokens(modelID: UUID, in period: TokenLimitPeriod, now: Date = .now) -> Int {
        guard let usage = snapshot.periods?[modelID.uuidString] else { return 0 }
        switch period {
        case .day: return usage.day == Self.dayKey(now) ? usage.dayTokens : 0
        case .month: return usage.month == Self.monthKey(now) ? usage.monthTokens : 0
        }
    }

    /// Modelin dolmuş limiti (önce günlük); limit yoksa veya dolmadıysa `nil`.
    func exceededLimit(of model: ModelProfile) -> TokenLimitPeriod? {
        if let limit = model.dailyTokenLimit, tokens(modelID: model.id, in: .day) >= limit { return .day }
        if let limit = model.monthlyTokenLimit, tokens(modelID: model.id, in: .month) >= limit { return .month }
        return nil
    }

    private static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func monthKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    struct DailyRemaining: Codable, Equatable {
        let tokens: Int
        let updatedAt: Date
    }

    /// Son yanıtta bildirilen günlük kalan token.
    func dailyRemaining(providerID: UUID) -> DailyRemaining? {
        snapshot.dailyRemaining?[providerID.uuidString]
    }

    func recordDailyRemaining(_ tokens: Int, providerID: UUID) {
        snapshot.dailyRemaining = snapshot.dailyRemaining ?? [:]
        snapshot.dailyRemaining?[providerID.uuidString] = DailyRemaining(tokens: tokens, updatedAt: .now)
        save()
    }

    func recordSearch(with provider: SearchProvider) {
        if provider == .tavily {
            snapshot.tavilySearches += 1
        } else {
            snapshot.otherSearches = snapshot.otherSearches ?? [:]
            snapshot.otherSearches?[provider.rawValue, default: 0] += 1
        }
        save()
    }

    var providerSearches: Int { snapshot.providerSearches ?? 0 }

    func recordProviderSearches(_ count: Int) {
        snapshot.providerSearches = providerSearches + count
        save()
    }

    func reset() {
        snapshot = Snapshot()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private static func key(_ providerID: UUID, _ model: String) -> String {
        "\(providerID.uuidString)|\(model)"
    }
}
