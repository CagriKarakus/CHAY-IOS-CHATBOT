import AgentCore
import Foundation
import Observation

/// Bağlantı ayarları. Base URL ve model UserDefaults'ta, API key'ler Keychain'de tutulur.
@Observable @MainActor
final class AppSettings {
    private enum Keys {
        static let baseURL = "llm.baseURL"
        static let model = "llm.model"
        static let apiKey = "llm.apiKey"
        static let tavilyKey = "tavily.apiKey"
    }

    private(set) var baseURL: String
    private(set) var model: String
    private(set) var apiKey: String
    private(set) var tavilyKey: String

    init() {
        baseURL = UserDefaults.standard.string(forKey: Keys.baseURL) ?? ""
        model = UserDefaults.standard.string(forKey: Keys.model) ?? ""
        apiKey = Keychain.read(Keys.apiKey) ?? ""
        tavilyKey = Keychain.read(Keys.tavilyKey) ?? ""
    }

    var isConfigured: Bool {
        (try? configuration()) != nil
    }

    func configuration() throws -> LLMConfiguration {
        try LLMConfiguration(baseURL: baseURL, apiKey: apiKey, model: model)
    }

    /// Doğrulanmış LLM ayarlarını ve (isteğe bağlı) Tavily key'ini kaydeder.
    func save(_ configuration: LLMConfiguration, tavilyKey: String) {
        baseURL = configuration.baseURL.absoluteString
        model = configuration.model
        apiKey = configuration.apiKey
        UserDefaults.standard.set(baseURL, forKey: Keys.baseURL)
        UserDefaults.standard.set(model, forKey: Keys.model)
        Keychain.save(apiKey, for: Keys.apiKey)

        self.tavilyKey = tavilyKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.tavilyKey.isEmpty {
            Keychain.delete(Keys.tavilyKey)
        } else {
            Keychain.save(self.tavilyKey, for: Keys.tavilyKey)
        }
    }
}
