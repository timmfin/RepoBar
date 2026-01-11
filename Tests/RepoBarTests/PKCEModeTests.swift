import Foundation
@testable import RepoBarCore
import Testing

struct PKCEModeTests {
    // MARK: - PKCEMode enum tests

    @Test
    func modeLabelsAreDescriptive() {
        #expect(PKCEMode.auto.label == "Auto (recommended)")
        #expect(PKCEMode.on.label == "Always on")
        #expect(PKCEMode.off.label == "Off (legacy GHE < 3.15)")
    }

    @Test
    func modeDescriptionsExist() {
        #expect(!PKCEMode.auto.description.isEmpty)
        #expect(!PKCEMode.on.description.isEmpty)
        #expect(!PKCEMode.off.description.isEmpty)
    }

    @Test
    func modeRawValuesForCodable() {
        #expect(PKCEMode.auto.rawValue == "auto")
        #expect(PKCEMode.on.rawValue == "on")
        #expect(PKCEMode.off.rawValue == "off")
    }

    // MARK: - PKCE mode=off tests

    @Test
    @MainActor
    func loginWithPKCEOff_doesNotIncludePKCEParams() async throws {
        let result = try await runLoginFlow(
            host: "https://ghe.example.com",
            pkceMode: .off,
            gheVersion: nil
        )

        #expect(!result.authURLContainsCodeChallenge, "Auth URL should NOT contain code_challenge when PKCE=off")
        #expect(!result.tokenRequestContainsCodeVerifier, "Token request should NOT contain code_verifier when PKCE=off")
    }

    // MARK: - PKCE mode=on tests

    @Test
    @MainActor
    func loginWithPKCEOn_includesPKCEParams() async throws {
        let result = try await runLoginFlow(
            host: "https://ghe.example.com",
            pkceMode: .on,
            gheVersion: nil
        )

        #expect(result.authURLContainsCodeChallenge, "Auth URL should contain code_challenge when PKCE=on")
        #expect(result.tokenRequestContainsCodeVerifier, "Token request should contain code_verifier when PKCE=on")
    }

    @Test
    @MainActor
    func loginWithPKCEOn_overridesOldGHEVersion() async throws {
        let result = try await runLoginFlow(
            host: "https://ghe.example.com",
            pkceMode: .on,
            gheVersion: "3.12.0"
        )

        #expect(result.authURLContainsCodeChallenge, "PKCE=on should override GHE version detection")
        #expect(result.tokenRequestContainsCodeVerifier, "PKCE=on should override GHE version detection")
    }

    // MARK: - PKCE mode=auto tests (the main feature)

    @Test
    @MainActor
    func loginWithPKCEAuto_enablesForGitHubCom() async throws {
        let result = try await runLoginFlow(
            host: "https://github.com",
            pkceMode: .auto,
            gheVersion: nil
        )

        #expect(result.authURLContainsCodeChallenge, "Auto mode should enable PKCE for github.com")
        #expect(result.tokenRequestContainsCodeVerifier, "Auto mode should enable PKCE for github.com")
    }

    @Test
    @MainActor
    func loginWithPKCEAuto_disablesForGHEBelow315() async throws {
        let result = try await runLoginFlow(
            host: "https://ghe.example.com",
            pkceMode: .auto,
            gheVersion: "3.12.17"
        )

        #expect(!result.authURLContainsCodeChallenge, "Auto mode should disable PKCE for GHE < 3.15")
        #expect(!result.tokenRequestContainsCodeVerifier, "Auto mode should disable PKCE for GHE < 3.15")
    }

    @Test
    @MainActor
    func loginWithPKCEAuto_disablesForGHE314() async throws {
        let result = try await runLoginFlow(
            host: "https://ghe.example.com",
            pkceMode: .auto,
            gheVersion: "3.14.99"
        )

        #expect(!result.authURLContainsCodeChallenge, "Auto mode should disable PKCE for GHE 3.14.x")
        #expect(!result.tokenRequestContainsCodeVerifier, "Auto mode should disable PKCE for GHE 3.14.x")
    }

    @Test
    @MainActor
    func loginWithPKCEAuto_enablesForGHE315_boundary() async throws {
        let result = try await runLoginFlow(
            host: "https://ghe.example.com",
            pkceMode: .auto,
            gheVersion: "3.15.0"
        )

        #expect(result.authURLContainsCodeChallenge, "Auto mode should enable PKCE for GHE >= 3.15 (boundary)")
        #expect(result.tokenRequestContainsCodeVerifier, "Auto mode should enable PKCE for GHE >= 3.15 (boundary)")
    }

    @Test
    @MainActor
    func loginWithPKCEAuto_enablesForGHE316() async throws {
        let result = try await runLoginFlow(
            host: "https://ghe.example.com",
            pkceMode: .auto,
            gheVersion: "3.16.5"
        )

        #expect(result.authURLContainsCodeChallenge, "Auto mode should enable PKCE for GHE > 3.15")
        #expect(result.tokenRequestContainsCodeVerifier, "Auto mode should enable PKCE for GHE > 3.15")
    }

    @Test
    @MainActor
    func loginWithPKCEAuto_disablesWhenVersionDetectionFails() async throws {
        let result = try await runLoginFlow(
            host: "https://ghe.example.com",
            pkceMode: .auto,
            gheVersion: nil,
            versionDetectionFails: true
        )

        #expect(!result.authURLContainsCodeChallenge, "Auto mode should disable PKCE when version detection fails (fail-safe for old GHE)")
        #expect(!result.tokenRequestContainsCodeVerifier, "Auto mode should disable PKCE when version detection fails")
    }

    @Test
    @MainActor
    func loginWithPKCEAuto_disablesWhenVersionUnparseable() async throws {
        let result = try await runLoginFlow(
            host: "https://ghe.example.com",
            pkceMode: .auto,
            gheVersion: "invalid-version"
        )

        #expect(!result.authURLContainsCodeChallenge, "Auto mode should disable PKCE when version is unparseable")
        #expect(!result.tokenRequestContainsCodeVerifier, "Auto mode should disable PKCE when version is unparseable")
    }
}

// MARK: - Test Helpers

private struct LoginFlowResult {
    let authURLContainsCodeChallenge: Bool
    let authURLContainsCodeChallengeMethod: Bool
    let tokenRequestContainsCodeVerifier: Bool
}

private final class CapturedPKCEState: @unchecked Sendable {
    private let lock = NSLock()
    private var _authURLContainsCodeChallenge = false
    private var _authURLContainsCodeChallengeMethod = false
    private var _tokenRequestContainsCodeVerifier = false

    var authURLContainsCodeChallenge: Bool {
        get { lock.withLock { _authURLContainsCodeChallenge } }
        set { lock.withLock { _authURLContainsCodeChallenge = newValue } }
    }

    var authURLContainsCodeChallengeMethod: Bool {
        get { lock.withLock { _authURLContainsCodeChallengeMethod } }
        set { lock.withLock { _authURLContainsCodeChallengeMethod = newValue } }
    }

    var tokenRequestContainsCodeVerifier: Bool {
        get { lock.withLock { _tokenRequestContainsCodeVerifier } }
        set { lock.withLock { _tokenRequestContainsCodeVerifier = newValue } }
    }
}

@MainActor
private func runLoginFlow(
    host: String,
    pkceMode: PKCEMode,
    gheVersion: String?,
    versionDetectionFails: Bool = false
) async throws -> LoginFlowResult {
    let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
    let store = TokenStore(service: service)
    defer { store.clear() }

    let captured = CapturedPKCEState()

    let session = URLSession(configuration: mockSessionConfiguration())
    let handlerID = UUID().uuidString

    MockURLProtocol.register(handlerID: handlerID) { request in
        let path = request.url?.path ?? ""

        if path.hasSuffix("/api/v3") {
            if versionDetectionFails {
                let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (Data(), response)
            }
            var headers: [String: String] = [:]
            if let version = gheVersion {
                headers["X-GitHub-Enterprise-Version"] = version
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!
            return (Data(), response)
        }

        if path.contains("/login/oauth/access_token") {
            if let body = bodyString(from: request) {
                let params = parseFormURLEncoded(body)
                captured.tokenRequestContainsCodeVerifier = params["code_verifier"] != nil && !params["code_verifier"]!.isEmpty
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            {"access_token":"tok","token_type":"bearer","scope":"repo","expires_in":3600,"refresh_token":"ref"}
            """.utf8)
            return (data, response)
        }

        let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
        return (Data(), response)
    }
    defer { MockURLProtocol.unregister(handlerID: handlerID) }

    let fakeRedirectURL = URL(string: "http://127.0.0.1:12345/callback")!
    let server = FakeLoopbackServer(
        redirectURL: fakeRedirectURL,
        result: (code: "code-123", state: "state-123")
    )
    let hostURL = URL(string: host)!

    let flow = OAuthLoginFlow(
        tokenStore: store,
        openURL: { url in
            if let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
                captured.authURLContainsCodeChallenge = query.contains { $0.name == "code_challenge" && $0.value?.isEmpty == false }
                captured.authURLContainsCodeChallengeMethod = query.contains { $0.name == "code_challenge_method" && $0.value == "S256" }
            }
        },
        dataProvider: { request in
            let (tagged, _) = taggedRequest(request, handlerID: handlerID)
            return try await session.data(for: tagged)
        },
        makeLoopbackServer: { _ in server },
        stateProvider: { "state-123" }
    )

    _ = try await flow.login(
        clientID: "cid",
        clientSecret: "csecret",
        host: hostURL,
        loopbackPort: 12345,
        pkceMode: pkceMode,
        timeout: 5
    )

    return LoginFlowResult(
        authURLContainsCodeChallenge: captured.authURLContainsCodeChallenge,
        authURLContainsCodeChallengeMethod: captured.authURLContainsCodeChallengeMethod,
        tokenRequestContainsCodeVerifier: captured.tokenRequestContainsCodeVerifier
    )
}

private func parseFormURLEncoded(_ body: String) -> [String: String] {
    var result: [String: String] = [:]
    for pair in body.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1)
        if parts.count == 2 {
            let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            result[key] = value
        }
    }
    return result
}

private func mockSessionConfiguration() -> URLSessionConfiguration {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return config
}

private final class FakeLoopbackServer: LoopbackServing {
    private let redirectURL: URL
    private let result: (code: String, state: String)

    init(redirectURL: URL, result: (code: String, state: String)) {
        self.redirectURL = redirectURL
        self.result = result
    }

    func start() throws -> URL { self.redirectURL }
    func waitForCallback(timeout _: TimeInterval) async throws -> (code: String, state: String) { self.result }
    func stop() {}
}

// swiftlint:disable static_over_final_class
private final class MockURLProtocol: URLProtocol {
    private static let handlersLock = NSLock()
    private nonisolated(unsafe) static var handlers: [String: @Sendable (URLRequest) throws -> (Data, URLResponse)] = [:]

    static func register(
        handlerID: String,
        handler: @escaping @Sendable (URLRequest) throws -> (Data, URLResponse)
    ) {
        self.handlersLock.lock()
        self.handlers[handlerID] = handler
        self.handlersLock.unlock()
    }

    static func unregister(handlerID: String) {
        self.handlersLock.lock()
        self.handlers[handlerID] = nil
        self.handlersLock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        URLProtocol.property(forKey: "handlerID", in: request) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard
            let handlerID = URLProtocol.property(forKey: "handlerID", in: request) as? String,
            let handler = Self.handler(for: handlerID)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func handler(for handlerID: String) -> (@Sendable (URLRequest) throws -> (Data, URLResponse))? {
        self.handlersLock.lock()
        defer { handlersLock.unlock() }
        return self.handlers[handlerID]
    }
}
// swiftlint:enable static_over_final_class

private func bodyString(from request: URLRequest) -> String? {
    if let body = request.httpBody, let string = String(data: body, encoding: .utf8) {
        return string
    }

    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 4 * 1024
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: buffer.count)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return String(data: data, encoding: .utf8)
}

private func taggedRequest(_ request: URLRequest, handlerID: String) -> (URLRequest, NSMutableURLRequest) {
    let boxed = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
    URLProtocol.setProperty(handlerID, forKey: "handlerID", in: boxed)
    return (boxed as URLRequest, boxed)
}
