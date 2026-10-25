import XCTest
@testable import OKNative

final class OAuthTests: XCTestCase {
    private func callback(_ parameters: [String: String]) throws -> URL {
        var url = URLComponents(string: OKConfiguration.redirectURI)!
        var fragment = URLComponents()
        fragment.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        url.percentEncodedFragment = fragment.percentEncodedQuery
        return try XCTUnwrap(url.url)
    }

    func testAuthorizationUsesRegisteredAppAndCallback() throws {
        let url = OKOAuthFlow.authorizationURL(state: "test-state")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, new in new })
        XCTAssertEqual(url.host, "connect.ok.ru")
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(values["client_id"], "512005294190")
        XCTAssertEqual(values["redirect_uri"], "ok512005294190://authorize")
        XCTAssertEqual(values["state"], "test-state")
        XCTAssertEqual(values["response_type"], "token")
        XCTAssertNil(values["client_secret"])
    }

    func testValidCallbackPreservesOpaqueTokenAndExpiry() throws {
        let now = Date.now
        let url = try callback(["state": "nonce", "access_token": "a+b=c&part#end", "session_secret_key": "session-secret", "expires_in": "3600"])
        let tokens = try OKOAuthFlow.tokens(from: url, expectedState: "nonce", now: now)
        XCTAssertEqual(tokens.accessToken, "a+b=c&part#end")
        XCTAssertEqual(tokens.sessionSecretKey, "session-secret")
        XCTAssertEqual(tokens.applicationKey, OKConfiguration.applicationKey)
        XCTAssertEqual(try XCTUnwrap(tokens.expiresAt).timeIntervalSince(now), 3600, accuracy: 0.001)
        XCTAssertNil(tokens.accountID, "The account ID comes only from the authenticated API response")
    }

    func testWrongStateOrCallbackRouteCannotCreateSession() throws {
        let url = try callback(["state": "wrong", "access_token": "token", "session_secret_key": "secret"])
        XCTAssertThrowsError(try OKOAuthFlow.tokens(from: url, expectedState: "expected")) {
            XCTAssertEqual($0 as? OKOAuthFlow.Failure, .stateMismatch)
        }
        let wrongRoute = try XCTUnwrap(URL(string: "ok512005294190://other#state=expected&access_token=token&session_secret_key=secret"))
        XCTAssertThrowsError(try OKOAuthFlow.tokens(from: wrongRoute, expectedState: "expected"))
        let duplicates = try XCTUnwrap(URL(string: "ok512005294190://authorize#state=expected&state=other&access_token=token&session_secret_key=secret"))
        XCTAssertThrowsError(try OKOAuthFlow.tokens(from: duplicates, expectedState: "expected"))
    }

    func testDeniedAndCodeOnlyResponsesDoNotStoreTokens() throws {
        let denied = try callback(["state": "nonce", "error": "access_denied", "error_description": "sensitive-provider-text"])
        XCTAssertThrowsError(try OKOAuthFlow.tokens(from: denied, expectedState: "nonce")) {
            XCTAssertEqual($0 as? OKOAuthFlow.Failure, .denied)
            XCTAssertFalse($0.localizedDescription.contains("sensitive-provider-text"))
        }
        let codeOnly = try callback(["state": "nonce", "code": "authorization-code"])
        XCTAssertThrowsError(try OKOAuthFlow.tokens(from: codeOnly, expectedState: "nonce")) {
            XCTAssertEqual($0 as? OKOAuthFlow.Failure, .missingTokens)
        }
    }
}
