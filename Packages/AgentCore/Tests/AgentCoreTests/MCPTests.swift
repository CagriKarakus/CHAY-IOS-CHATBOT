import Foundation
import Testing
@testable import AgentCore

/// Her isteğe verilen kapanışla cevap veren ve istekleri kaydeden sahte sunucu.
final class MCPServerStub: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HTTPRequest] = []
    private let handler: @Sendable (HTTPRequest) -> HTTPResponse

    init(_ handler: @escaping @Sendable (HTTPRequest) -> HTTPResponse) {
        self.handler = handler
    }

    var requests: [HTTPRequest] { lock.withLock { recorded } }

    func lines(for request: HTTPRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { recorded.append(request) }
        return handler(request)
    }
}

private func json(_ text: String, status: Int = 200, headers: [String: String] = [:]) -> HTTPResponse {
    HTTPResponse(statusCode: status, contentType: "application/json", body: Data(text.utf8), headers: headers)
}

private func method(of request: HTTPRequest) -> String? {
    guard let body = request.body,
          let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    else { return nil }
    return object["method"] as? String
}

private func rpcID(of request: HTTPRequest) -> Int {
    let object = (try? JSONSerialization.jsonObject(with: request.body ?? Data())) as? [String: Any]
    return object?["id"] as? Int ?? 0
}

private let serverURL = URL(string: "https://mcp.example.com/mcp")!

@Test func mcpClientInitializesListsAndCallsTools() async throws {
    let transport = MCPServerStub { request in
        let id = rpcID(of: request)
        switch method(of: request) {
        case "initialize":
            return json(#"{"jsonrpc":"2.0","id":\#(id),"result":{"protocolVersion":"2025-06-18","capabilities":{}}}"#,
                        headers: ["Mcp-Session-Id": "s-1"])
        case "notifications/initialized":
            return HTTPResponse(statusCode: 202, contentType: nil, body: Data())
        case "tools/list":
            // SSE yanıtı: önce bir bildirim, sonra cevap.
            let sse = """
            event: message
            data: {"jsonrpc":"2.0","method":"notifications/message","params":{}}

            data: {"jsonrpc":"2.0","id":\(id),"result":{"tools":[
            data: {"name":"search_issues","description":"Search issues","inputSchema":{"type":"object","properties":{"q":{"type":"string"}}},"annotations":{"readOnlyHint":true}},
            data: {"name":"create_issue","title":"Create issue"}]}}

            """
            return HTTPResponse(statusCode: 200, contentType: "text/event-stream", body: Data(sse.utf8))
        default:
            return json(#"{"jsonrpc":"2.0","id":\#(id),"result":{"content":[{"type":"text","text":"3 issues"},{"type":"image","data":"AAA","mimeType":"image/png"}]}}"#)
        }
    }
    let client = try MCPClient(url: serverURL, transport: transport, tokens: StaticToken(" tok "))

    let tools = try await client.listTools()
    #expect(tools.map(\.name) == ["search_issues", "create_issue"])
    #expect(tools[0].readOnly && !tools[1].readOnly)
    #expect(tools[1].title == "Create issue")
    #expect(tools[0].inputSchema == ["type": "object", "properties": ["q": ["type": "string"]]])

    let text = try await client.callTool("search_issues", arguments: #"{"q":"bug"}"#)
    #expect(text == "3 issues\n\n[image image/png]")

    let requests = transport.requests
    #expect(requests.map { method(of: $0) } == ["initialize", "notifications/initialized", "tools/list", "tools/call"])
    #expect(requests[0].headers["Mcp-Session-Id"] == nil)
    #expect(requests[0].headers["Authorization"] == "Bearer tok")
    #expect(requests[0].headers["Accept"] == "application/json, text/event-stream")
    #expect(requests[2].headers["Mcp-Session-Id"] == "s-1")
    #expect(requests[2].headers["MCP-Protocol-Version"] == "2025-06-18")
    let call = try #require(try JSONSerialization.jsonObject(with: requests[3].body!) as? [String: Any])
    let params = try #require(call["params"] as? [String: Any])
    #expect(params["name"] as? String == "search_issues")
    #expect((params["arguments"] as? [String: Any])?["q"] as? String == "bug")
}

@Test func mcpClientReportsToolAndRPCErrors() async throws {
    let transport = MCPServerStub { request in
        let id = rpcID(of: request)
        switch method(of: request) {
        case "initialize": return json(#"{"jsonrpc":"2.0","id":\#(id),"result":{}}"#)
        case "tools/list": return json(#"{"jsonrpc":"2.0","id":\#(id),"error":{"code":-32601,"message":"Method not found"}}"#)
        default: return json(#"{"jsonrpc":"2.0","id":\#(id),"result":{"content":[{"type":"text","text":"Repo not found"}],"isError":true}}"#)
        }
    }
    let client = try MCPClient(url: serverURL, transport: transport)
    await #expect(throws: MCPError.rpc(code: -32601, message: "Method not found")) { try await client.listTools() }
    await #expect(throws: MCPError.toolFailed("Repo not found")) { try await client.callTool("x", arguments: "{}") }
    #expect(throws: MCPError.insecureURL) { try MCPClient(url: URL(string: "http://mcp.example.com")!, transport: transport) }
}

/// İlk token reddedilir, yenisi kabul edilir.
private actor RotatingToken: MCPTokenProvider {
    private(set) var refreshes = 0
    func token(forceRefresh: Bool) async throws -> String? {
        if forceRefresh { refreshes += 1 }
        return refreshes == 0 ? "old" : "new"
    }
}

@Test func mcpClientRefreshesTokenOn401AndReportsMetadata() async throws {
    let transport = MCPServerStub { request in
        guard request.headers["Authorization"] == "Bearer new" else {
            return json("", status: 401, headers: ["WWW-Authenticate": #"Bearer error="invalid_token", resource_metadata="https://mcp.example.com/.well-known/oauth-protected-resource/mcp""#])
        }
        return json(#"{"jsonrpc":"2.0","id":\#(rpcID(of: request)),"result":{"tools":[]}}"#)
    }
    let tokens = RotatingToken()
    let client = try MCPClient(url: serverURL, transport: transport, tokens: tokens)
    #expect(try await client.listTools().isEmpty)
    #expect(await tokens.refreshes == 1)

    let locked = try MCPClient(url: serverURL, transport: transport, tokens: StaticToken("old"))
    await #expect(throws: MCPError.unauthorized(resourceMetadata: URL(string: "https://mcp.example.com/.well-known/oauth-protected-resource/mcp"))) {
        try await locked.listTools()
    }
}

@Test func mcpClientReopensExpiredSession() async throws {
    let sessions = SessionCounter()
    let transport = MCPServerStub { request in
        let id = rpcID(of: request)
        switch method(of: request) {
        case "initialize":
            return json(#"{"jsonrpc":"2.0","id":\#(id),"result":{}}"#, headers: ["mcp-session-id": "s-\(sessions.next())"])
        case "tools/list" where request.headers["Mcp-Session-Id"] == "s-1":
            return json("", status: 404)
        default:
            return json(#"{"jsonrpc":"2.0","id":\#(id),"result":{"tools":[{"name":"a"}]}}"#)
        }
    }
    let client = try MCPClient(url: serverURL, transport: transport)
    #expect(try await client.listTools().map(\.name) == ["a"])
    #expect(transport.requests.last?.headers["Mcp-Session-Id"] == "s-2")
}

final class SessionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { value += 1; return value } }
}

@Test func mcpToolNamesSchemasAndApproval() throws {
    #expect(MCPTool.exposedName(server: "GitHub Çalışma", tool: "search.issues", taken: []) == "mcp_github__al__ma_search_issues")
    #expect(MCPTool.exposedName(server: "gh", tool: "a", taken: ["mcp_gh_a"]) == "mcp_gh_a_2")
    let long = MCPTool.exposedName(server: "s", tool: String(repeating: "x", count: 80), taken: [])
    #expect(long.count == 64)

    let client = try MCPClient(url: serverURL, transport: MockTransport())
    let reader = MCPTool(info: MCPToolInfo(name: "list", inputSchema: ["type": "object", "properties": [:]], readOnly: true),
                         exposedName: "mcp_gh_list", serverName: "GitHub", client: client)
    let writer = MCPTool(info: MCPToolInfo(name: "create", title: "Create issue"), exposedName: "mcp_gh_create", serverName: "GitHub", client: client)
    #expect(!reader.requiresApproval && writer.requiresApproval)
    let trusted = MCPTool(info: MCPToolInfo(name: "create"), exposedName: "mcp_gh_create", serverName: "GitHub", client: client, alwaysAllowed: true)
    #expect(!trusted.requiresApproval)
    #expect(writer.parameters == ["type": "object", "properties": [:]])
    #expect(writer.activityDetail(for: "{}") == "GitHub · Create issue")
    #expect(writer.description == "[GitHub connector] Create issue")
}

@Test func mcpWriteToolAsksForApprovalEveryTime() async throws {
    let transport = MCPServerStub { request in
        json(#"{"jsonrpc":"2.0","id":\#(rpcID(of: request)),"result":{"content":[{"type":"text","text":"done"}]}}"#)
    }
    let client = try MCPClient(url: serverURL, transport: transport)
    let tool = MCPTool(info: MCPToolInfo(name: "create"), exposedName: "mcp_gh_create", serverName: "GitHub", client: client)
    let llm = ScriptedTransport([
        [
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","type":"function","function":{"name":"mcp_gh_create","arguments":"{\"title\":\"x\"}"}}]}}]}"#,
            "data: [DONE]",
        ],
        [#"data: {"choices":[{"delta":{"content":"ok"}}]}"#, "data: [DONE]"],
    ])
    let approvals = ApprovalLog()
    let loop = AgentLoop(
        client: LLMClient(configuration: try LLMConfiguration(baseURL: "https://llm.example.com/v1", apiKey: "k", model: "m"), transport: llm),
        tools: [tool],
        approve: { request in await approvals.record(request) }
    )
    var toolResult: String?
    for try await event in loop.run([ChatMessage(role: .user, content: "make an issue")]) {
        if case let .message(message) = event, message.role == .tool { toolResult = message.content }
    }
    #expect(await approvals.requests == [ApprovalRequest(toolName: "mcp_gh_create", detail: "GitHub · create", arguments: #"{"title":"x"}"#)])
    #expect(toolResult == "The user declined this action; do not retry it.")
    #expect(transport.requests.isEmpty)
}

private actor ApprovalLog {
    private(set) var requests: [ApprovalRequest] = []
    func record(_ request: ApprovalRequest) -> Bool {
        requests.append(request)
        return false
    }
}

// MARK: - OAuth

@Test func oauthDiscoversRegistersAndExchangesCode() async throws {
    let transport = MCPServerStub { request in
        switch (request.method, request.url.absoluteString) {
        case ("POST", "https://mcp.example.com/mcp"):
            return json("", status: 401, headers: ["WWW-Authenticate": #"Bearer resource_metadata="https://mcp.example.com/.well-known/oauth-protected-resource/mcp""#])
        case ("GET", "https://mcp.example.com/.well-known/oauth-protected-resource/mcp"):
            return json(#"{"resource":"https://mcp.example.com/mcp","authorization_servers":["https://auth.example.com/tenant"],"scopes_supported":["read","write"]}"#)
        case ("GET", "https://auth.example.com/.well-known/oauth-authorization-server/tenant"):
            return json("", status: 404)
        case ("GET", "https://auth.example.com/.well-known/openid-configuration/tenant"):
            return json(#"{"authorization_endpoint":"https://auth.example.com/authorize?tenant=1","token_endpoint":"https://auth.example.com/token","registration_endpoint":"https://auth.example.com/register"}"#)
        case ("POST", "https://auth.example.com/register"):
            return json(#"{"client_id":"cid-1"}"#, status: 201)
        case ("POST", "https://auth.example.com/token"):
            return json(#"{"access_token":"at-1","token_type":"Bearer","expires_in":3600,"refresh_token":"rt-1"}"#)
        default:
            return json("", status: 404)
        }
    }
    let login = try await MCPOAuth.prepareLogin(
        serverURL: serverURL,
        redirectURI: "dev.cagri.aiassistant:/oauth/callback",
        clientName: "CHAY",
        clientID: nil,
        pkce: PKCE(verifier: "verifier-123", challenge: "challenge-abc"),
        state: "st-1",
        transport: transport
    )
    let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: login.authorizationURL, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    #expect(login.authorizationURL.absoluteString.hasPrefix("https://auth.example.com/authorize?"))
    #expect(query["tenant"] == "1")
    #expect(query["client_id"] == "cid-1")
    #expect(query["code_challenge"] == "challenge-abc")
    #expect(query["code_challenge_method"] == "S256")
    #expect(query["resource"] == "https://mcp.example.com/mcp")
    #expect(query["scope"] == "read write")
    #expect(query["redirect_uri"] == "dev.cagri.aiassistant:/oauth/callback")

    let registration = try #require(transport.requests.first { $0.url.absoluteString == "https://auth.example.com/register" })
    let body = try #require(try JSONSerialization.jsonObject(with: registration.body!) as? [String: Any])
    #expect(body["token_endpoint_auth_method"] as? String == "none")
    #expect(body["redirect_uris"] as? [String] == ["dev.cagri.aiassistant:/oauth/callback"])

    await #expect(throws: MCPOAuthError.stateMismatch) {
        try await MCPOAuth.finishLogin(login, callback: URL(string: "dev.cagri.aiassistant:/oauth/callback?code=c&state=other")!, transport: transport)
    }
    await #expect(throws: MCPOAuthError.denied("User said no")) {
        try await MCPOAuth.finishLogin(login, callback: URL(string: "dev.cagri.aiassistant:/oauth/callback?error=access_denied&error_description=User%20said%20no")!, transport: transport)
    }

    let credentials = try await MCPOAuth.finishLogin(login, callback: URL(string: "dev.cagri.aiassistant:/oauth/callback?code=code-9&state=st-1")!, transport: transport)
    #expect(credentials.accessToken == "at-1")
    #expect(credentials.refreshToken == "rt-1")
    #expect(credentials.clientID == "cid-1")
    #expect(!credentials.isExpired())
    let tokenRequest = try #require(transport.requests.last)
    let form = String(decoding: tokenRequest.body!, as: UTF8.self)
    #expect(form.contains("grant_type=authorization_code"))
    #expect(form.contains("code=code-9"))
    #expect(form.contains("code_verifier=verifier-123"))
    #expect(form.contains("resource=https%3A%2F%2Fmcp.example.com%2Fmcp"))
}

@Test func oauthUsesManualClientIDAndLegacyDefaults() async throws {
    let transport = MCPServerStub { request in
        json("", status: request.method == "POST" ? 400 : 404)
    }
    let login = try await MCPOAuth.prepareLogin(
        serverURL: URL(string: "https://legacy.example.com/sse")!,
        redirectURI: "app:/cb",
        clientName: "CHAY",
        clientID: " my-client ",
        pkce: PKCE(verifier: "v", challenge: "c"),
        state: "s",
        transport: transport
    )
    #expect(login.authorizationURL.absoluteString.hasPrefix("https://legacy.example.com/authorize?"))
    #expect(login.authorizationURL.absoluteString.contains("client_id=my-client"))
    #expect(!transport.requests.contains { $0.url.path == "/register" })
}

@Test func oauthTokenProviderRefreshesAndKeepsRefreshToken() async throws {
    let transport = MCPServerStub { request in
        let form = String(decoding: request.body ?? Data(), as: UTF8.self)
        return form.contains("refresh_token=rt-1")
            ? json(#"{"access_token":"at-2","expires_in":60}"#)
            : json(#"{"error":"invalid_grant"}"#, status: 400)
    }
    let expired = OAuthCredentials(
        clientID: "cid", clientSecret: nil, accessToken: "at-1", refreshToken: "rt-1",
        expiresAt: .now.addingTimeInterval(-10), tokenEndpoint: URL(string: "https://auth.example.com/token")!, resource: "https://mcp.example.com/mcp"
    )
    let saved = CredentialLog()
    let provider = OAuthTokenProvider(credentials: expired, transport: transport) { saved.append($0) }
    #expect(try await provider.token(forceRefresh: false) == "at-2")
    #expect(saved.all.last?.refreshToken == "rt-1")

    var revoked = expired
    revoked.refreshToken = "rt-revoked"
    await #expect(throws: MCPOAuthError.loginRequired) {
        try await MCPOAuth.refresh(revoked, transport: transport)
    }
}

final class CredentialLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [OAuthCredentials] = []
    var all: [OAuthCredentials] { lock.withLock { items } }
    func append(_ item: OAuthCredentials) { lock.withLock { items.append(item) } }
}

@Test func oauthWellKnownCandidates() {
    #expect(MCPOAuth.protectedResourceCandidates(for: URL(string: "https://a.com/v1/mcp/")!).map(\.absoluteString) == [
        "https://a.com/.well-known/oauth-protected-resource/v1/mcp",
        "https://a.com/.well-known/oauth-protected-resource",
    ])
    #expect(MCPOAuth.authorizationServerCandidates(for: URL(string: "https://auth.a.com")!).map(\.absoluteString) == [
        "https://auth.a.com/.well-known/oauth-authorization-server",
        "https://auth.a.com/.well-known/openid-configuration",
    ])
    #expect(MCPOAuth.canonicalResource(URL(string: "https://a.com/mcp/#x")!) == "https://a.com/mcp")
}
