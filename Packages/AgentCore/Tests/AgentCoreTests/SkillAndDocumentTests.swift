import Foundation
import Testing
@testable import AgentCore

// MARK: - SKILL.md

private let sampleSkill = """
---
name: brand-guidelines
description: "Applies the company's colors and fonts to documents."
license: MIT
---

# Brand guidelines

Use #8B0000 for headings.
"""

@Test func parsesSkillMarkdown() throws {
    let skill = try #require(Skill.parse(markdown: sampleSkill))

    #expect(skill.name == "brand-guidelines")
    #expect(skill.description == "Applies the company's colors and fonts to documents.")
    #expect(skill.instructions == "# Brand guidelines\n\nUse #8B0000 for headings.")
}

@Test func parsesFoldedDescription() throws {
    let markdown = "---\r\nname: pdf\r\ndescription: >\r\n  Extracts text\r\n  from PDFs.\r\n---\r\nBody"

    let skill = try #require(Skill.parse(markdown: markdown))

    #expect(skill.description == "Extracts text from PDFs.")
    #expect(skill.instructions == "Body")
}

@Test(arguments: ["No front matter", "---\nname: x\n---\nbody", "---\ndescription: y\n---\nbody"])
func rejectsIncompleteSkills(_ markdown: String) {
    #expect(Skill.parse(markdown: markdown) == nil)
}

@Test func useSkillReturnsInstructions() async throws {
    let tool = UseSkillTool(skills: [Skill(name: "pdf", description: "d", instructions: "Step 1")])

    let output = try await tool.run(arguments: #"{"name":"PDF"}"#)
    let missing = try await tool.run(arguments: #"{"name":"other"}"#)

    #expect(output.content.contains("<skill name=\"pdf\">\nStep 1\n</skill>"))
    #expect(missing.content.hasPrefix("No skill named 'other'"))
    #expect(tool.activityDetail(for: #"{"name":"pdf"}"#) == "pdf")
}

@Test func systemPromptListsSkillsAndRespectsMemory() {
    let skills = [Skill(name: "pdf", description: "Works with PDFs.", instructions: "")]
    let notes = [Note(content: "Adı Çağrı.", createdAt: Date())]

    let withMemory = SystemPrompt.make(notes: notes, skills: skills)
    let withoutMemory = SystemPrompt.make(notes: notes, memoryEnabled: false)

    #expect(withMemory.contains("- pdf: Works with PDFs."))
    #expect(withMemory.contains("save_note"))
    #expect(withMemory.contains("Adı Çağrı."))
    #expect(!withoutMemory.contains("save_note"))
    #expect(!withoutMemory.contains("Adı Çağrı."))
    #expect(!withoutMemory.contains("Available skills"))
}

// MARK: - GitHub

/// URL'ye göre yanıt veren sahte transport.
private struct RoutedTransport: HTTPTransport {
    let routes: [String: (Int, String)]

    func lines(for request: HTTPRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let (status, body) = routes[request.url.absoluteString] ?? (404, "")
        return HTTPResponse(statusCode: status, contentType: nil, body: Data(body.utf8))
    }
}

@Test(arguments: [
    ("anthropics/skills", "anthropics", "skills"),
    ("https://github.com/anthropics/skills", "anthropics", "skills"),
    ("github.com/owner/my-repo.git", "owner", "my-repo"),
    (" https://github.com/a/b/tree/main/skills ", "a", "b"),
])
func parsesRepositoryNames(_ input: String, _ owner: String, _ repo: String) throws {
    let parsed = try #require(SkillRepository.parseRepository(input))
    #expect(parsed.owner == owner)
    #expect(parsed.repo == repo)
}

@Test(arguments: ["skills", "", "a/b c", "../x/y"])
func rejectsBadRepositoryNames(_ input: String) {
    #expect(SkillRepository.parseRepository(input) == nil)
}

@Test func fetchesSkillsFromRepository() async throws {
    let tree = #"{"tree":[{"path":"README.md","type":"blob"},{"path":"pdf/SKILL.md","type":"blob"},{"path":"docx/SKILL.md","type":"blob"},{"path":"broken/SKILL.md","type":"blob"},{"path":"pdf","type":"tree"}]}"#
    let transport = RoutedTransport(routes: [
        "https://api.github.com/repos/o/r/git/trees/HEAD?recursive=1": (200, tree),
        "https://raw.githubusercontent.com/o/r/HEAD/pdf/SKILL.md": (200, "---\nname: pdf\ndescription: PDFs\n---\nUse PDFs."),
        "https://raw.githubusercontent.com/o/r/HEAD/docx/SKILL.md": (200, "---\nname: docx\ndescription: Word\n---\nUse Word."),
        "https://raw.githubusercontent.com/o/r/HEAD/broken/SKILL.md": (200, "no front matter"),
    ])

    let found = try await SkillRepository.fetchSkills(from: "o/r", transport: transport)

    #expect(found.map(\.skill.name) == ["docx", "pdf"])
    #expect(found.first?.path == "docx/SKILL.md")
}

@Test func repositoryErrors() async throws {
    await #expect(throws: SkillRepository.RepositoryError.notFound) {
        try await SkillRepository.fetchSkills(from: "o/missing", transport: RoutedTransport(routes: [:]))
    }
    let limited = RoutedTransport(routes: ["https://api.github.com/repos/o/r/git/trees/HEAD?recursive=1": (403, "")])
    await #expect(throws: SkillRepository.RepositoryError.rateLimited) {
        try await SkillRepository.fetchSkills(from: "o/r", transport: limited)
    }
}

// MARK: - Doküman ekleri

@Test func documentsAreSentAsPlainText() throws {
    let document = Attachment(kind: .document, mimeType: "text/plain", data: Data("Sayfa 1 metni".utf8), name: "rapor.pdf")
    let message = ChatMessage(role: .user, content: "Özetle", attachments: [document])

    let body = try #require(try LLMClient(configuration: try makeConfiguration(), transport: MockTransport()).makeRequest([message]).body)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let content = try #require((json["messages"] as? [[String: Any]])?.first?["content"] as? String)

    #expect(content == "Özetle\n\n<document name=\"rapor.pdf\">\nSayfa 1 metni\n</document>")
}

@Test func documentsJoinTextPartWithImages() throws {
    let document = Attachment(kind: .document, mimeType: "text/plain", data: Data("x".utf8), name: "a.pdf")
    let image = Attachment(kind: .image, mimeType: "image/jpeg", data: Data([1]))
    let message = ChatMessage(role: .user, content: "", attachments: [document, image])

    let body = try #require(try LLMClient(configuration: try makeConfiguration(), transport: MockTransport()).makeRequest([message]).body)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let parts = try #require((json["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])

    #expect(parts.count == 2)
    #expect(parts[0]["text"] as? String == "<document name=\"a.pdf\">\nx\n</document>")
    #expect(parts[1]["type"] as? String == "image_url")
}

@Test func documentsCountByLength() {
    let document = Attachment(kind: .document, mimeType: "text/plain", data: Data(String(repeating: "a", count: 3_000).utf8))

    #expect(ContextCompactor.estimatedTokens([ChatMessage(role: .user, content: "", attachments: [document])]) == 1_000)
}
