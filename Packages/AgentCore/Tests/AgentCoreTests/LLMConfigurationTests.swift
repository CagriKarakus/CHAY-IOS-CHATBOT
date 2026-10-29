import Testing
@testable import AgentCore

@Test func trimsValues() throws {
    let configuration = try LLMConfiguration(baseURL: " https://router.example.com/v1 \n", apiKey: " key ", model: " m ")

    #expect(configuration.baseURL.absoluteString == "https://router.example.com/v1")
    #expect(configuration.apiKey == "key")
    #expect(configuration.model == "m")
}

@Test(arguments: ["http://router.example.com/v1", "router.example.com/v1", "https://", ""])
func rejectsNonHTTPSURLs(_ url: String) {
    #expect(throws: LLMError.invalidBaseURL) {
        try LLMConfiguration(baseURL: url, apiKey: "key", model: "m")
    }
}

@Test func requiresKeyAndModel() {
    #expect(throws: LLMError.missingAPIKey) {
        try LLMConfiguration(baseURL: "https://a.com/v1", apiKey: "  ", model: "m")
    }
    #expect(throws: LLMError.missingModel) {
        try LLMConfiguration(baseURL: "https://a.com/v1", apiKey: "key", model: "")
    }
}

@Test(arguments: [
    ("data: {\"a\":1}", SSELine.data("{\"a\":1}")),
    ("data:{\"a\":1}\r", SSELine.data("{\"a\":1}")),
    ("data: [DONE]", SSELine.done),
    (": keep-alive", SSELine.ignored),
    ("event: message", SSELine.ignored),
    ("", SSELine.ignored),
])
func parsesSSELines(_ input: String, _ expected: SSELine) {
    #expect(SSELine(input) == expected)
}
