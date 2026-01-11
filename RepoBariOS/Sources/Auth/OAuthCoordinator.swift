import AuthenticationServices
import Foundation
import RepoBarCore
import UIKit

@MainActor
final class OAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let tokenStore: TokenStore
    private let tokenRefresher: OAuthTokenRefresher
    private var authSession: ASWebAuthenticationSession?
    private var lastHost: URL = RepoBarAuthDefaults.githubHost
    private var cachedTokens: OAuthTokens?
    private var hasLoadedTokens = false
    private static let callbackHost = "repobar.app"
    private static let callbackPath = "/oauth-callback"
    private static let callbackURL = URL(string: "https://repobar.app/oauth-callback")!

    override init() {
        let store = TokenStore.shared
        self.tokenStore = store
        self.tokenRefresher = OAuthTokenRefresher(tokenStore: store)
        super.init()
    }

    func login(
        clientID: String,
        clientSecret: String,
        host: URL,
        pkceMode: PKCEMode = .auto,
        scope: String = "repo read:org"
    ) async throws {
        let normalizedHost = try OAuthLoginFlow.normalizeHost(host)
        self.lastHost = normalizedHost

        let authBase = normalizedHost.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let authEndpoint = URL(string: "\(authBase)/login/oauth/authorize")!
        let tokenEndpoint = URL(string: "\(authBase)/login/oauth/access_token")!

        let usePKCE = await Self.shouldUsePKCE(mode: pkceMode, host: normalizedHost)
        let pkce = usePKCE ? PKCE.generate() : nil
        let state = UUID().uuidString
        let redirectURL = Self.callbackURL

        var components = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: scope)
        ]
        if let pkce {
            components.queryItems?.append(URLQueryItem(name: "code_challenge", value: pkce.challenge))
            components.queryItems?.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
        }
        guard let authorizeURL = components.url else { throw URLError(.badURL) }

        let callbackURL = try await self.startWebAuthentication(url: authorizeURL)
        guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value ?? ""
        let returnedState = callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value ?? ""
        guard returnedState == state, code.isEmpty == false else { throw URLError(.badServerResponse) }

        var tokenParams = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": code,
            "redirect_uri": redirectURL.absoluteString,
            "grant_type": "authorization_code"
        ]
        if let pkce {
            tokenParams["code_verifier"] = pkce.verifier
        }

        var tokenRequest = URLRequest(url: tokenEndpoint)
        tokenRequest.httpMethod = "POST"
        tokenRequest.addValue("application/json", forHTTPHeaderField: "Accept")
        tokenRequest.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        tokenRequest.httpBody = Self.formUrlEncoded(tokenParams)

        let (data, response) = try await URLSession.shared.data(for: tokenRequest)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        let tokens = OAuthTokens(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken ?? "",
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expiresIn ?? 3600))
        )
        try self.tokenStore.save(tokens: tokens)
        try self.tokenStore.save(clientCredentials: OAuthClientCredentials(clientID: clientID, clientSecret: clientSecret))
        self.cachedTokens = tokens
        self.hasLoadedTokens = true
    }

    /// Determines whether to use PKCE based on mode and host.
    /// For "auto" mode, enables PKCE for GitHub.com and GHE >= 3.15, disables for older GHE.
    private static func shouldUsePKCE(mode: PKCEMode, host: URL) async -> Bool {
        switch mode {
        case .on:
            return true
        case .off:
            return false
        case .auto:
            let isGitHubCom = host.host?.lowercased() == "github.com"
            if isGitHubCom {
                return true
            }
            let gheVersion = await detectGHEVersion(host: host)
            if let version = gheVersion {
                return version >= GHEVersion(major: 3, minor: 15)
            }
            return false
        }
    }

    /// Detects GitHub Enterprise Server version by checking X-GitHub-Enterprise-Version header.
    private static func detectGHEVersion(host: URL) async -> GHEVersion? {
        let apiURL = host.appendingPathComponent("api/v3")
        var request = URLRequest(url: apiURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  let versionString = httpResponse.value(forHTTPHeaderField: "X-GitHub-Enterprise-Version") else {
                return nil
            }
            return GHEVersion(string: versionString)
        } catch {
            return nil
        }
    }

    func logout() async {
        self.tokenStore.clear()
        self.cachedTokens = nil
        self.hasLoadedTokens = false
    }

    func loadTokens() -> OAuthTokens? {
        if self.hasLoadedTokens { return self.cachedTokens }
        self.hasLoadedTokens = true
        let tokens = try? self.tokenStore.load()
        self.cachedTokens = tokens
        return tokens
    }

    func refreshIfNeeded() async throws -> OAuthTokens? {
        if let tokens = self.cachedTokens, tokens.expiresAt.map({ $0 > Date().addingTimeInterval(60) }) != false {
            return tokens
        }
        let refreshed = try await self.tokenRefresher.refreshIfNeeded(host: self.lastHost)
        if refreshed != nil {
            self.cachedTokens = refreshed
            self.hasLoadedTokens = true
        }
        return refreshed
    }

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = windowScenes.flatMap(\.windows).first(where: { $0.isKeyWindow }) {
            return window
        }
        guard let scene = windowScenes.first else {
            preconditionFailure("No UIWindowScene available for authentication")
        }
        return UIWindow(windowScene: scene)
    }

    private func startWebAuthentication(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let callback = ASWebAuthenticationSession.Callback.https(
                host: Self.callbackHost,
                path: Self.callbackPath
            )
            let session = ASWebAuthenticationSession(url: url, callback: callback) { [weak self] callbackURL, error in
                self?.authSession = nil
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            if !session.start() {
                continuation.resume(throwing: URLError(.cannotOpenFile))
            }
        }
    }
}

private extension OAuthCoordinator {
    static func formUrlEncoded(_ params: [String: String]) -> Data? {
        let encoded = params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return encoded.data(using: .utf8)
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let scope: String
    let expiresIn: Int?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

/// Represents a GitHub Enterprise Server version for comparison.
private struct GHEVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init?(string: String) {
        let components = string.split(separator: ".").compactMap { Int($0) }
        guard components.count >= 2 else { return nil }
        self.major = components[0]
        self.minor = components[1]
        self.patch = components.count > 2 ? components[2] : 0
    }

    static func < (lhs: GHEVersion, rhs: GHEVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
