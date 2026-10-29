import Foundation
import Testing
@testable import AgentCore

func withoutUsage(_ events: [LLMStreamEvent]) -> [LLMStreamEvent] {
    events.filter { if case .usage = $0 { false } else { true } }
}

private func usages(_ events: [LLMStreamEvent]) -> [TokenUsage] {
    events.compactMap { if case let .usage(usage) = $0 { usage } else { nil } }
}

// MARK: - Token kullanımı

@Test func reportsUsageFromRecordedStream() async throws {
    let client = LLMClient(configuration: try makeConfiguration(), transport: MockTransport(responseLines: try fixtureLines("text-stream.sse")))

    let events = try await collect(client.streamChat([]))

    let usage = try #require(usages(events).first)
    #expect(usage.promptTokens == 22)
    #expect(usage.completionTokens == 176)
    #expect(usage.generationSeconds != nil)
    #expect(events.last.map { if case .usage = $0 { true } else { false } } == true)
}

@Test func noUsageEventWhenServerSendsNone() async throws {
    let lines = [#"data: {"choices":[{"delta":{"content":"a"}}]}"#, "data: [DONE]"]
    let client = LLMClient(configuration: try makeConfiguration(), transport: MockTransport(responseLines: lines))

    #expect(usages(try await collect(client.streamChat([]))).isEmpty)
}

@Test func requestsUsageInStream() throws {
    let body = try #require(try LLMClient(configuration: try makeConfiguration(), transport: MockTransport()).makeRequest([]).body)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

    #expect((json["stream_options"] as? [String: Any])?["include_usage"] as? Bool == true)
}

@Test func tokenUsageMathAndSpeed() {
    let first = TokenUsage(promptTokens: 100, completionTokens: 50, generationSeconds: 1)
    let second = TokenUsage(promptTokens: 200, completionTokens: 150, generationSeconds: nil)

    let total = first + second

    #expect(total == TokenUsage(promptTokens: 300, completionTokens: 200, generationSeconds: 1))
    #expect(total.totalTokens == 500)
    #expect(total.tokensPerSecond == 200)
    #expect(TokenUsage(promptTokens: 1, completionTokens: 10, generationSeconds: 0).tokensPerSecond == nil)
}

@Test func agentLoopForwardsUsage() async throws {
    let transport = ScriptedTransport([[
        #"data: {"choices":[{"delta":{"content":"a"}}]}"#,
        #"data: {"choices":[],"usage":{"prompt_tokens":7,"completion_tokens":3}}"#,
        "data: [DONE]",
    ]])
    let loop = AgentLoop(client: LLMClient(configuration: try makeConfiguration(), transport: transport), tools: [])

    let events = try await collect(loop.run([]))

    #expect(events.contains { if case let .usage(usage) = $0 { usage.promptTokens == 7 && usage.completionTokens == 3 } else { false } })
}

// MARK: - İptal sonrası geçmiş

@Test func closesUnansweredToolCallsAfterCancel() {
    let history = [
        ChatMessage(role: .user, content: "Ara"),
        ChatMessage(role: .assistant, content: nil, toolCalls: [
            ToolCall(id: "a", name: "web_search", arguments: "{}"),
            ToolCall(id: "b", name: "fetch_page", arguments: "{}"),
        ]),
        ChatMessage(role: .tool, content: "sonuç", toolCallID: "a"),
    ]

    let repaired = history.closingUnansweredToolCalls()

    #expect(repaired.count == 4)
    #expect(repaired.last == ChatMessage(role: .tool, content: "İptal edildi.", toolCallID: "b"))
    #expect(repaired.closingUnansweredToolCalls() == repaired)
    let plain = [ChatMessage(role: .user, content: "Selam"), ChatMessage(role: .assistant, content: "Merhaba")]
    #expect(plain.closingUnansweredToolCalls() == plain)
}

// MARK: - Bağlam sıkıştırma

private let longPage = "<untrusted_content source=\"x\">\n" + String(repeating: "a", count: 2_000)

@Test func trimsOnlyOldToolResults() {
    let history = [
        ChatMessage(role: .user, content: "1"),
        ChatMessage(role: .tool, content: longPage, toolCallID: "old"),
        ChatMessage(role: .assistant, content: "cevap"),
        ChatMessage(role: .user, content: "2"),
        ChatMessage(role: .tool, content: longPage, toolCallID: "new"),
    ]

    let trimmed = ContextCompactor.trimmingOldToolResults(history, maxCharacters: 100)

    #expect(trimmed[1].content?.count == 100 + "\n[…kısaltıldı]".count)
    #expect(trimmed[1].content?.hasPrefix("<untrusted_content") == true)
    #expect(trimmed[4].content == longPage)
    #expect(Array(trimmed[0...0]) + Array(trimmed[2...3]) == Array(history[0...0]) + Array(history[2...3]))
}

@Test func splitsAtUserTurns() {
    let history = [
        ChatMessage(role: .user, content: "1"),
        ChatMessage(role: .assistant, content: nil, toolCalls: [ToolCall(id: "c", name: "x", arguments: "{}")]),
        ChatMessage(role: .tool, content: "r", toolCallID: "c"),
        ChatMessage(role: .assistant, content: "a1"),
        ChatMessage(role: .user, content: "2"),
        ChatMessage(role: .assistant, content: "a2"),
        ChatMessage(role: .user, content: "3"),
    ]

    let (older, recent) = ContextCompactor.split(history, keepingLastTurns: 2)

    #expect(older.count == 4)
    #expect(recent.first == ChatMessage(role: .user, content: "2"))
    #expect(ContextCompactor.split(history, keepingLastTurns: 5).older.isEmpty)
}

@Test func summarizesWithoutTools() async throws {
    let transport = ScriptedTransport([[#"data: {"choices":[{"delta":{"content":"- Kullanıcı Roma gezisi planlıyor."}}]}"#, "data: [DONE]"]])
    let client = LLMClient(configuration: try makeConfiguration(), transport: transport)
    let messages = [
        ChatMessage(role: .user, content: "Roma'ya gideceğim"),
        ChatMessage(role: .assistant, content: "Harika"),
    ]

    let summary = try await ContextCompactor.summarize(messages, previousSummary: "Eski özet", client: client)

    #expect(summary == "- Kullanıcı Roma gezisi planlıyor.")
    let body = try transport.body(of: 0)
    #expect(body["tools"] == nil)
    let sent = try #require(body["messages"] as? [[String: Any]])
    let input = try #require(sent.last?["content"] as? String)
    #expect(input.contains("Önceki özet:\nEski özet"))
    #expect(input.contains("Kullanıcı: Roma'ya gideceğim"))
    #expect(input.contains("Asistan: Harika"))
}

@Test func systemPromptIncludesSummary() {
    let prompt = SystemPrompt.make(summary: "- Roma gezisi", userInstructions: "Kısa yaz.")

    #expect(prompt.contains("önceki kısmının özeti"))
    #expect(prompt.contains("- Roma gezisi"))
    #expect(prompt.hasSuffix("Kısa yaz."))
}

@Test func estimatesTokens() {
    #expect(ContextCompactor.estimatedTokens([ChatMessage(role: .user, content: String(repeating: "a", count: 300))]) == 100)
}
