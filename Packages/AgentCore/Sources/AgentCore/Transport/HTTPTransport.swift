import Foundation

public struct HTTPRequest: Equatable, Sendable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data?

    public init(url: URL, method: String, headers: [String: String], body: Data?) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let contentType: String?
    public let body: Data
    /// Yanıt başlıkları; adlar küçük harfle.
    public let headers: [String: String]

    public init(statusCode: Int, contentType: String?, body: Data, headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.contentType = contentType
        self.body = body
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

/// 2xx dışı bir yanıt. `body` hata gövdesinin (kırpılmış) metnidir.
public struct HTTPStatusError: Error, Equatable, Sendable {
    public let statusCode: Int
    public let body: String

    public init(statusCode: Int, body: String) {
        self.statusCode = statusCode
        self.body = body
    }
}

/// HTTP katmanı. iOS'ta URLSession, testlerde sahte uygulama kullanılır.
public protocol HTTPTransport: Sendable {
    /// Yanıtı satır satır akıtır. 2xx dışı yanıtlarda akış `HTTPStatusError` ile biter.
    func lines(for request: HTTPRequest) -> AsyncThrowingStream<String, any Error>

    /// Yanıtın tamamını döndürür; durum kodu kontrolü çağırana kalır.
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}
