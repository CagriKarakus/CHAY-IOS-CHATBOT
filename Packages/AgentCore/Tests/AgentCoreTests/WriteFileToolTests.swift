import Foundation
import Testing
@testable import AgentCore

private func makeTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("WriteFileToolTests-\(UUID().uuidString)")
}

private func arguments(_ filename: String, _ content: String) throws -> String {
    String(decoding: try JSONEncoder().encode(["filename": filename, "content": content]), as: UTF8.self)
}

@Test func writesMarkdownFile() async throws {
    let directory = makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let tool = WriteFileTool(directory: directory)

    let output = try await tool.run(arguments: try arguments("Yapay Zeka Özeti.md", "# Başlık\n\nİçerik"))

    let url = try #require(output.files.first)
    #expect(url.lastPathComponent == "Yapay Zeka Özeti.md")
    #expect(try String(contentsOf: url, encoding: .utf8) == "# Başlık\n\nİçerik")
    #expect(output.content.contains("Dosya kaydedildi: Yapay Zeka Özeti.md"))
}

@Test func doesNotOverwriteExistingFile() async throws {
    let directory = makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let tool = WriteFileTool(directory: directory)

    _ = try await tool.run(arguments: try arguments("not.md", "ilk"))
    let second = try await tool.run(arguments: try arguments("not.md", "ikinci"))

    #expect(second.files.first?.lastPathComponent == "not (2).md")
    #expect(try String(contentsOf: directory.appendingPathComponent("not.md"), encoding: .utf8) == "ilk")
}

@Test(arguments: [
    ("ozet.md", "ozet.md"),
    ("ozet", "ozet.md"),
    ("rapor.txt", "rapor.md"),
    ("  Haftalık Plan (v2).MD ", "Haftalık Plan (v2).md"),
    ("a:b*c?.md", "abc.md"),
    (".gizli.md", "gizli.md"),
])
func sanitizesFilenames(_ raw: String, _ expected: String) throws {
    #expect(try WriteFileTool.sanitizedFilename(raw) == expected)
}

@Test(arguments: ["../ozet.md", "/etc/passwd", "alt/ozet.md", "C:\\ozet.md", "~/ozet.md", "", "  ", "***", ".md"])
func rejectsUnsafeFilenames(_ raw: String) {
    #expect(throws: ToolError.invalidFilename) {
        try WriteFileTool.sanitizedFilename(raw)
    }
}

@Test func writeFileActivityShowsCleanName() throws {
    let tool = WriteFileTool(directory: makeTemporaryDirectory())

    #expect(tool.activity(for: try arguments("rapor.txt", "")) == "Dosya yazılıyor: rapor.md")
}
