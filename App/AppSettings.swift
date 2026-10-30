import AgentCore
import Foundation
import Observation

/// Bir OpenAI-uyumlu endpoint ve altında kullanılan modeller. API key Keychain'de, provider kimliğiyle tutulur.
struct Provider: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var baseURL: String
    var models: [ModelProfile]
    /// Başlangıçta seçilen hazır ayar (`ProviderPreset.id`); bakiye gösterimi gibi sağlayıcıya özel işler için.
    var preset: String?
    /// Bu sağlayıcı yoğunken veya çalışmazken sırayla denenecek modeller. Eski kayıtlarda yok.
    var fallbackModelIDs: [UUID]?
    /// Sağlayıcının yerleşik araçları (ör. web araması); `nil` = açık. Eski kayıtlarda yok.
    var usesBuiltInFeatures: Bool?

    /// Kullanıcı ayarından bağımsız olarak sağlayıcının sunduğu yerleşik araçlar.
    var availableServerTools: ServerTools? {
        (ProviderPreset.preset(id: preset) ?? ProviderPreset.matching(baseURL: baseURL))?.serverTools
    }
}

struct ModelProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// Model `reasoning_effort` destekliyorsa sohbet ekranında efor seçilebilir.
    var supportsEffort = false
    /// `nil` = modelin varsayılanı.
    var effort: ReasoningEffort?
    // Yetenekler; `nil` = bilinmiyor (kapalı sayılır). Opsiyonel olmaları eski kayıtların açılabilmesi için.
    var acceptsImages: Bool?
    var acceptsAudio: Bool?
    var generatesImages: Bool?
    /// Bağlam penceresi (token); sunucunun model kartından gelir, sıkıştırma eşiği için.
    var contextLength: Int?
    /// Araç çağırabilir mi; `nil` = bilinmiyor, araçlar gönderilir. Eski kayıtlarda yok.
    var supportsTools: Bool?
    /// Token limitleri (giriş + çıkış); `nil` = limitsiz.
    var dailyTokenLimit: Int?
    var monthlyTokenLimit: Int?
    /// Limit dolunca istekleri karşılayan model; `nil` ise o an kullanıcıya sorulur.
    var limitFallbackID: UUID?

    /// Sunucunun bildirdiği yetenekleri uygular. `overwrite: false` ise sadece henüz ayarlanmamış olanları doldurur.
    mutating func apply(_ info: ModelInfo, overwrite: Bool = true) {
        if let value = info.acceptsImages, overwrite || acceptsImages == nil { acceptsImages = value }
        if let value = info.acceptsAudio, overwrite || acceptsAudio == nil { acceptsAudio = value }
        if let value = info.generatesImages, overwrite || generatesImages == nil { generatesImages = value }
        if let value = info.supportsReasoningEffort, overwrite || !supportsEffort { supportsEffort = value }
        if let value = info.contextLength, overwrite || contextLength == nil { contextLength = value }
        if let value = info.supportsTools, overwrite || supportsTools == nil { supportsTools = value }
    }
}

/// Seçim listelerinde bir model ve sağlayıcısı.
struct ModelOption: Identifiable {
    let provider: Provider
    let model: ModelProfile
    var id: UUID { model.id }
}

/// Token limitinin dönemi; takvim günü ve ayı (cihazın saat dilimiyle).
enum TokenLimitPeriod: String, Codable {
    case day, month

    var title: String {
        switch self {
        case .day: L("daily", "günlük")
        case .month: L("monthly", "aylık")
        }
    }
}

/// Sağlayıcılar, seçili model ve genel ayarlar. Gizli olmayanlar UserDefaults'ta, API key'ler Keychain'de.
@Observable @MainActor
final class AppSettings {
    private enum Keys {
        static let providers = "llm.providers"
        static let selectedModel = "llm.selectedModel"
        static let tavilyKey = "tavily.apiKey"
        static let braveKey = "brave.apiKey"
        static let searchProvider = "search.provider"
        static let searxngURL = "search.searxngURL"
        static let userInstructions = "user.instructions"

        static func apiKey(_ provider: UUID) -> String { "provider.\(provider.uuidString).apiKey" }
        /// Ek HTTP başlıkları gizli değer içerebileceği için Keychain'de (JSON).
        static func headers(_ provider: UUID) -> String { "provider.\(provider.uuidString).headers" }

        // Tek sağlayıcılı eski sürümün anahtarları (taşıma için).
        static let legacyBaseURL = "llm.baseURL"
        static let legacyModel = "llm.model"
        static let legacyAPIKey = "llm.apiKey"
    }

    private(set) var providers: [Provider] = []
    private(set) var selectedModelID: UUID?
    private(set) var tavilyKey: String
    private(set) var searchProvider: SearchProvider
    private(set) var braveKey: String
    private(set) var searxngURL: String
    /// Her sohbette system prompt'a eklenen kişisel talimatlar (örn. "emoji kullanma").
    private(set) var userInstructions: String
    private var apiKeys: [UUID: String] = [:]
    private var extraHeaders: [UUID: [String: String]] = [:]

    init() {
        let defaults = UserDefaults.standard
        tavilyKey = Keychain.read(Keys.tavilyKey) ?? ""
        braveKey = Keychain.read(Keys.braveKey) ?? ""
        searchProvider = defaults.string(forKey: Keys.searchProvider).flatMap(SearchProvider.init(rawValue:)) ?? .tavily
        searxngURL = defaults.string(forKey: Keys.searxngURL) ?? ""
        userInstructions = defaults.string(forKey: Keys.userInstructions) ?? ""

        if let data = defaults.data(forKey: Keys.providers),
           let decoded = try? JSONDecoder().decode([Provider].self, from: data) {
            providers = decoded
            selectedModelID = defaults.string(forKey: Keys.selectedModel).flatMap(UUID.init(uuidString:))
        } else {
            migrateLegacySettings()
        }
        for provider in providers {
            apiKeys[provider.id] = Keychain.read(Keys.apiKey(provider.id)) ?? ""
            extraHeaders[provider.id] = Keychain.read(Keys.headers(provider.id))
                .flatMap { try? JSONDecoder().decode([String: String].self, from: Data($0.utf8)) } ?? [:]
        }
    }

    // MARK: - Seçim

    /// Seçili model; seçim silinmişse ilk model.
    var selected: (provider: Provider, model: ModelProfile)? {
        selection(for: nil)
    }

    /// Verilen model (ör. bir kestirmenin sohbetine özel); `nil` veya bulunamazsa seçili model.
    func selection(for modelID: UUID?) -> (provider: Provider, model: ModelProfile)? {
        let all = providers.flatMap { provider in provider.models.map { (provider: provider, model: $0) } }
        if let modelID, let match = all.first(where: { $0.model.id == modelID }) {
            return match
        }
        return all.first { $0.model.id == selectedModelID } ?? all.first
    }

    var isConfigured: Bool {
        (try? configuration()) != nil
    }

    func configuration(modelID: UUID? = nil) throws -> LLMConfiguration {
        guard let selected = selection(for: modelID) else { throw LLMError.missingModel }
        var configuration = try LLMConfiguration(
            baseURL: selected.provider.baseURL,
            apiKey: apiKey(for: selected.provider.id),
            model: selected.model.name,
            reasoningEffort: selected.model.supportsEffort ? selected.model.effort : nil,
            extraHeaders: headers(for: selected.provider.id)
        )
        if selected.provider.usesBuiltInFeatures != false, selected.model.supportsTools != false {
            configuration.serverTools = selected.provider.availableServerTools
        }
        return configuration
    }

    func headers(for providerID: UUID) -> [String: String] {
        extraHeaders[providerID] ?? [:]
    }

    func apiKey(for providerID: UUID) -> String {
        apiKeys[providerID] ?? ""
    }

    func select(_ modelID: UUID) {
        selectedModelID = modelID
        UserDefaults.standard.set(modelID.uuidString, forKey: Keys.selectedModel)
    }

    func setEffort(_ effort: ReasoningEffort?, for modelID: UUID) {
        for providerIndex in providers.indices {
            if let modelIndex = providers[providerIndex].models.firstIndex(where: { $0.id == modelID }) {
                providers[providerIndex].models[modelIndex].effort = effort
            }
        }
        persistProviders()
    }

    /// Limiti dolan modelin yedeğini kaydeder (limit anında kullanıcının seçtiği model).
    func setLimitFallback(_ fallbackID: UUID, for modelID: UUID) {
        for providerIndex in providers.indices {
            if let modelIndex = providers[providerIndex].models.firstIndex(where: { $0.id == modelID }) {
                providers[providerIndex].models[modelIndex].limitFallbackID = fallbackID
            }
        }
        persistProviders()
    }

    /// Tüm sağlayıcılardaki modeller.
    var allModels: [ModelOption] {
        providers.flatMap { provider in provider.models.map { ModelOption(provider: provider, model: $0) } }
    }

    /// Sağlayıcının sıralı yedekleri; silinmiş modeller atlanır.
    func fallbacks(for providerID: UUID) -> [ModelOption] {
        let ids = providers.first { $0.id == providerID }?.fallbackModelIDs ?? []
        return ids.compactMap { id in allModels.first { $0.model.id == id } }
    }

    /// Modeli sağlayıcının yedek listesinin sonuna ekler; zaten varsa yerinde kalır.
    func addFallback(_ modelID: UUID, to providerID: UUID) {
        guard let index = providers.firstIndex(where: { $0.id == providerID }) else { return }
        var ids = providers[index].fallbackModelIDs ?? []
        guard !ids.contains(modelID) else { return }
        ids.append(modelID)
        providers[index].fallbackModelIDs = ids
        persistProviders()
    }

    // MARK: - Düzenleme

    /// Sağlayıcıyı doğrulayıp ekler veya günceller.
    func save(_ provider: Provider, apiKey: String, headers: [String: String] = [:]) throws {
        var provider = provider
        let url = try LLMConfiguration.validatedBaseURL(provider.baseURL)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw LLMError.missingAPIKey }

        provider.baseURL = url.absoluteString
        provider.name = provider.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider.name.isEmpty { provider.name = url.host ?? L("Provider", "Sağlayıcı") }

        var seen = Set<String>()
        provider.models = provider.models.compactMap { model in
            var model = model
            model.name = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.name.isEmpty, seen.insert(model.name).inserted else { return nil }
            return model
        }

        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
        } else {
            providers.append(provider)
        }
        apiKeys[provider.id] = key
        Keychain.save(key, for: Keys.apiKey(provider.id))
        let cleanedHeaders = headers.filter {
            !$0.key.trimmingCharacters(in: .whitespaces).isEmpty && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty
        }
        extraHeaders[provider.id] = cleanedHeaders
        if cleanedHeaders.isEmpty {
            Keychain.delete(Keys.headers(provider.id))
        } else if let data = try? JSONEncoder().encode(cleanedHeaders) {
            Keychain.save(String(decoding: data, as: UTF8.self), for: Keys.headers(provider.id))
        }
        persistProviders()

        if selected?.model.id != selectedModelID, let first = selected?.model.id {
            select(first)
        }
    }

    func deleteProvider(_ id: UUID) {
        providers.removeAll { $0.id == id }
        apiKeys[id] = nil
        Keychain.delete(Keys.apiKey(id))
        Keychain.delete(Keys.headers(id))
        extraHeaders[id] = nil
        persistProviders()
    }

    /// Yedekten gelen sağlayıcıları ekler (key'siz; kullanıcı yeniden girer). Eklenen sayıyı döndürür.
    func importProviders(_ incoming: [Provider]) -> Int {
        let new = incoming.filter { provider in !providers.contains { $0.id == provider.id } }
        providers += new
        for provider in new { apiKeys[provider.id] = "" }
        persistProviders()
        return new.count
    }

    /// Kişisel talimat boşsa yedektekini kullanır; var olanın üzerine yazmaz.
    func importUserInstructions(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard userInstructions.isEmpty, !trimmed.isEmpty else { return }
        userInstructions = trimmed
        UserDefaults.standard.set(trimmed, forKey: Keys.userInstructions)
    }

    /// Asistanın web aramasında kullandığı servis.
    var searchBackend: SearchBackend {
        switch searchProvider {
        case .tavily: .tavily(apiKey: tavilyKey)
        case .brave: .brave(apiKey: braveKey)
        case .searxng: .searxng(baseURL: searxngURL)
        case .duckduckgo: .duckDuckGo
        }
    }

    /// Tavily veya Brave key/kota hatası verirse aramalar DuckDuckGo ile tekrarlanır.
    var searchFallback: SearchBackend? {
        switch searchProvider {
        case .tavily, .brave: .duckDuckGo
        case .searxng, .duckduckgo: nil
        }
    }

    func saveSearch(provider: SearchProvider, braveKey: String, searxngURL: String) {
        searchProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: Keys.searchProvider)

        self.searxngURL = searxngURL.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(self.searxngURL, forKey: Keys.searxngURL)

        self.braveKey = braveKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.braveKey.isEmpty {
            Keychain.delete(Keys.braveKey)
        } else {
            Keychain.save(self.braveKey, for: Keys.braveKey)
        }
    }

    func saveGeneral(tavilyKey: String, userInstructions: String) {
        self.userInstructions = userInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(self.userInstructions, forKey: Keys.userInstructions)

        self.tavilyKey = tavilyKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.tavilyKey.isEmpty {
            Keychain.delete(Keys.tavilyKey)
        } else {
            Keychain.save(self.tavilyKey, for: Keys.tavilyKey)
        }
    }

    private func persistProviders() {
        if let data = try? JSONEncoder().encode(providers) {
            UserDefaults.standard.set(data, forKey: Keys.providers)
        }
    }

    /// Eski tek sağlayıcılı ayarları ilk sağlayıcı olarak taşır; key'i yeniden girmek gerekmez.
    private func migrateLegacySettings() {
        let defaults = UserDefaults.standard
        guard let baseURL = defaults.string(forKey: Keys.legacyBaseURL), !baseURL.isEmpty else { return }

        let modelName = defaults.string(forKey: Keys.legacyModel) ?? ""
        let model = ModelProfile(name: modelName)
        let provider = Provider(
            name: URL(string: baseURL)?.host ?? L("Provider", "Sağlayıcı"),
            baseURL: baseURL,
            models: modelName.isEmpty ? [] : [model]
        )
        providers = [provider]
        if let key = Keychain.read(Keys.legacyAPIKey) {
            Keychain.save(key, for: Keys.apiKey(provider.id))
            Keychain.delete(Keys.legacyAPIKey)
        }
        persistProviders()
        if !modelName.isEmpty {
            select(model.id)
        }
        defaults.removeObject(forKey: Keys.legacyBaseURL)
        defaults.removeObject(forKey: Keys.legacyModel)
    }
}

extension ReasoningEffort {
    var title: String {
        switch self {
        case .low: L("Low", "Düşük")
        case .medium: L("Medium", "Orta")
        case .high: L("High", "Yüksek")
        }
    }
}

/// Ayarlar'da seçilen arama servisi.
enum SearchProvider: String, CaseIterable, Identifiable {
    case tavily, brave, searxng, duckduckgo

    var id: String { rawValue }

    init(_ backend: SearchBackend) {
        switch backend {
        case .tavily: self = .tavily
        case .brave: self = .brave
        case .searxng: self = .searxng
        case .duckDuckGo: self = .duckduckgo
        }
    }

    var title: String {
        switch self {
        case .tavily: "Tavily"
        case .brave: "Brave Search"
        case .searxng: "SearXNG"
        case .duckduckgo: L("DuckDuckGo (no key)", "DuckDuckGo (anahtarsız)")
        }
    }
}
