import Foundation
import Observation

/// Sık kullanılan bir istek; giriş kutusuna tek dokunuşla eklenir.
struct SavedPrompt: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var text: String
}

/// Hazır komutlar (UserDefaults'ta). İlk açılışta birkaç örnek eklenir.
@Observable @MainActor
final class PromptLibrary {
    private static let storageKey = "prompts.saved"
    private(set) var prompts: [SavedPrompt] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([SavedPrompt].self, from: data) {
            prompts = decoded
        } else {
            prompts = [
                SavedPrompt(title: L("Make it formal", "Resmi dile çevir"),
                            text: L("Rewrite the following text in a formal, polite tone:\n\n", "Aşağıdaki metni resmi ve kibar bir dille yeniden yaz:\n\n")),
                SavedPrompt(title: L("Draft an email", "E-posta taslağı"),
                            text: L("Write a short, clear email draft about:\n\n", "Şu konuda kısa ve net bir e-posta taslağı yaz:\n\n")),
                SavedPrompt(title: L("Summarize", "Özetle"),
                            text: L("Summarize the following in 5 bullet points:\n\n", "Aşağıdakini 5 maddede özetle:\n\n")),
                SavedPrompt(title: L("Translate to English", "İngilizceye çevir"),
                            text: L("Translate the following into natural English:\n\n", "Aşağıdakini doğal bir İngilizceye çevir:\n\n")),
            ]
            save()
        }
    }

    func update(_ prompt: SavedPrompt) {
        if let index = prompts.firstIndex(where: { $0.id == prompt.id }) {
            prompts[index] = prompt
        } else {
            prompts.append(prompt)
        }
        save()
    }

    func delete(at offsets: IndexSet) {
        prompts.remove(atOffsets: offsets)
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        prompts.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Yedekten gelenleri ekler; aynı başlık ve metinli olanları atlar. Eklenen sayıyı döndürür.
    func importPrompts(_ incoming: [SavedPrompt]) -> Int {
        let new = incoming.filter { item in !prompts.contains { $0.title == item.title && $0.text == item.text } }
        prompts += new
        save()
        return new.count
    }

    private func save() {
        if let data = try? JSONEncoder().encode(prompts) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
