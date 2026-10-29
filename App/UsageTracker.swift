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

    private struct Snapshot: Codable {
        /// Anahtar: "<provider id>|<model adı>".
        var models: [String: Totals] = [:]
        var tavilySearches = 0
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

    func record(_ usage: TokenUsage, providerID: UUID, model: String) {
        var totals = totals(providerID: providerID, model: model)
        totals.promptTokens += usage.promptTokens
        totals.completionTokens += usage.completionTokens
        totals.requests += 1
        snapshot.models[Self.key(providerID, model)] = totals
        save()
    }

    func recordSearch() {
        snapshot.tavilySearches += 1
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
