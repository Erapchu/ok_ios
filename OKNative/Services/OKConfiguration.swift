import Foundation

enum OKConfiguration {
    // Public application identifiers, safe to include in the client binary.
    static let applicationID = "512005294190"
    static let applicationKey = "CPGJMFOGDIHBABABA"
    static let callbackScheme = "ok512005294190"
    static let redirectURI = "ok512005294190://authorize"
}

enum OKOAuthFlow {
    enum Failure: Error, LocalizedError, Equatable {
        case invalidCallback, stateMismatch, denied, missingTokens, cannotStart
        var errorDescription: String? {
            switch self {
            case .invalidCallback, .stateMismatch: "Не удалось проверить ответ авторизации. Повторите вход."
            case .denied: "ОК не предоставил доступ. Проверьте клиентскую OAuth-авторизацию и разрешение VALUABLE_ACCESS в настройках приложения."
            case .missingTokens: "ОК не вернул пару клиентских токенов. Проверьте настройки OAuth; при необходимости используйте личные токены разработчика."
            case .cannotStart: "Не удалось открыть окно входа. Повторите попытку."
            }
        }
    }

    static func authorizationURL(state: String) -> URL {
        var url = URLComponents(string: "https://connect.ok.ru/oauth/authorize")!
        url.queryItems = [
            URLQueryItem(name: "client_id", value: OKConfiguration.applicationID),
            URLQueryItem(name: "redirect_uri", value: OKConfiguration.redirectURI),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "scope", value: "VALUABLE_ACCESS"),
            URLQueryItem(name: "layout", value: "m"),
            URLQueryItem(name: "state", value: state)
        ]
        return url.url!
    }

    static func tokens(from callback: URL, expectedState: String, now: Date = .now) throws -> AuthTokens {
        guard callback.scheme?.lowercased() == OKConfiguration.callbackScheme,
              callback.host?.lowercased() == "authorize", ["", "/"].contains(callback.path),
              callback.port == nil, callback.user == nil, callback.password == nil,
              let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false) else { throw Failure.invalidCallback }
        let query = parts.percentEncodedFragment.flatMap { URLComponents(string: "?" + $0)?.queryItems } ?? parts.queryItems ?? []
        var parameters: [String: String] = [:]
        for item in query {
            guard parameters[item.name] == nil else { throw Failure.invalidCallback }
            parameters[item.name] = item.value ?? ""
        }
        guard !expectedState.isEmpty, parameters["state"] == expectedState else { throw Failure.stateMismatch }
        if parameters["error"] != nil { throw Failure.denied }
        guard let token = parameters["access_token"], !token.isEmpty,
              let secret = parameters["session_secret_key"], !secret.isEmpty else { throw Failure.missingTokens }
        var expiresAt: Date?
        if let raw = parameters["expires_in"], let seconds = Double(raw), seconds.isFinite, seconds > 0 {
            expiresAt = now.addingTimeInterval(min(seconds, 315_360_000))
        }
        let tokens = AuthTokens(accessToken: token, expiresAt: expiresAt,
                                applicationKey: OKConfiguration.applicationKey, sessionSecretKey: secret)
        try OKAPIClient.validate(tokens)
        return tokens
    }
}
