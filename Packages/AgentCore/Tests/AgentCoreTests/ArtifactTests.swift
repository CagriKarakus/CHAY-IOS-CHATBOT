import Foundation
import Testing
@testable import AgentCore

private func arguments(_ title: String, _ html: String) throws -> String {
    String(decoding: try JSONEncoder().encode(["title": title, "html": html]), as: UTF8.self)
}

@Test func createsAndUpdatesArtifact() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ArtifactTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let tool = CreateArtifactTool(directory: directory)

    let first = try await tool.run(arguments: try arguments("Satış Grafiği", "<canvas id=c></canvas>"))
    let second = try await tool.run(arguments: try arguments("Satış Grafiği", "<html><body>v2</body></html>"))

    let url = try #require(first.files.first)
    #expect(url.lastPathComponent == "Satış Grafiği.html")
    #expect(first.content.hasPrefix("Artifact created: Satış Grafiği.html"))
    #expect(second.content.hasPrefix("Artifact updated"))
    #expect(try String(contentsOf: url, encoding: .utf8).hasSuffix("<html><body>v2</body></html>"))
    #expect(tool.activityDetail(for: try arguments("Oyun", "x")) == "Oyun")
}

@Test func wrapsFragmentsInDocument() {
    let page = CreateArtifactTool.document(title: "A <b>", html: "<p>Merhaba</p>")

    #expect(page.hasPrefix("<!doctype html>"))
    #expect(page.contains("<meta name=\"viewport\""))
    #expect(page.contains("<title>A &lt;b></title>"))
    #expect(page.contains("<p>Merhaba</p>"))
}

@Test func rejectsUnsafeArtifactNames() async throws {
    let tool = CreateArtifactTool(directory: FileManager.default.temporaryDirectory)

    await #expect(throws: ToolError.invalidFilename) {
        try await tool.run(arguments: try arguments("../evil", "<p>x</p>"))
    }
    await #expect(throws: ToolError.invalidArguments) {
        try await tool.run(arguments: try arguments("ok", "  "))
    }
}
