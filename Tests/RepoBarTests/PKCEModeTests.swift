import Foundation
@testable import RepoBarCore
import Testing

private final class CapturedBody: @unchecked Sendable {
    var value: String?
}

struct PKCEModeTests {
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

    @Test
    @MainActor
    func loginWithPKCEOff_doesNotIncludeCodeVerifier() async throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        let capturedBody = CapturedBody()
        let session = URLSession(configuration: mockSessionConfiguration())
        let handlerID = UUID().uuidString

        MockURLProtocol.register(handlerID: handlerID) { request in
            if request.url?.path.contains("/login/oauth/access_token") == true {
                capturedBody.value = bodyString(from: request)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            {"access_token":"tok","token_type":"bearer","scope":"repo","expires_in":3600,"refresh_token":"ref"}
            """.utf8)
            return (data, response)
        }
        defer { MockURLProtocol.unregister(handlerID: handlerID) }

        let fakeRedirectURL = URL(string: "http://127.0.0.1:12345/callback")!
        let server = FakeLoopbackServer(
            redirectURL: fakeRedirectURL,
            result: (code: "code-123", state: "state-123")
        )
        let host = URL(string: "https://ghe.example.com")!

        let flow = OAuthLoginFlow(
            tokenStore: store,
            openURL: { _ in },
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
            host: host,
            loopbackPort: 12345,
            pkceMode: .off,
            timeout: 2
        )

        let body = try #require(capturedBody.value)
        #expect(!body.contains("code_verifier"))
    }

    @Test
    @MainActor
    func loginWithPKCEOn_includesCodeVerifier() async throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        let capturedBody = CapturedBody()
        let session = URLSession(configuration: mockSessionConfiguration())
        let handlerID = UUID().uuidString

        MockURLProtocol.register(handlerID: handlerID) { request in
            if request.url?.path.contains("/login/oauth/access_token") == true {
                capturedBody.value = bodyString(from: request)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            {"access_token":"tok","token_type":"bearer","scope":"repo","expires_in":3600,"refresh_token":"ref"}
            """.utf8)
            return (data, response)
        }
        defer { MockURLProtocol.unregister(handlerID: handlerID) }

        let fakeRedirectURL = URL(string: "http://127.0.0.1:12345/callback")!
        let server = FakeLoopbackServer(
            redirectURL: fakeRedirectURL,
            result: (code: "code-123", state: "state-123")
        )
        let host = URL(string: "https://ghe.example.com")!

        let flow = OAuthLoginFlow(
            tokenStore: store,
            openURL: { _ in },
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
            host: host,
            loopbackPort: 12345,
            pkceMode: .on,
            timeout: 2
        )

        let body = try #require(capturedBody.value)
        #expect(body.contains("code_verifier"))
    }

    @Test
    @MainActor
    func loginWithPKCEAuto_enablesForGitHubCom() async throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        let capturedBody = CapturedBody()
        let session = URLSession(configuration: mockSessionConfiguration())
        let handlerID = UUID().uuidString

        MockURLProtocol.register(handlerID: handlerID) { request in
            if request.url?.path.contains("/login/oauth/access_token") == true {
                capturedBody.value = bodyString(from: request)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            {"access_token":"tok","token_type":"bearer","scope":"repo","expires_in":3600,"refresh_token":"ref"}
            """.utf8)
            return (data, response)
        }
        defer { MockURLProtocol.unregister(handlerID: handlerID) }

        let fakeRedirectURL = URL(string: "http://127.0.0.1:12345/callback")!
        let server = FakeLoopbackServer(
            redirectURL: fakeRedirectURL,
            result: (code: "code-123", state: "state-123")
        )
        let host = URL(string: "https://github.com")!

        let flow = OAuthLoginFlow(
            tokenStore: store,
            openURL: { _ in },
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
            host: host,
            loopbackPort: 12345,
            pkceMode: .auto,
            timeout: 2
        )

        let body = try #require(capturedBody.value)
        #expect(body.contains("code_verifier"))
    }
}

// MARK: - Test Helpers

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
