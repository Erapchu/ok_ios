import Foundation
import CryptoKit

enum OKAPIError: Error, LocalizedError, Equatable {
    case invalidCredentials
    case authentication
    case permission
    case server(Int)
    case invalidResponse
    case unsupported

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Проверьте публичный ключ приложения и оба токена доступа."
        case .authentication: "Сессия ОК истекла или отозвана. Подключите аккаунт заново."
        case .permission: "ОК не разрешил доступ. Проверьте разрешения приложения, включая VALUABLE_ACCESS, и создайте новую пару токенов."
        case .server(let code): "ОК вернул ошибку \(code). Попробуйте позднее."
        case .invalidResponse: "ОК вернул данные в неожиданном формате."
        case .unsupported: "Эта функция пока не подключена к API."
        }
    }
}

struct OKAPIClient: Sendable {
    let credentials: AuthTokens
    let transport: HTTPClient

    init(credentials: AuthTokens, transport: HTTPClient? = nil) {
        self.credentials = credentials
        if let transport { self.transport = transport } else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil
            config.urlCache = nil
            config.timeoutIntervalForRequest = 30
            self.transport = HTTPClient(session: URLSession(configuration: config))
        }
    }

    static func validate(_ tokens: AuthTokens) throws {
        let values = [tokens.accessToken, tokens.applicationKey ?? "", tokens.sessionSecretKey ?? ""]
        guard values.allSatisfy({ !$0.isEmpty && $0.count <= 4096 && !$0.contains(where: \.isWhitespace) }) else {
            throw OKAPIError.invalidCredentials
        }
        if let expiry = tokens.expiresAt, expiry <= .now { throw OKAPIError.authentication }
    }

    func call<Response: Decodable & Sendable>(
        _ method: String, parameters: [String: String] = [:], as type: Response.Type = Response.self
    ) async throws -> Response {
        let data: Data
        do { data = try await transport.data(for: request(method, parameters: parameters)) }
        catch HTTPClient.Failure.httpStatus(401) { throw OKAPIError.authentication }
        catch HTTPClient.Failure.httpStatus(403) { throw OKAPIError.permission }
        // OK reports application errors inside HTTP 200 responses as well.
        if let failure = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
            switch failure.errorCode {
            case 102: throw OKAPIError.authentication
            case 10, 200, 457: throw OKAPIError.permission
            default: throw OKAPIError.server(failure.errorCode)
            }
        }
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw OKAPIError.invalidResponse }
    }

    func request(_ method: String, parameters: [String: String] = [:]) throws -> URLRequest {
        try Self.validate(credentials)
        var fields = parameters
        fields["method"] = method
        fields["application_key"] = credentials.applicationKey
        fields["format"] = "json"
        fields["__online"] = "false"
        fields.removeValue(forKey: "sig")
        fields.removeValue(forKey: "access_token")
        fields.removeValue(forKey: "session_key")
        let signature = Self.signature(fields, secret: credentials.sessionSecretKey ?? "")
        fields["access_token"] = credentials.accessToken
        fields["sig"] = signature
        var request = URLRequest(url: URL(string: "https://api.ok.ru/fb.do")!)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = Self.formEncoded(fields).data(using: .utf8)
        return request
    }

    /// MD5 is required by OK's wire protocol; it is not used for password storage.
    static func signature(_ parameters: [String: String], secret: String) -> String {
        let text = parameters.keys.filter { !["access_token", "session_key", "sig"].contains($0) }
            .sorted().map { "\($0)=\(parameters[$0] ?? "")" }.joined() + secret
        return Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func formEncoded(_ parameters: [String: String]) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return parameters.keys.sorted().map { key in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")=\((parameters[key] ?? "").addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&")
    }
}

private struct APIErrorEnvelope: Decodable {
    let errorCode: Int
    enum CodingKeys: String, CodingKey { case errorCode = "error_code" }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(Int.self, forKey: .errorCode) { errorCode = value }
        else { errorCode = Int(try container.decode(String.self, forKey: .errorCode)) ?? -1 }
    }
}
