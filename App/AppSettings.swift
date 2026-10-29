import AgentCore
import Foundation
import Observation

/// LLM bağlantı ayarları. Base URL ve model UserDefaults'ta, API key Keychain'de tutulur.
@Observable @MainActor
final class AppSettings {
    private enum Keys {
        static let baseURL = "llm.baseURL"
        static let model = "llm.model"
        static let apiKey = "llm.apiKey"
    }

    private(set) var baseURL: String
    private(set) var model: String
    private(set) var apiKey: String

    init() {
        baseURL = UserDefaults.standard.string(forKey: Keys.baseURL) ?? ""
        model = UserDefaults.standard.string(forKey: Keys.model) ?? ""
        apiKey = Keychain.read(Keys.apiKey) ?? ""
    }

    var isConfigured: Bool {
        (try? configuration()) != nil
    }

    func configuration() throws -> LLMConfiguration {
        try LLMConfiguration(baseURL: baseURL, apiKey: apiKey, model: model)
    }

    /// Doğrulanmış ayarları kaydeder.
    func save(_ configuration: LLMConfiguration) {
        baseURL = configuration.baseURL.absoluteString
        model = configuration.model
        apiKey = configuration.apiKey
        UserDefaults.standard.set(baseURL, forKey: Keys.baseURL)
        UserDefaults.standard.set(model, forKey: Keys.model)
        Keychain.save(apiKey, for: Keys.apiKey)
    }
}
