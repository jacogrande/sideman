import Foundation
import Network

actor SpotifyCallbackServer {
    private let port: UInt16
    private var listener: NWListener?

    init(port: UInt16 = 28371) {
        self.port = port
    }

    func waitForCallback(expectedState: String) async throws -> String {
        let params = NWParameters.tcp
        let nwPort = NWEndpoint.Port(rawValue: port)!
        listener = try NWListener(using: params, on: nwPort)

        let guard_ = ContinuationGuard()

        let code: String = try await withCheckedThrowingContinuation { continuation in
            guard_.setContinuation(continuation)

            listener?.newConnectionHandler = { connection in
                connection.start(queue: .global())
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                    guard let data, let request = String(data: data, encoding: .utf8) else { return }

                    let parsedURL = Self.parseRequestURL(from: request)
                    let queryItems = parsedURL
                        .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }

                    let state = queryItems?.first(where: { $0.name == "state" })?.value
                    let authCode = queryItems?.first(where: { $0.name == "code" })?.value

                    guard let _ = queryItems, state == expectedState, let authCode else {
                        let errorBody = "Invalid callback request."
                        let errorResponse = Self.httpResponse(body: errorBody)
                        connection.send(content: errorResponse.data(using: .utf8), completion: .contentProcessed { _ in
                            connection.cancel()
                        })

                        if let errorParam = queryItems?.first(where: { $0.name == "error" })?.value {
                            guard_.resume(throwing: SpotifyClientError.authenticationFailed(errorParam))
                        } else {
                            guard_.resume(throwing: SpotifyClientError.authenticationFailed("Invalid state or missing code"))
                        }
                        return
                    }

                    let successBody = "<html><body><h2>Authorization successful!</h2><p>You can close this tab and return to Sideman.</p></body></html>"
                    let response = Self.httpResponse(body: successBody)
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })

                    guard_.resume(returning: authCode)
                }
            }

            listener?.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    guard_.resume(throwing: SpotifyClientError.network("Listener failed: \(error)"))
                }
            }

            listener?.start(queue: .global())

            Task {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                guard_.resume(throwing: SpotifyClientError.authenticationCancelled)
            }
        }

        stop()
        return code
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private static func parseRequestURL(from httpRequest: String) -> URL? {
        guard let firstLine = httpRequest.split(separator: "\r\n").first ?? httpRequest.split(separator: "\n").first else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        return URL(string: "http://127.0.0.1\(parts[1])")
    }

    private static func httpResponse(body: String) -> String {
        "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    }
}

/// Thread-safe wrapper to ensure a continuation is resumed exactly once.
private final class ContinuationGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var resumed = false

    func setContinuation(_ c: CheckedContinuation<String, Error>) {
        lock.lock()
        continuation = c
        lock.unlock()
    }

    func resume(returning value: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed, let c = continuation else { return }
        resumed = true
        c.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed, let c = continuation else { return }
        resumed = true
        c.resume(throwing: error)
    }
}
