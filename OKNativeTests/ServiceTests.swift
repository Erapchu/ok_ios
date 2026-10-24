import XCTest
@testable import OKNative

final class ServiceTests: XCTestCase {
    private func client() -> HTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return HTTPClient(session: URLSession(configuration: configuration))
    }

    func testHTTPClientDecodesResponse() async throws {
        struct Response: Decodable, Sendable { let value: Int }
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.invalid/ok")))
        let result: Response = try await client().send(request)
        XCTAssertEqual(result.value, 7)
    }

    func testHTTPClientReportsStatusAndMalformedJSON() async throws {
        struct Response: Decodable, Sendable { let value: Int }
        let denied = URLRequest(url: try XCTUnwrap(URL(string: "https://example.invalid/unauthorized")))
        do {
            let _: Response = try await client().send(denied)
            XCTFail("HTTP 401 must not decode as a successful response")
        } catch {
            XCTAssertEqual(error as? HTTPClient.Failure, .httpStatus(401))
        }
        let malformed = URLRequest(url: try XCTUnwrap(URL(string: "https://example.invalid/malformed")))
        do {
            let _: Response = try await client().send(malformed)
            XCTFail("Malformed JSON must be rejected")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testHTTPClientRejectsPlainHTTPBeforeNetworking() async throws {
        struct Response: Decodable, Sendable { let ok: Bool }
        let request = URLRequest(url: try XCTUnwrap(URL(string: "http://example.invalid")))
        do {
            let _: Response = try await HTTPClient().send(request)
            XCTFail("Insecure requests must be rejected")
        } catch {
            XCTAssertEqual(error as? HTTPClient.Failure, .insecureURL)
        }
    }

    func testKeychainInsertUpdateReadAndDelete() async throws {
        let store = KeychainTokenStore(service: "app.oknative.tests.\(UUID().uuidString)")
        let first = AuthTokens(accessToken: "test-one", expiresAt: nil)
        let second = AuthTokens(accessToken: "test-two", expiresAt: Date(timeIntervalSince1970: 2_000_000_000))
        do {
            try await store.save(first)
            let readFirst = try await store.read()
            XCTAssertEqual(readFirst, first)
            try await store.save(second)
            let readSecond = try await store.read()
            XCTAssertEqual(readSecond, second)
            try await store.delete()
            let readDeleted = try await store.read()
            XCTAssertNil(readDeleted)
            try await store.delete()
        } catch {
            try? await store.delete()
            throw error
        }
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: url.path == "/unauthorized" ? 401 : 200,
                                             httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let payload = url.path == "/malformed" ? "invalid JSON" : "{\"value\":7}"
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
