import Foundation
import Testing
@testable import AgentCore

/// Argümanları kaydeden ve sabit sonuç dönen sahte araç.
private struct EchoTool: Tool {
    let name = "echo"
    let description = "Test aracı"
    let parameters: JSONValue = ["type": "object"]
    var fails = false

    func activity(for arguments: String) -> String? { "Echo: \(arguments)" }

    func run(arguments: String) async throws -> ToolOutput {
        if fails { throw ToolError.http(status: 500) }
        return ToolOutput(content: "echo \(arguments)", sources: [Source(title: "Kaynak", url: URL(string: "https://a.com")!)])
    }
}

@Test func runsToolThenAnswers() async throws {
    let transport = ScriptedTransport([
        toolCallLines(id: "c1", name: "echo", arguments: #"{"x":1}"#),
        [#"data: {"choices":[{"delta":{"content":"Bitti"}}]}"#, "data: [DONE]"],
    ])
    let loop = AgentLoop(client: LLMClient(configuration: try makeConfiguration(), transport: transport), tools: [EchoTool()])

    let events = try await collect(loop.run([ChatMessage(role: .user, content: "Selam")]))

    let call = ToolCall(id: "c1", name: "echo", arguments: #"{"x":1}"#)
    #expect(events == [
        .message(ChatMessage(role: .assistant, content: nil, toolCalls: [call])),
        .toolStarted(id: "c1", name: "echo", activity: #"Echo: {"x":1}"#),
        .toolFinished(id: "c1", sources: [Source(title: "Kaynak", url: URL(string: "https://a.com")!)], files: [], failed: false),
        .message(ChatMessage(role: .tool, content: #"echo {"x":1}"#, toolCallID: "c1")),
        .text("Bitti"),
        .message(ChatMessage(role: .assistant, content: "Bitti")),
    ])

    // İkinci istek, araç çağrısını ve sonucunu geçmişte taşır.
    let messages = try #require(try transport.body(of: 1)["messages"] as? [[String: Any]])
    #expect(messages.count == 3)
    #expect(messages[2]["role"] as? String == "tool")
    #expect(messages[2]["tool_call_id"] as? String == "c1")
}

@Test func lastStepOffersNoTools() async throws {
    let alwaysCalls = toolCallLines(id: "c", name: "echo", arguments: "{}")
    let transport = ScriptedTransport([alwaysCalls, alwaysCalls, alwaysCalls])
    let loop = AgentLoop(client: LLMClient(configuration: try makeConfiguration(), transport: transport), tools: [EchoTool()], maxSteps: 2)

    _ = try await collect(loop.run([ChatMessage(role: .user, content: "Selam")]))

    #expect(transport.requests.count == 2)
    #expect(try transport.body(of: 0)["tools"] != nil)
    #expect(try transport.body(of: 1)["tools"] == nil)
}

@Test func toolErrorsGoBackToModel() async throws {
    let transport = ScriptedTransport([
        toolCallLines(id: "c1", name: "echo", arguments: "{}"),
        ["data: [DONE]"],
    ])
    let loop = AgentLoop(client: LLMClient(configuration: try makeConfiguration(), transport: transport), tools: [EchoTool(fails: true)])

    let events = try await collect(loop.run([]))

    #expect(events.contains(.toolFinished(id: "c1", sources: [], files: [], failed: true)))
    #expect(events.contains(.message(ChatMessage(role: .tool, content: "Hata: HTTP 500 hatası.", toolCallID: "c1"))))
}

@Test func unknownToolIsReported() async throws {
    let transport = ScriptedTransport([
        toolCallLines(id: "c1", name: "rm_rf", arguments: "{}"),
        ["data: [DONE]"],
    ])
    let loop = AgentLoop(client: LLMClient(configuration: try makeConfiguration(), transport: transport), tools: [EchoTool()])

    let events = try await collect(loop.run([]))

    #expect(events.contains(.message(ChatMessage(role: .tool, content: "Hata: 'rm_rf' adında bir araç yok.", toolCallID: "c1"))))
    #expect(transport.requests.count == 2)
}

@Test func systemPromptContainsDate() throws {
    let date = try #require(ISO8601DateFormatter().date(from: "2026-10-29T09:00:00Z"))

    let prompt = SystemPrompt.make(now: date, timeZone: try #require(TimeZone(identifier: "Europe/Istanbul")))

    #expect(prompt.contains("29 Ekim 2026"))
    #expect(prompt.contains("web_search"))
    #expect(!prompt.contains("kişisel talimatları"))
}

@Test func systemPromptAppendsUserInstructions() {
    let prompt = SystemPrompt.make(userInstructions: "  Emoji kullanma.\n")

    #expect(prompt.hasSuffix("Kullanıcının kişisel talimatları (bunlara her zaman uy):\nEmoji kullanma."))
}
