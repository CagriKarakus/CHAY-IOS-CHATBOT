import Foundation
import Testing
@testable import AgentCore

@Test func encodesToOpenAIFormat() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys

    let data = try encoder.encode(ChatMessage(role: .user, content: "Merhaba"))

    #expect(String(decoding: data, as: UTF8.self) == #"{"content":"Merhaba","role":"user"}"#)
}

@Test func decodesAssistantMessage() throws {
    let json = Data(#"{"role":"assistant","content":"Selam"}"#.utf8)

    let message = try JSONDecoder().decode(ChatMessage.self, from: json)

    #expect(message == ChatMessage(role: .assistant, content: "Selam"))
}
