import AuthenticationServices
import UIKit

@MainActor
final class OKOAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<AuthTokens, Error>?
    private var anchor: UIWindow?

    func authenticate() async throws -> AuthTokens {
        guard session == nil else { throw OKOAuthFlow.Failure.cannotStart }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { pending in
                guard let window = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .filter({ $0.activationState == .foregroundActive })
                    .flatMap(\.windows).first(where: \.isKeyWindow) else {
                    pending.resume(throwing: OKOAuthFlow.Failure.cannotStart)
                    return
                }
                anchor = window
                continuation = pending
                let state = UUID().uuidString + UUID().uuidString
                let browser = ASWebAuthenticationSession(url: OKOAuthFlow.authorizationURL(state: state),
                    callbackURLScheme: OKConfiguration.callbackScheme) { [weak self] url, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                            self.finish(.failure(CancellationError()))
                        } else if error != nil {
                            self.finish(.failure(OKOAuthFlow.Failure.cannotStart))
                        } else if let url {
                            self.finish(Result { try OKOAuthFlow.tokens(from: url, expectedState: state) })
                        } else { self.finish(.failure(OKOAuthFlow.Failure.invalidCallback)) }
                    }
                }
                browser.presentationContextProvider = self
                browser.prefersEphemeralWebBrowserSession = true
                session = browser
                if !browser.start() { finish(.failure(OKOAuthFlow.Failure.cannotStart)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func cancel() {
        session?.cancel()
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<AuthTokens, Error>) {
        let pending = continuation
        continuation = nil
        session = nil
        anchor = nil
        pending?.resume(with: result)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor ?? ASPresentationAnchor() }
}
