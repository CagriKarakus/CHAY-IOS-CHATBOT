/// Sunucunun model listesindeki bir model ve (bildirildiyse) yetenekleri.
public struct ModelInfo: Equatable, Sendable {
    public let id: String
    /// Kabul ettiği girdiler ("text", "image", "audio"…); sunucu bildirmezse `nil`.
    public let inputModalities: [String]?
    /// Üretebildiği çıktılar; sunucu bildirmezse `nil`.
    public let outputModalities: [String]?
    /// Evren gibi sunucuların bildirdiği görev ("chat", görsel üretimi…).
    public let task: String?

    public init(id: String, inputModalities: [String]? = nil, outputModalities: [String]? = nil, task: String? = nil) {
        self.id = id
        self.inputModalities = inputModalities
        self.outputModalities = outputModalities
        self.task = task
    }

    /// Bilinmiyorsa `nil` (kullanıcı elle işaretler).
    public var acceptsImages: Bool? {
        inputModalities.map { $0.contains { $0.lowercased() == "image" } }
    }

    public var acceptsAudio: Bool? {
        inputModalities.map { $0.contains { $0.lowercased() == "audio" } }
    }

    /// Görsel üreten model mi; çıktı modalitesi veya görev adından anlaşılır.
    public var generatesImages: Bool? {
        if let outputModalities {
            return outputModalities.contains { $0.lowercased() == "image" }
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
            task: model.task
        )
    }
}
