import Foundation
import Testing
@testable import AgentCore

@Test func streamsReasoningFromRecordedFixture() async throws {
    let client = LLMClient(configuration: try makeConfiguration(), transport: MockTransport(responseLines: try fixtureLines("text-stream.sse")))

    let events = try await collect(client.streamChat([]))
    let thinking = events.compactMap { if case let .reasoning(text) = $0 { text } else { nil } }.joined()

    #expect(thinking.hasPrefix("The user asked for a self-introduction"))
    #expect(events.contains { if case .text = $0 { true } else { false } })
}

@Test func readsReasoningContentField() async throws {
    let lines = [#"data: {"choices":[{"delta":{"reasoning_content":"düşün"}}]}"#, #"data: {"choices":[{"delta":{"content":"cevap"}}]}"#, "data: [DONE]"]
    let client = LLMClient(configuration: try makeConfiguration(), transport: MockTransport(responseLines: lines))

    #expect(withoutUsage(try await collect(client.streamChat([]))) == [.reasoning("düşün"), .text("cevap")])
}

@Test func reportsToolCallProgressWhileArgumentsStream() async throws {
    let chunk = String(repeating: "x", count: 150)
    var lines = [#"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"a","function":{"name":"create_artifact","arguments":""}}]}}]}"#]
    for _ in 0..<4 {
        lines.append(#"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\#(chunk)"}}]}}]}"#)
    }
    lines.append("data: [DONE]")
    let client = LLMClient(configuration: try makeConfiguration(), transport: MockTransport(responseLines: lines))

    let progress = try await collect(client.streamChat([])).compactMap {
        if case let .toolCallProgress(name, characters) = $0 { "\(name):\(characters)" } else { nil }
    }

    #expect(progress == ["create_artifact:0", "create_artifact:300", "create_artifact:600"])
}

@Test func agentLoopForwardsReasoning() async throws {
    let transport = ScriptedTransport([[#"data: {"choices":[{"delta":{"reasoning":"hmm"}}]}"#, #"data: {"choices":[{"delta":{"content":"ok"}}]}"#, "data: [DONE]"]])
    let loop = AgentLoop(client: LLMClient(configuration: try makeConfiguration(), transport: transport), tools: [])

    let events = try await collect(loop.run([]))

    #expect(events.prefix(2) == [.reasoning("hmm"), .text("ok")])
}

@Test func readsEvrenModelCard() async throws {
    let card = """
    {"id":"glm-5.3","object":"model","task":"chat","modalities":["text"],"context_length":524288,
     "default_max_output_tokens":16384,"capabilities":{"tools":true,"thinking":true,"reasoning_effort":true,
     "reasoning_effort_values":null,"reasoning_effort_aliases":{"medium":"high"},"vision":false},"precision":"FP8"}
    """
    let transport = SendRecorder(json: card)

    let info = await LLMClient.modelDetails(baseURL: "https://evren-llmapi.ssyz.org.tr/v1", apiKey: "k", modelID: "glm-5.3", transport: transport)

    #expect(transport.requests.first?.url.absoluteString == "https://evren-llmapi.ssyz.org.tr/v1/models/glm-5.3")
    #expect(info?.supportsReasoningEffort == true)
    #expect(info?.acceptsImages == false)
    #expect(info?.contextLength == 524_288)
}

@Test func modelCardFallsBackToVisionFlag() async throws {
    let transport = SendRecorder(json: #"{"id":"m","capabilities":{"vision":true,"reasoning_effort":false}}"#)

    let info = await LLMClient.modelDetails(baseURL: "https://a.com/v1", apiKey: "k", modelID: "m", transport: transport)

    #expect(info?.acceptsImages == true)
    #expect(info?.supportsReasoningEffort == false)
}

@Test func missingModelCardIsNil() async throws {
    #expect(await LLMClient.modelDetails(baseURL: "https://a.com/v1", apiKey: "k", modelID: "m", transport: SendRecorder(status: 404, json: "{}")) == nil)
}
