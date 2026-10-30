import Foundation

/// Sohbetten yedek model seçer. Eşleştirme ve kayıt uygulama tarafında yapılır; sonuç modele metin olarak döner.
public struct SetFallbackModelTool: Tool {
    private struct Arguments: Decodable {
        let model: String
        let provider: String?
    }

    /// (model adı, sağlayıcı adı) alır, kullanıcıya aktarılacak sonucu döndürür.
    public typealias Apply = @Sendable (String, String?) async -> String

    public let name = "set_fallback_model"
    public let description = "Adds a model to a provider's fallback list. It is used automatically when that provider is overloaded or down. Use it when the user asks to set a fallback or backup model."
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [
            "model": ["type": "string", "description": "Name of a model saved in the app"],
            "provider": ["type": "string", "description": "Provider or router the fallback is for. Leave it out for the current provider."],
        ],
        "required": ["model"],
    ]

    /// Web içeriği okunduysa kullanıcıdan onay istenir; sayfadaki bir talimat ayarı değiştiremesin.
    public let requiresApprovalAfterUntrustedContent = true

    private let apply: Apply

    public init(apply: @escaping Apply) {
        self.apply = apply
    }

    public func activityDetail(for arguments: String) -> String? {
        (try? decodeArguments(Arguments.self, from: arguments))?.model
    }

    public func run(arguments: String) async throws -> ToolOutput {
        let arguments = try decodeArguments(Arguments.self, from: arguments)
        return ToolOutput(content: await apply(arguments.model, arguments.provider))
    }
}
