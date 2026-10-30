import Foundation

/// Web yanıtının metni: sunucunun veya sayfanın bildirdiği karakter kodlamasıyla çözülür.
enum WebText {
    static func decode(_ data: Data, contentType: String?) -> String {
        let declared = charset(in: contentType ?? "") ?? charset(in: String(decoding: data.prefix(2_048), as: UTF8.self))
        if let encoding = declared.flatMap(encoding(named:)), let text = String(data: data, encoding: encoding) {
            return text
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        // Kodlama bildirilmemiş ve UTF-8 değil: eski Türkçe sayfaların çoğu Windows-1254'tür.
        return String(data: data, encoding: .windowsCP1254) ?? String(decoding: data, as: UTF8.self)
    }

    /// `charset=…` değeri (`Content-Type` başlığı veya sayfanın `<meta>` etiketi).
    static func charset(in text: String) -> String? {
        guard let range = text.range(of: #"charset\s*=\s*["']?[a-zA-Z0-9_-]+"#, options: [.regularExpression, .caseInsensitive]),
              let separator = text[range].firstIndex(of: "=")
        else { return nil }
        return text[range][text.index(after: separator)...]
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'"))
            .lowercased()
    }

    /// Tarayıcılar gibi: ISO-8859-9 Windows-1254, ISO-8859-1 Windows-1252 olarak okunur.
    private static func encoding(named name: String) -> String.Encoding? {
        switch name {
        case "utf-8", "utf8": .utf8
        case "windows-1254", "cp1254", "iso-8859-9", "latin5": .windowsCP1254
        case "windows-1252", "cp1252", "iso-8859-1", "latin1": .windowsCP1252
        case "windows-1250", "cp1250": .windowsCP1250
        case "windows-1251", "cp1251": .windowsCP1251
        case "windows-1253", "cp1253": .windowsCP1253
        default: nil
        }
    }
}
