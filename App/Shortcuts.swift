import AppIntents
import Foundation

/// Kestirmeler'den gelen, uygulama açılınca gönderilecek istek.
struct ShortcutRequest: Codable {
    let prompt: String
    let modelID: UUID?
}

/// Eylem ile sohbet ekranı arasındaki kutu: istek önce kaydedilir, ekran hazır olunca alınıp gönderilir.
enum ShortcutInbox {
    static let didReceive = Notification.Name("ShortcutInbox.didReceive")
    private static let key = "shortcut.pending"

    static func put(_ request: ShortcutRequest) {
        if let data = try? JSONEncoder().encode(request) {
            UserDefaults.standard.set(data, forKey: key)
        }
        NotificationCenter.default.post(name: didReceive, object: nil)
    }

    /// Bekleyen isteği alır ve siler (bir kez gönderilsin).
    static func take() -> ShortcutRequest? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        return try? JSONDecoder().decode(ShortcutRequest.self, from: data)
    }
}

/// Kestirmeler'de seçilebilen model.
struct ModelEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Model"
    static let defaultQuery = ModelQuery()

    let id: UUID
    let name: String
    let provider: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(provider)")
    }
}

struct ModelQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ModelEntity] {
        Self.all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ModelEntity] {
        Self.all()
    }

    /// Ayarlardaki sağlayıcı ve modeller (UserDefaults'tan okunur; key'ler gerekmez).
    static func all() -> [ModelEntity] {
        guard let data = UserDefaults.standard.data(forKey: "llm.providers"),
              let providers = try? JSONDecoder().decode([Provider].self, from: data)
        else { return [] }
        return providers.flatMap { provider in
            provider.models.map { ModelEntity(id: $0.id, name: $0.name, provider: provider.name) }
        }
    }
}

/// "CHAY'a sor": uygulamayı açar ve komutu seçilen modelle yeni bir sohbette gönderir.
/// Kestirmeler > Otomasyon > Günün Saati ile her sabah çalıştırılabilir.
struct AskCHAYIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask CHAY"
    static let description = IntentDescription("Opens CHAY and sends the prompt in a new chat, using the model you choose. For RSS news, put the feed URLs in the prompt.")
    static let openAppWhenRun = true

    @Parameter(title: "Prompt", inputOptions: String.IntentInputOptions(multiline: true))
    var prompt: String

    @Parameter(title: "Model")
    var model: ModelEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Ask CHAY \(\.$prompt)") {
            \.$model
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutInbox.put(ShortcutRequest(prompt: prompt, modelID: model?.id))
        return .result()
    }
}

struct CHAYShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskCHAYIntent(),
            phrases: ["Ask \(.applicationName)", "\(.applicationName)'a sor"],
            shortTitle: "Ask CHAY",
            systemImageName: "sparkle"
        )
    }
}
