import Foundation

/// Akarken Markdown'ı ikiye böler: bitmiş bloklar bir kez işlenir, sadece yazılmakta olan kısım her güncellemede çizilir.
public enum MarkdownStream {
    /// `stable`: son boş satıra kadar olan, açık kod bloğu içermeyen kısım. `tail`: kalanı.
    public static func split(_ text: String) -> (stable: String, tail: String) {
        var insideFence = false
        var boundary = text.startIndex
        var lineStart = text.startIndex
        var previousLineBlank = false

        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[lineStart..<lineEnd].trimmingCharacters(in: .whitespaces)
            let next = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                insideFence.toggle()
                // Kapanan kod bloğunun sonu da güvenli bir sınırdır.
                if !insideFence, lineEnd < text.endIndex { boundary = next }
            } else if !insideFence, line.isEmpty, !previousLineBlank, lineEnd < text.endIndex {
                boundary = next
            }
            previousLineBlank = line.isEmpty
            lineStart = next
        }
        return (String(text[..<boundary]), String(text[boundary...]))
    }
}
