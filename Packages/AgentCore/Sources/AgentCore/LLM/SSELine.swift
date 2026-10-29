import Foundation

/// OpenAI streaming yanıtındaki tek bir SSE satırı.
///
/// URLSession'ın satır akışı boş satırları atladığı için olaylar boş satırla değil,
/// her `data:` satırı ayrı bir olay sayılarak ayrıştırılır (OpenAI tek satırlık `data` gönderir).
enum SSELine: Equatable {
    case data(String)
    case done
    case ignored

    init(_ line: String) {
        guard line.hasPrefix("data:") else {
            self = .ignored
            return
        }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        if payload == "[DONE]" {
            self = .done
        } else if payload.isEmpty {
            self = .ignored
        } else {
            self = .data(payload)
        }
    }
}
