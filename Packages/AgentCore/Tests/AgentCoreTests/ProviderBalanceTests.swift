import Foundation
import Testing
@testable import AgentCore

/// URL'ye göre yanıt veren ve istekleri kaydeden sahte transport.
private final class Routes: HTTPTransport, @unchecked Sendable {
    let routes: [String: (Int, String)]
    private(set) var requested: [HTTPRequest] = []

    init(_ routes: [String: (Int, String)]) {
        self.routes = routes
    }

    func lines(for request: HTTPRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requested.append(request)
        let (status, body) = routes[request.url.absoluteString] ?? (404, "")
        return HTTPResponse(statusCode: status, contentType: "application/json", body: Data(body.utf8))
    }
}

@Test func openRouterCredits() async throws {
    let transport = Routes(["https://openrouter.ai/api/v1/credits": (200, #"{"data":{"total_credits":20,"total_usage":7.5}}"#)])

    let balance = try await ProviderBalance.fetch(preset: "openrouter", baseURL: "https://openrouter.ai/api/v1", apiKey: " k ", transport: transport)

    #expect(balance == ProviderBalance(used: 7.5, limit: 20, remaining: 12.5, currency: "USD"))
    #expect(transport.requested.first?.headers["Authorization"] == "Bearer k")
}

@Test func openRouterFallsBackToKeyLimit() async throws {
    let transport = Routes([
        "https://openrouter.ai/api/v1/credits": (403, "{}"),
        "https://openrouter.ai/api/v1/key": (200, #"{"data":{"usage":1.25,"limit":5,"limit_remaining":3.75}}"#),
    ])

    let balance = try await ProviderBalance.fetch(preset: "openrouter", baseURL: "https://openrouter.ai/api/v1", apiKey: "k", transport: transport)

    #expect(balance == ProviderBalance(used: 1.25, limit: 5, remaining: 3.75, currency: "USD"))
}

@Test func deepSeekBalance() async throws {
    let json = #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"80.00"},{"currency":"USD","total_balance":"10.50","granted_balance":"0","topped_up_balance":"10.50"}]}"#
    let transport = Routes(["https://api.deepseek.com/user/balance": (200, json)])

    let balance = try await ProviderBalance.fetch(preset: "deepseek", baseURL: "https://api.deepseek.com/v1", apiKey: "k", transport: transport)

    #expect(balance == ProviderBalance(remaining: 10.5, currency: "USD"))
}

@Test func liteLLMKeyInfo() async throws {
    let transport = Routes(["https://llm.example.com/key/info": (200, #"{"key":"x","info":{"spend":2.5,"max_budget":10}}"#)])

    let balance = try await ProviderBalance.fetch(preset: "litellm", baseURL: "https://llm.example.com/v1/", apiKey: "k", transport: transport)

    #expect(balance == ProviderBalance(used: 2.5, limit: 10, remaining: 7.5, currency: "USD"))
}

@Test func unsupportedPresetsReturnNil() async throws {
    let transport = Routes([:])

    #expect(try await ProviderBalance.fetch(preset: "openai", baseURL: "https://api.openai.com/v1", apiKey: "k", transport: transport) == nil)
    #expect(try await ProviderBalance.fetch(preset: nil, baseURL: "https://a.com/v1", apiKey: "k", transport: transport) == nil)
    #expect(transport.requested.isEmpty)
}

@Test func balanceErrors() async throws {
    await #expect(throws: LLMError.http(status: 401, message: nil)) {
        try await ProviderBalance.fetch(preset: "deepseek", baseURL: "https://api.deepseek.com/v1", apiKey: "k",
                                        transport: Routes(["https://api.deepseek.com/user/balance": (401, "")]))
    }
}
