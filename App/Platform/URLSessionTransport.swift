import AgentCore
import Foundation

/// `HTTPTransport`'un URLSession uygulaması (`bytes(for:)` ile satır satır akış).
struct URLSessionTransport: HTTPTransport {
    var session: URLSession = .shared
    /// Yanıtta günlük kalan token başlığı (Evren: `x-evren-daily-remaining-tokens`) varsa çağrılır.
    var onDailyRemaining: (@Sendable (Int) -> Void)?

    func lines(for request: HTTPRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: urlRequest(from: request))
                    guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
                    if let value = http.value(forHTTPHeaderField: "x-evren-daily-remaining-tokens"), let remaining = Int(value) {
                        onDailyRemaining?(remaining)
                    }

                    guard (200..<300).contains(http.statusCode) else {
                        var body = ""
                        for try await line in bytes.lines where body.count < 4_000 {
                            body += line + "\n"
                        }
                        throw HTTPStatusError(statusCode: http.statusCode, body: body)
                    }

                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: urlRequest(from: request))
        guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
        return HTTPResponse(
            statusCode: http.statusCode,
            contentType: http.value(forHTTPHeaderField: "Content-Type"),
            body: data,
            headers: Dictionary(
                http.allHeaderFields.compactMap { key, value in (key as? String).map { ($0, "\(value)") } },
                uniquingKeysWith: { first, _ in first }
            )
        )
    }

    private func urlRequest(from request: HTTPRequest) -> URLRequest {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: 60)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        return urlRequest
    }
}
