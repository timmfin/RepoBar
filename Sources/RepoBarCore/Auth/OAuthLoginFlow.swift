import Foundation

@MainActor
protocol LoopbackServing: AnyObject {
    func start() throws -> URL
    func waitForCallback(timeout: TimeInterval) async throws -> (code: String, state: String)
    func stop()
}

extension LoopbackServer: LoopbackServing {}

@MainActor
public struct OAuthLoginFlow {
    private let tokenStore: TokenStore
    private let openURL: @Sendable (URL) throws -> Void
    private let dataProvider: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let makeLoopbackServer: (Int) -> LoopbackServing
    private let stateProvider: @Sendable () -> String

    public init(
        tokenStore: TokenStore = .shared,
        openURL: @escaping @Sendable (URL) throws -> Void,
        dataProvider: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.init(
            tokenStore: tokenStore,
            openURL: openURL,
            dataProvider: dataProvider,
            makeLoopbackServer: { port in LoopbackServer(port: port) },
            stateProvider: { UUID().uuidString }
        )
    }

    init(
        tokenStore: TokenStore,
        openURL: @escaping @Sendable (URL) throws -> Void,
        dataProvider: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse),
        makeLoopbackServer: @escaping (Int) -> LoopbackServing,
        stateProvider: @escaping @Sendable () -> String
    ) {
        self.tokenStore = tokenStore
        self.openURL = openURL
        self.dataProvider = dataProvider
        self.makeLoopbackServer = makeLoopbackServer
        self.stateProvider = stateProvider
    }

    public func login(
        clientID: String,
        clientSecret: String,
        host: URL,
        loopbackPort: Int,
        pkceMode: PKCEMode = .auto,
        scope: String = "repo read:org",
        timeout: TimeInterval = 180
    ) async throws -> OAuthTokens {
        let normalizedHost = try Self.normalizeHost(host)
        let authBase = normalizedHost.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let authEndpoint = URL(string: "\(authBase)/login/oauth/authorize")!
        let tokenEndpoint = URL(string: "\(authBase)/login/oauth/access_token")!

        let usePKCE = await Self.shouldUsePKCE(
            mode: pkceMode,
            host: normalizedHost,
            dataProvider: self.dataProvider
        )
        let pkce = usePKCE ? PKCE.generate() : nil
        let state = self.stateProvider()

        let server = self.makeLoopbackServer(loopbackPort)
        let redirectURL = try server.start()
        defer { server.stop() }

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
        try self.openURL(authorizeURL)

        let result = try await server.waitForCallback(timeout: timeout)
        guard result.state == state else { throw URLError(.badServerResponse) }

        var tokenParams = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": result.code,
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

        let (data, response) = try await self.dataProvider(tokenRequest)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        let tokens = OAuthTokens(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken ?? "",
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expiresIn ?? 3600))
        )
        try self.tokenStore.save(tokens: tokens)
        try self.tokenStore.save(clientCredentials: OAuthClientCredentials(clientID: clientID, clientSecret: clientSecret))
        return tokens
    }

    /// Determines whether to use PKCE based on mode and host.
    /// For "auto" mode, enables PKCE for GitHub.com and GHE >= 3.15, disables for older GHE.
    /// See: https://docs.github.com/en/enterprise-server@3.12/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps
    private static func shouldUsePKCE(
        mode: PKCEMode,
        host: URL,
        dataProvider: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) async -> Bool {
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
            let gheVersion = await detectGHEVersion(host: host, dataProvider: dataProvider)
            if let version = gheVersion {
                return version >= GHEVersion(major: 3, minor: 15)
            }
            return false
        }
    }

    /// Detects GitHub Enterprise Server version by checking X-GitHub-Enterprise-Version header.
    private static func detectGHEVersion(
        host: URL,
        dataProvider: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) async -> GHEVersion? {
        let apiURL = host.appendingPathComponent("api/v3")
        var request = URLRequest(url: apiURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await dataProvider(request)
            guard let httpResponse = response as? HTTPURLResponse,
                  let versionString = httpResponse.value(forHTTPHeaderField: "X-GitHub-Enterprise-Version") else {
                return nil
            }
            return GHEVersion(string: versionString)
        } catch {
            return nil
        }
    }

    public static func normalizeHost(_ host: URL) throws -> URL {
        guard var components = URLComponents(url: host, resolvingAgainstBaseURL: false) else {
            throw GitHubAPIError.invalidHost
        }
        if components.scheme == nil { components.scheme = "https" }
        guard components.scheme?.lowercased() == "https", components.host != nil else {
            throw GitHubAPIError.invalidHost
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        guard let cleaned = components.url else { throw GitHubAPIError.invalidHost }
        return cleaned
    }
}

private extension OAuthLoginFlow {
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
struct GHEVersion: Comparable {
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
