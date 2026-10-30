import Foundation

/// Asistanın üslup tercihleri. Modele talimat olarak gittiği için her sağlayıcıyla çalışır.
public struct Personalization: Codable, Equatable, Sendable {
    public enum Style: String, Codable, CaseIterable, Sendable {
        case standard, professional, friendly, candid, quirky, efficient, nerdy
    }

    public enum Level: String, Codable, CaseIterable, Sendable {
        case standard, more, less
    }

    public var style = Style.standard
    public var warmth = Level.standard
    public var enthusiasm = Level.standard
    public var emoji = Level.standard
    public var visualAnswers = Level.standard
    /// Asistan kayıtlı dokümanlarda arayabilsin.
    public var searchesDocuments = true

    public init() {}

    /// Sonradan eklenen alanlar eski kayıtlarda olmayabilir; eksikler varsayılan kalır.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = try container.decodeIfPresent(Style.self, forKey: .style) ?? .standard
        warmth = try container.decodeIfPresent(Level.self, forKey: .warmth) ?? .standard
        enthusiasm = try container.decodeIfPresent(Level.self, forKey: .enthusiasm) ?? .standard
        emoji = try container.decodeIfPresent(Level.self, forKey: .emoji) ?? .standard
        visualAnswers = try container.decodeIfPresent(Level.self, forKey: .visualAnswers) ?? .standard
        searchesDocuments = try container.decodeIfPresent(Bool.self, forKey: .searchesDocuments) ?? true
    }

    /// System prompt'a eklenen üslup talimatları; hepsi varsayılansa `nil`.
    var promptSection: String? {
        var lines: [String] = []
        switch style {
        case .standard: break
        case .professional: lines.append("Write in a polished, precise and professional tone.")
        case .friendly: lines.append("Write in a warm, chatty and friendly tone.")
        case .candid: lines.append("Be direct and encouraging; say plainly what you think.")
        case .quirky: lines.append("Be playful and imaginative.")
        case .efficient: lines.append("Be concise and plain; skip greetings and filler.")
        case .nerdy: lines.append("Be curious and exploratory; share interesting technical detail.")
        }
        switch warmth {
        case .standard: break
        case .more: lines.append("Be warmer and more personal.")
        case .less: lines.append("Be more neutral and matter-of-fact.")
        }
        switch enthusiasm {
        case .standard: break
        case .more: lines.append("Be more energetic and enthusiastic.")
        case .less: lines.append("Be calmer and more reserved.")
        }
        switch emoji {
        case .standard: break
        case .more: lines.append("Use emoji often.")
        case .less: lines.append("Avoid emoji.")
        }
        switch visualAnswers {
        case .standard: break
        case .more: lines.append("Prefer tables, and use create_artifact for charts or diagrams when they would help.")
        case .less: lines.append("Avoid tables, charts and artifacts unless the user asks for them.")
        }
        guard !lines.isEmpty else { return nil }
        return "The user's style preferences:\n" + lines.map { "- \($0)" }.joined(separator: "\n")
    }
}
