import Foundation
import XCTest
@testable import SubscriptionUsage

@MainActor
final class CodexLoginClientTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    // Independent RFC 7636 S256 test vector, not calculated with production code.
    private let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    private let challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

    func test403And404RemainPendingWithoutReturningAuthorizationCode() async throws {
        for status in [403, 404] {
            let transport = LoginTransportStub(body: "pending", status: status)
            let result = try await client(transport).poll(authorization())
            XCTAssertNil(result, "官网尚未确认时不能取得有效授权码")
            let requests = await transport.requests
            let request = try XCTUnwrap(requests.first)
            XCTAssertEqual(request.url, CodexLoginClient.pollURL)
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String]
            XCTAssertEqual(body, ["device_auth_id": "synthetic-device", "user_code": "TEST-1234"])
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        }
        print("T08 | 官网尚未确认（403／404） | 保持等待，不视为登录成功")
    }

    func testMatchingPKCEChallengeReturnsCodeAndMismatchFailsClosed() async throws {
        let accepted = try await client(.init(body: pollBody())).poll(authorization())
        XCTAssertTrue(accepted?.code == "synthetic-code")
        XCTAssertTrue(accepted?.verifier == verifier)
        await assertPollFails(.init(body: pollBody(challenge: "different-challenge")))
        print("T08 | 授权码与 PKCE | 匹配才接收；不匹配拒绝")
    }

    func testMalformedCodesVerifiersAndPollResponsesAreRejected() async {
        for value in ["", "synthetic code", "synthetic\ncode"] {
            await assertPollFails(.init(body: pollBody(code: value)))
        }
        for value in ["", String(repeating: "a", count: 42), String(repeating: "a", count: 129),
                      String(repeating: "a", count: 42) + "+"] {
            await assertPollFails(.init(body: pollBody(verifier: value)))
        }
        for body in ["{}", "[]", "not-json"] { await assertPollFails(.init(body: body)) }
        for status in [302, 400, 401, 429, 500] {
            await assertPollFails(.init(body: pollBody(), status: status))
        }
    }

    func testExpiredAuthorizationIsRejectedBeforeSendingRequest() async throws {
        let authorization = try authorization()
        let transport = LoginTransportStub(body: pollBody())
        let deadline = authorization.expiresAt
        do {
            _ = try await CodexLoginClient(transport: transport, now: { deadline }).poll(authorization)
            XCTFail("到期授权不能继续领取")
        } catch { XCTAssertEqual(error as? CodexLoginError, .failed) }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testExchangeUsesExactOfficialFormAndDoesNotTreatTokensAsVerifiedIdentity() async throws {
        let transport = LoginTransportStub(body: tokenBody())
        let tokens = try await client(transport).exchange(.init(code: "synthetic+code/=", verifier: verifier))
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://auth.openai.com/oauth/token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8),
                       "grant_type=authorization_code&client_id=app_EMoamEEZ73f0CkXaXp7hrann&code=synthetic%2Bcode%2F%3D&code_verifier=\(verifier)&redirect_uri=https%3A%2F%2Fauth.openai.com%2Fdeviceauth%2Fcallback")
        XCTAssertTrue(tokens.accessToken == "synthetic-access")
        XCTAssertTrue(tokens.refreshToken == "synthetic-refresh")
        XCTAssertTrue(tokens.idToken == "synthetic-id")
        XCTAssertEqual(tokens.obtainedAt, start)
        XCTAssertEqual(tokens.expiresAt, start.addingTimeInterval(3600))
        print("T08 | 令牌交换 | 固定官网与回调，表单转义正确；仍是待核验结果")
    }

    func testInvalidTokenBodiesDoNotProduceTokenPackage() async {
        for body in ["{}", "not-json",
                     tokenBody(access: ""), tokenBody(refresh: ""), tokenBody(id: ""),
                     tokenBody(access: "has space"), tokenBody(type: "mac"),
                     tokenBody(expiry: "0"), tokenBody(expiry: "-1"), tokenBody(expiry: "1e999")] {
            await assertExchangeFails(.init(body: body))
        }
    }

    func testRedirectHTMLNonHTTPAndOversizedResponsesAreRejected() async {
        let body = tokenBody()
        await assertExchangeFails(.init(body: body, responseURL: URL(string: "https://example.invalid/token")!))
        await assertExchangeFails(.init(body: body, contentType: "text/html"))
        await assertExchangeFails(.init(body: body, nonHTTP: true))
        await assertExchangeFails(.init(body: String(repeating: "a", count: 256 * 1024 + 1)))
    }

    func testSensitiveServerAndTransportErrorsAreSanitized() async {
        await assertExchangeFails(.init(body: "synthetic-sensitive-response", status: 401))
        await assertExchangeFails(.init(body: "", error: NSError(domain: "synthetic-secret-domain", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "synthetic-sensitive-description"])))
        print("T08 | 错误去敏 | 仅保留简短内部失败，不透出服务端正文或授权内容")
    }

    func testCancellationDiscardsLateExchangeResponse() async {
        let transport = LoginTransportStub(body: tokenBody(), suspended: true)
        let service = client(transport)
        let code = CodexAuthorizationCode(code: "synthetic-code", verifier: verifier)
        let task = Task { try await service.exchange(code) }
        await transport.entered.wait()
        task.cancel()
        await transport.release.open()
        do { _ = try await task.value; XCTFail("取消后的令牌不能交给验证器") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testSensitiveModelDescriptionsAndReflectionAreRedacted() {
        let code = CodexAuthorizationCode(code: "synthetic-code", verifier: verifier)
        let tokens = CodexTokenResponse(accessToken: "synthetic-access", refreshToken: "synthetic-refresh",
                                        idToken: "synthetic-id", obtainedAt: start, expiresAt: nil)
        for value in [String(describing: code), String(reflecting: code),
                      String(describing: tokens), String(reflecting: tokens)] {
            XCTAssertFalse(value.contains("synthetic"))
            XCTAssertFalse(value.contains(verifier))
        }
        XCTAssertTrue(Mirror(reflecting: code).children.isEmpty)
        XCTAssertTrue(Mirror(reflecting: tokens).children.isEmpty)
    }

    private func authorization() throws -> CodexDeviceAuthorization {
        try .init(deviceAuthID: "synthetic-device", userCode: "TEST-1234", pollInterval: 5, startedAt: start)
    }

    private func client(_ transport: LoginTransportStub) -> CodexLoginClient {
        let date = start
        return .init(transport: transport, now: { date })
    }

    private func pollBody(code: String = "synthetic-code", verifier: String? = nil, challenge: String? = nil) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["authorization_code": code,
            "code_verifier": verifier ?? self.verifier, "code_challenge": challenge ?? self.challenge])
        return String(decoding: data, as: UTF8.self)
    }

    private func tokenBody(access: String = "synthetic-access", refresh: String = "synthetic-refresh",
                           id: String = "synthetic-id", type: String = "Bearer", expiry: String = "3600") -> String {
        "{\"access_token\":\"\(access)\",\"refresh_token\":\"\(refresh)\",\"id_token\":\"\(id)\",\"token_type\":\"\(type)\",\"expires_in\":\(expiry)}"
    }

    private func assertPollFails(_ transport: LoginTransportStub) async {
        do { _ = try await client(transport).poll(authorization()); XCTFail("无效授权结果不能继续") }
        catch { XCTAssertEqual(error as? CodexLoginError, .failed) }
    }

    private func assertExchangeFails(_ transport: LoginTransportStub) async {
        do {
            _ = try await client(transport).exchange(.init(code: "synthetic-code", verifier: verifier))
            XCTFail("失败响应不能生成令牌包")
        } catch {
            XCTAssertEqual(error as? CodexLoginError, .failed)
            XCTAssertFalse(String(reflecting: error).contains("synthetic"))
        }
    }
}

private actor LoginTransportStub: CodexDeviceAuthorizationTransport {
    let entered = LoginClientGate()
    let release = LoginClientGate()
    private let body: String
    private let status: Int
    private let contentType: String
    private let responseURL: URL?
    private let nonHTTP: Bool
    private let error: NSError?
    private let suspended: Bool
    private(set) var requests: [URLRequest] = []

    init(body: String, status: Int = 200, contentType: String = "application/json",
         responseURL: URL? = nil, nonHTTP: Bool = false, error: NSError? = nil, suspended: Bool = false) {
        self.body = body; self.status = status; self.contentType = contentType
        self.responseURL = responseURL; self.nonHTTP = nonHTTP; self.error = error; self.suspended = suspended
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        if suspended { await entered.open(); await release.wait() }
        if let error { throw error }
        let url = responseURL ?? request.url!
        let response: URLResponse = nonHTTP
            ? URLResponse(url: url, mimeType: contentType, expectedContentLength: body.utf8.count, textEncodingName: "utf-8")
            : HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": contentType])!
        return (Data(body.utf8), response)
    }
}

private actor LoginClientGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        let pending = waiters; waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}
