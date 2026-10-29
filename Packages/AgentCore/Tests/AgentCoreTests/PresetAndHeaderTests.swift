import Foundation
import Testing
@testable import AgentCore

@Test func presetsHaveUniqueIDsAndValidURLs() throws {
    #expect(Set(ProviderPreset.all.map(\.id)).count == ProviderPreset.all.count)
    for preset in ProviderPreset.all where !preset.needsEditing {
        #expect(throws: Never.self) { try LLMConfiguration.validatedBaseURL(preset.baseURL) }
    }
    #expect(ProviderPreset.preset(id: "portkey")?.headerNames == ["x-portkey-api-key", "x-portkey-provider"])
    #expect(ProviderPreset.preset(id: "cloudflare")?.needsEditing == true)
}

@Test func extraHeadersAreSentButCannotOverrideAuth() throws {
    let configuration = try LLMConfiguration(
        baseURL: "https://api.portkey.ai/v1",
        apiKey: "sk",
        model: "m",
        extraHeaders: ["x-portkey-api-key": " pk ", "Authorization": "Bearer evil", " ": "x", "x-empty": " "]
    )

    let request = try LLMClient(configuration: configuration, transport: MockTransport()).makeRequest([])

    #expect(request.headers["x-portkey-api-key"] == "pk")
    #expect(request.headers["Authorization"] == "Bearer sk")
    #expect(request.headers["x-empty"] == nil)
    #expect(configuration.extraHeaders.count == 1)
}

@Test func listModelsSendsExtraHeaders() async throws {
    let transport = SendRecorder(json: #"{"data":[]}"#)

    _ = try await LLMClient.listModels(baseURL: "https://a.com/v1", apiKey: "k", extraHeaders: ["x-team": "t"], transport: transport)

    #expect(transport.requests.first?.headers["x-team"] == "t")
    #expect(transport.requests.first?.headers["Authorization"] == "Bearer k")
}

@Test func headerValuesAreRedactedFromErrors() async throws {
    let configuration = try LLMConfiguration(baseURL: "https://a.com/v1", apiKey: "sk", model: "m", extraHeaders: ["x-key": "secret-pk"])
    let failure = HTTPStatusError(statusCode: 500, body: #"{"error":{"message":"bad header secret-pk"}}"#)
    let client = LLMClient(configuration: configuration, transport: MockTransport(failure: failure))

    do {
        _ = try await collect(client.streamChat([]))
        Issue.record("Hata bekleniyordu")
    } catch {
        #expect(error as? LLMError == .http(status: 500, message: "bad header ***"))
    }
}
