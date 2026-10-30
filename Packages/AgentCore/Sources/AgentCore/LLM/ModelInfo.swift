import Foundation

/// Sunucunun model listesindeki bir model ve (bildirildiyse) yetenekleri.
public struct ModelInfo: Equatable, Sendable {
    public let id: String
    /// Kabul ettiği girdiler ("text", "image", "audio"…); sunucu bildirmezse `nil`.
    public let inputModalities: [String]?
    /// Üretebildiği çıktılar; sunucu bildirmezse `nil`.
    public let outputModalities: [String]?
    /// Evren gibi sunucuların bildirdiği görev ("chat", görsel üretimi…).
    public let task: String?
    /// Model kartında (`GET /models/{id}`) bildirildiyse `reasoning_effort` desteği.
    public let supportsReasoningEffort: Bool?
    /// Model kartında bildirildiyse bağlam penceresi (token).
    public let contextLength: Int?
    /// Sunucu bildirdiyse modelin kabul ettiği istek alanları (`tools` vb.).
    public let supportedParameters: [String]?

    public init(
        id: String,
        inputModalities: [String]? = nil,
        outputModalities: [String]? = nil,
        task: String? = nil,
        supportsReasoningEffort: Bool? = nil,
        contextLength: Int? = nil,
        supportedParameters: [String]? = nil
    ) {
        self.id = id
        self.inputModalities = inputModalities
        self.outputModalities = outputModalities
        self.task = task
        self.supportsReasoningEffort = supportsReasoningEffort
        self.contextLength = contextLength
        self.supportedParameters = supportedParameters
    }

    /// Bilinmiyorsa `nil` (kullanıcı elle işaretler).
    public var acceptsImages: Bool? {
        inputModalities.map { $0.contains { $0.lowercased() == "image" } }
    }

    public var acceptsAudio: Bool? {
        inputModalities.map { $0.contains { $0.lowercased() == "audio" } }
    }

    /// Araç çağırabilir mi; sunucu bildirmediyse `nil` (araçlar gönderilmeye devam eder).
    public var supportsTools: Bool? {
        supportedParameters.map { $0.contains("tools") }
    }

    /// Sadece görsel üreten (`/images/generations` ile çalışan) model mi; çıktı modalitesi veya görev adından anlaşılır.
    /// Hem metin hem görsel üreten modeller (ör. OpenRouter'daki Gemini) sohbet modeli sayılır.
    public var generatesImages: Bool? {
        if let outputModalities {
            let outputs = Set(outputModalities.map { $0.lowercased() })
            return outputs.contains("image") && !outputs.contains("text")
        }
        guard let task = task?.lowercased() else { return nil }
        return task.contains("image") && !task.contains("to-text")
    }
}

extension ModelInfo {
    init(_ model: ModelList.Model) {
        self.init(
            id: model.id,
            inputModalities: model.architecture?.input_modalities ?? model.modalities,
            outputModalities: model.architecture?.output_modalities,
            task: model.task,
            supportedParameters: model.supported_parameters
        )
    }
}

/// `GET /models/{id}` yanıtı (Evren gibi sunucuların model kartı): bağlam ve yetenekler.
struct ModelCard: Decodable {
    struct Capabilities: Decodable {
        let reasoning_effort: Bool?
        let vision: Bool?
    }
    let id: String
    let task: String?
    let modalities: [String]?
    let context_length: Int?
    let capabilities: Capabilities?

    var info: ModelInfo {
        var inputs = modalities
        if inputs == nil, let vision = capabilities?.vision {
            inputs = vision ? ["text", "image"] : ["text"]
        }
        return ModelInfo(
            id: id,
            inputModalities: inputs,
            task: task,
            supportsReasoningEffort: capabilities?.reasoning_effort,
            contextLength: context_length
        )
    }
}
