import AgentCore
import Foundation
import Observation

/// Bir OpenAI-uyumlu endpoint ve altında kullanılan modeller. API key Keychain'de, provider kimliğiyle tutulur.
struct Provider: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var baseURL: String
    var models: [ModelProfile]
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

    /// Sunucunun bildirdiği yetenekleri uygular. `overwrite: false` ise sadece henüz ayarlanmamış olanları doldurur.
    mutating func apply(_ info: ModelInfo, overwrite: Bool = true) {
        if let value = info.acceptsImages, overwrite || acceptsImages == nil { acceptsImages = value }
        if let value = info.acceptsAudio, overwrite || acceptsAudio == nil { acceptsAudio = value }
        if let value = info.generatesImages, overwrite || generatesImages == nil { generatesImages = value }
    }
}

/// Sağlayıcılar, seçili model ve genel ayarlar. Gizli olmayanlar UserDefaults'ta, API key'ler Keychain'de.
@Observable @MainActor
final class AppSettings {
    private enum Keys {
        static let providers = "llm.providers"
        static let selectedModel = "llm.selectedModel"
        static let tavilyKey = "tavily.apiKey"
        static let userInstructions = "user.instructions"

        static func apiKey(_ provider: UUID) -> String { "provider.\(provider.uuidString).apiKey" }

        // Tek sağlayıcılı eski sürümün anahtarları (taşıma için).
        static let legacyBaseURL = "llm.baseURL"
        static let legacyModel = "llm.model"
        static let legacyAPIKey = "llm.apiKey"
    }

    private(set) var providers: [Provider] = []
    private(set) var selectedModelID: UUID?
    private(set) var tavilyKey: String
    /// Her sohbette system prompt'a eklenen kişisel talimatlar (örn. "emoji kullanma").
    private(set) var userInstructions: String
    private var apiKeys: [UUID: String] = [:]

    init() {
        let defaults = UserDefaults.standard
        tavilyKey = Keychain.read(Keys.tavilyKey) ?? ""
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
        }
    }

    // MARK: - Seçim

    /// Seçili model; seçim silinmişse ilk model.
    var selected: (provider: Provider, model: ModelProfile)? {
        let all = providers.flatMap { provider in provider.models.map { (provider: provider, model: $0) } }
        return all.first { $0.model.id == selectedModelID } ?? all.first
    }

    var isConfigured: Bool {
        (try? configuration()) != nil
    }

    func configuration() throws -> LLMConfiguration {
        guard let selected else { throw LLMError.missingModel }
        return try LLMConfiguration(
            baseURL: selected.provider.baseURL,
            apiKey: apiKey(for: selected.provider.id),
            model: selected.model.name,
            reasoningEffort: selected.model.supportsEffort ? selected.model.effort : nil
        )
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

    // MARK: - Düzenleme

    /// Sağlayıcıyı doğrulayıp ekler veya günceller.
    func save(_ provider: Provider, apiKey: String) throws {
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
        persistProviders()

        if selected?.model.id != selectedModelID, let first = selected?.model.id {
            select(first)
        }
    }

    func deleteProvider(_ id: UUID) {
        providers.removeAll { $0.id == id }
        apiKeys[id] = nil
        Keychain.delete(Keys.apiKey(id))
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
