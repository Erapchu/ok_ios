import Foundation

/// Shared HTTPS transport. The API uses an ephemeral URLSession to avoid credential caching.
struct HTTPClient: Sendable {
    enum Failure: Error, Equatable {
        case insecureURL
        case invalidResponse
        case httpStatus(Int)
    }

    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func send<Response: Decodable & Sendable>(
        _ request: URLRequest, as type: Response.Type = Response.self
    ) async throws -> Response {
        let data = try await data(for: request)
        return try JSONDecoder().decode(type, from: data)
    }

    func data(for request: URLRequest) async throws -> Data {
        guard request.url?.scheme?.lowercased() == "https" else { throw Failure.insecureURL }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw Failure.httpStatus(http.statusCode) }
        return data
    }
}

