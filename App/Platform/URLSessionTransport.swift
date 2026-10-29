import AgentCore
import Foundation

/// `HTTPTransport`'un URLSession uygulaması (`bytes(for:)` ile satır satır akış).
struct URLSessionTransport: HTTPTransport {
    var session: URLSession = .shared

    func lines(for request: HTTPRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: urlRequest(from: request))
                    guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse }

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
