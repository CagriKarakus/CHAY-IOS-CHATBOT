import AgentCore
import Foundation
import Observation

/// Uygulamaya eklenmiş bir skill.
struct InstalledSkill: Codable, Identifiable, Equatable {
    var id = UUID()
    var skill: Skill
    /// GitHub'dan geldiyse "owner/repo"; kullanıcı yazdıysa `nil`.
    var source: String?
    /// Yeni sohbetlerde varsayılan olarak açık mı.
    var enabledByDefault = true
}

/// Skill'ler cihazda bir JSON dosyasında (Application Support) tutulur.
@Observable @MainActor
final class SkillLibrary {
    private(set) var skills: [InstalledSkill] = []

    private static var fileURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("skills.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode([InstalledSkill].self, from: data) {
            skills = decoded
        }
    }

    /// Bir sohbetin seçimine göre kullanılacak skill'ler; seçim yoksa varsayılan açık olanlar.
    func active(in selection: Set<UUID>?) -> [InstalledSkill] {
        skills.filter { selection?.contains($0.id) ?? $0.enabledByDefault }
    }

    /// Aynı adlı skill varsa yerine koyar.
    func add(_ newSkills: [Skill], source: String?) {
        for skill in newSkills {
            if let index = skills.firstIndex(where: { $0.skill.name == skill.name }) {
                skills[index].skill = skill
                skills[index].source = source
            } else {
                skills.append(InstalledSkill(skill: skill, source: source))
            }
        }
        save()
    }

    /// Yedekten gelenleri ekler; aynı adlı skill varsa atlar. Eklenen sayıyı döndürür.
    func importSkills(_ incoming: [InstalledSkill]) -> Int {
        let new = incoming.filter { item in !skills.contains { $0.skill.name == item.skill.name } }
        skills += new
        save()
        return new.count
    }

    func update(_ installed: InstalledSkill) {
        if let index = skills.firstIndex(where: { $0.id == installed.id }) {
            skills[index] = installed
        } else {
            skills.append(installed)
        }
        save()
    }

    func delete(_ id: InstalledSkill.ID) {
        skills.removeAll { $0.id == id }
        save()
    }

    func setEnabledByDefault(_ enabled: Bool, for id: InstalledSkill.ID) {
        guard let index = skills.firstIndex(where: { $0.id == id }) else { return }
        skills[index].enabledByDefault = enabled
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(skills) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
