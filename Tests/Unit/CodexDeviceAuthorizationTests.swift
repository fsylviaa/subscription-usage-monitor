import Foundation
import XCTest
@testable import SubscriptionUsage

@MainActor
final class CodexDeviceAuthorizationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    func testRequestUsesPinnedOfficialEndpointAndOnlyPublicClientID() async throws {
        let transport = DeviceAuthorizationTransportStub()
        let authorization = try await client(transport).requestAuthorization()
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1, "申请一次，不轮询或交换令牌")
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://auth.openai.com/api/accounts/deviceauth/usercode")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String]
        XCTAssertEqual(body, ["client_id": "app_EMoamEEZ73f0CkXaXp7hrann"])
        XCTAssertEqual(authorization.provider, .openAI)
        XCTAssertEqual(authorization.product, .codexSubscription)
        XCTAssertEqual(authorization.clientID, CodexDeviceAuthorization.clientID)
        print("T07 | 申请设备码 | 仅请求官方地址，不轮询、不保存账户")
    }

    func testStringAndIntegerIntervalAndBothUserCodeNamesAreAccepted() async throws {
        for key in ["user_code", "usercode"] {
            for interval in ["\"5\"", "\" 5 \"", "5"] {
                let body = "{\"device_auth_id\":\"synthetic-device\",\"\(key)\":\"TEST-1234\",\"interval\":\(interval)}"
                let authorization = try await client(.init(body: body)).requestAuthorization()
                XCTAssertTrue(authorization.userCode == "TEST-1234")
                XCTAssertTrue(authorization.deviceAuthID == "synthetic-device")
                XCTAssertEqual(authorization.pollInterval, 5)
            }
        }
    }

    func testEmptyMalformedAndConflictingCodesAreRejected() async {
        let bodies = [
            "{}", "[]", "not-json",
            "{\"device_auth_id\":\"synthetic-device\",\"interval\":\"5\"}",
            "{\"device_auth_id\":\"synthetic-device\",\"user_code\":\"TEST-1234\",\"usercode\":\"DIFFERENT\",\"interval\":\"5\"}"
        ]
        for body in bodies { await assertFailure(.invalidResponse, body: body) }
        for userCode in ["", " ", "--", "TEST 123", "TEST\n123", "TEST\u{200B}123", "https://example.invalid", String(repeating: "A", count: 65)] {
            await assertFailure(.invalidResponse, body: body(userCode: userCode))
        }
        for deviceID in ["", " ", "a\nb", String(repeating: "d", count: 1025)] {
            await assertFailure(.invalidResponse, body: body(deviceID: deviceID))
        }
        print("T07 | 缺失、无效或冲突代码 | 简短失败，无有效事务")
    }

    func testMissingInvalidAndUnsafeIntervalsAreRejected() async {
        for interval in ["null", "true", "false", "0", "-1", "1.5", "901", "1e999",
                         "\"\"", "\"0\"", "\"-1\"", "\"1.5\"", "\"5e1\"", "\"abc\"", "\"18446744073709551616\""] {
            await assertFailure(.invalidResponse, body: "{\"device_auth_id\":\"synthetic-device\",\"user_code\":\"TEST-1234\",\"interval\":\(interval)}")
        }
        await assertFailure(.invalidResponse, body: "{\"device_auth_id\":\"synthetic-device\",\"user_code\":\"TEST-1234\"}")
    }

    func testVerificationURLIsOfficialAndNeverContainsOrTrustsAResponseCodeURL() async throws {
        let body = "{\"device_auth_id\":\"synthetic-device\",\"user_code\":\"TEST-1234\",\"interval\":\"5\",\"verification_uri\":\"https://evil.invalid\",\"verification_uri_complete\":\"https://evil.invalid/?code=FAKE\"}"
        let authorization = try await client(.init(body: body)).requestAuthorization()
        XCTAssertEqual(authorization.verificationURL.absoluteString, "https://auth.openai.com/codex/device")
        XCTAssertNil(authorization.verificationURL.query)
        XCTAssertNil(authorization.verificationURL.fragment)
        print("T07 | 打开地址 | 固定 OpenAI 官方 HTTPS 页面，不拼接或预填代码")
    }

    func testOriginalDeadlineStartsBeforeRequestAndSurvivesEncoding() async throws {
        let clock = DeviceAuthorizationClock([start, start.addingTimeInterval(12)])
        let authorization = try await CodexDeviceAuthorizationClient(transport: DeviceAuthorizationTransportStub(), now: { clock.next() }).requestAuthorization()
        XCTAssertEqual(authorization.startedAt, start)
        XCTAssertEqual(authorization.expiresAt, start.addingTimeInterval(900))
        let recovered = try JSONDecoder().decode(CodexDeviceAuthorization.self, from: JSONEncoder().encode(authorization))
        XCTAssertEqual(recovered, authorization)
        XCTAssertFalse(recovered.isExpired(at: start.addingTimeInterval(899)))
        XCTAssertTrue(recovered.isExpired(at: start.addingTimeInterval(900)))
        print("T07 | 原始期限 | 从申请开始计时；编码读回不延长")
    }

    func testResponseArrivingAfterOriginalDeadlineIsRejected() async {
        let clock = DeviceAuthorizationClock([start, start.addingTimeInterval(900)])
        let service = CodexDeviceAuthorizationClient(transport: DeviceAuthorizationTransportStub(), now: { clock.next() })
        do {
            _ = try await service.requestAuthorization()
            XCTFail("到期结果不得进入代码步骤")
        } catch {
            XCTAssertEqual(error as? CodexDeviceAuthorizationError, .expired)
        }
    }

    func testPersistedMetadataAndExpiryTamperingAreRejected() throws {
        let authorization = try CodexDeviceAuthorization(deviceAuthID: "synthetic-device", userCode: "TEST-1234", pollInterval: 5, startedAt: start)
        let data = try JSONEncoder().encode(authorization)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for (key, value) in [
            ("provider", "other" as Any), ("product", "other"), ("clientID", "other"),
            ("verificationURL", "https://evil.invalid"), ("expiresAt", 0), ("pollInterval", 0)
        ] {
            var modified = original
            modified[key] = value
            let modifiedData = try JSONSerialization.data(withJSONObject: modified)
            XCTAssertThrowsError(try JSONDecoder().decode(CodexDeviceAuthorization.self, from: modifiedData))
        }
    }

    func testHTTPFailuresDoNotBecomePendingOrRevealBody() async {
        for status in [301, 400, 401, 403, 404, 429, 500] {
            let expected: CodexDeviceAuthorizationError = status == 404 ? .unavailable : .requestFailed
            await assertFailure(expected, transport: .init(body: "sensitive synthetic response", status: status))
        }
    }

    func testRedirectedNonHTTPEmptyHTMLAndOversizedResponsesAreRejected() async {
        await assertFailure(.invalidResponse, transport: .init(responseURL: URL(string: "https://evil.invalid")!))
        await assertFailure(.invalidResponse, transport: .init(nonHTTP: true))
        await assertFailure(.invalidResponse, transport: .init(body: ""))
        await assertFailure(.invalidResponse, transport: .init(contentType: "text/html"))
        await assertFailure(.invalidResponse, transport: .init(body: String(repeating: "a", count: 65 * 1024)))
    }

    func testTransportErrorsAreSanitized() async {
        await assertFailure(.timeout, transport: .init(error: URLError(.timedOut)))
        await assertFailure(.requestFailed, transport: .init(error: URLError(.notConnectedToInternet)))
    }

    func testCancellationBeforeRequestDoesNotSendAndLateSuccessIsDiscarded() async {
        let beforeTransport = DeviceAuthorizationTransportStub()
        let before = Task { @MainActor in
            try await client(beforeTransport).requestAuthorization()
        }
        before.cancel()
        do { _ = try await before.value; XCTFail("取消不得成功") }
        catch { XCTAssertTrue(error is CancellationError) }
        let requestsBefore = await beforeTransport.requests
        XCTAssertTrue(requestsBefore.isEmpty)

        let lateTransport = DeviceAuthorizationTransportStub(suspended: true)
        let late = Task { @MainActor in try await client(lateTransport).requestAuthorization() }
        await lateTransport.waitUntilRequested()
        late.cancel()
        await lateTransport.resume()
        do { _ = try await late.value; XCTFail("迟到结果不得成功") }
        catch { XCTAssertTrue(error is CancellationError) }
        print("T07 | 申请取消 | 未开始的不请求；已开始的迟到结果丢弃")
    }

    func testTransportCancelledErrorRemainsCancellation() async {
        do {
            _ = try await client(.init(error: URLError(.cancelled))).requestAuthorization()
            XCTFail("取消不得成功")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testSessionAndRepresentationsDoNotRetainCookiesOrRevealCodes() throws {
        let configuration = URLSessionCodexDeviceAuthorizationTransport.configuration()
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertFalse(configuration.waitsForConnectivity)
        let authorization = try CodexDeviceAuthorization(deviceAuthID: "synthetic-device", userCode: "TEST-1234", pollInterval: 5, startedAt: start)
        for text in [String(describing: authorization), String(reflecting: authorization)] {
            XCTAssertFalse(text.contains(authorization.userCode))
            XCTAssertFalse(text.contains(authorization.deviceAuthID))
        }
        XCTAssertTrue(Mirror(reflecting: authorization).children.isEmpty)
        print("T07 | 隐私检查 | 无浏览器 Cookie；事务描述与反射不含代码")
    }

    func testTransactionKeychainRoundTripPreservesOriginalIdentityAndDeadline() async throws {
        let scope = isolatedTransactionVault()
        let store = CodexLoginTransactionStore(vault: scope.vault)
        let authorization = try CodexDeviceAuthorization(deviceAuthID: "synthetic-device", userCode: "TEST-1234", pollInterval: 5, startedAt: start)
        try await store.save(authorization)
        let saved = try await scope.vault.load(for: scope.entry)
        let payload = try XCTUnwrap(saved)
        let recovered = try JSONDecoder().decode(CodexDeviceAuthorization.self, from: payload.data)
        XCTAssertTrue(recovered == authorization)
        XCTAssertEqual(recovered.transactionID, authorization.transactionID)
        XCTAssertEqual(recovered.expiresAt, start.addingTimeInterval(900))
        print("T07 | 临时钥匙串保存后读回 | 事务匹配，原期限不延长")
    }

    func testOldTransactionCancellationCannotDeleteReplacementOrFormalCredential() async throws {
        let scope = isolatedTransactionVault()
        let store = CodexLoginTransactionStore(vault: scope.vault)
        let old = try CodexDeviceAuthorization(deviceAuthID: "synthetic-old", userCode: "OLD-1234", pollInterval: 5, startedAt: start)
        let new = try CodexDeviceAuthorization(deviceAuthID: "synthetic-new", userCode: "NEW-1234", pollInterval: 5, startedAt: start.addingTimeInterval(15))
        let formal = CredentialPayload(data: Data("synthetic-existing-credential".utf8))
        try await scope.vault.save(formal, for: scope.formalEntry)
        try await store.save(old)
        try await store.save(new)
        try await store.remove(transactionID: old.transactionID)
        let pending = try await scope.vault.load(for: scope.entry)
        let saved = try JSONDecoder().decode(CodexDeviceAuthorization.self, from: XCTUnwrap(pending).data)
        XCTAssertTrue(saved == new)
        try await store.remove(transactionID: new.transactionID)
        try await store.remove(transactionID: new.transactionID)
        let removed = try await scope.vault.load(for: scope.entry)
        let remainingFormal = try await scope.vault.load(for: scope.formalEntry)
        XCTAssertNil(removed)
        XCTAssertTrue(remainingFormal == formal)
        print("T07 | 旧事务取消及当前事务清理 | 新事务不被误删，正式授权不变")
    }

    func testAtomicConditionalDeleteRechecksCurrentPackageAfterReplacement() async throws {
        let scope = isolatedTransactionVault()
        let old = CredentialPayload(data: Data("synthetic-old-pending".utf8))
        let new = CredentialPayload(data: Data("synthetic-new-pending".utf8))
        try await scope.vault.save(old, for: scope.entry)
        let captured = try await scope.vault.load(for: scope.entry)
        try await scope.vault.save(new, for: scope.entry)
        try await scope.vault.remove(ifMatching: XCTUnwrap(captured), for: scope.entry)
        let remaining = try await scope.vault.load(for: scope.entry)
        XCTAssertTrue(remaining == new)
        print("T07 | 读取旧包后新包写入再取消 | 条件清理保留新包")
    }

    private func isolatedTransactionVault() -> (vault: CredentialVault, entry: CredentialVault.Entry, formalEntry: CredentialVault.Entry) {
        let vault = CredentialVault(service: "com.iceflying.SubscriptionUsage.tests.T07.\(UUID().uuidString)")
        let slot = UUID(uuidString: "2BCEFFDE-7DC2-4F6A-89B0-020023689458")!
        let entry = CredentialVault.Entry.loginTransaction(slot)
        let formalEntry = CredentialVault.Entry.credential(slot)
        addTeardownBlock {
            try await vault.remove(for: entry)
            try await vault.remove(for: formalEntry)
        }
        return (vault, entry, formalEntry)
    }

    private func client(_ transport: DeviceAuthorizationTransportStub) -> CodexDeviceAuthorizationClient {
        let start = start
        return CodexDeviceAuthorizationClient(transport: transport, now: { start })
    }

    private func body(deviceID: String = "synthetic-device", userCode: String = "TEST-1234") -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["device_auth_id": deviceID, "user_code": userCode, "interval": "5"])
        return String(decoding: data, as: UTF8.self)
    }

    private func assertFailure(_ expected: CodexDeviceAuthorizationError, body: String) async {
        await assertFailure(expected, transport: .init(body: body))
    }

    private func assertFailure(_ expected: CodexDeviceAuthorizationError, transport: DeviceAuthorizationTransportStub) async {
        do {
            _ = try await client(transport).requestAuthorization()
            XCTFail("无效结果不得生成事务")
        } catch { XCTAssertEqual(error as? CodexDeviceAuthorizationError, expected) }
    }
}

private actor DeviceAuthorizationTransportStub: CodexDeviceAuthorizationTransport {
    private let body: String
    private let status: Int
    private let contentType: String
    private let responseURL: URL?
    private let nonHTTP: Bool
    private let error: URLError?
    private let suspended: Bool
    private var completion: CheckedContinuation<Void, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private(set) var requests: [URLRequest] = []

    init(body: String = "{\"device_auth_id\":\"synthetic-device\",\"user_code\":\"TEST-1234\",\"interval\":\"5\"}",
         status: Int = 200, contentType: String = "application/json", responseURL: URL? = nil,
         nonHTTP: Bool = false, error: URLError? = nil, suspended: Bool = false) {
        self.body = body
        self.status = status
        self.contentType = contentType
        self.responseURL = responseURL
        self.nonHTTP = nonHTTP
        self.error = error
        self.suspended = suspended
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        if suspended {
            await withCheckedContinuation { continuation in
                completion = continuation
                startWaiter?.resume()
                startWaiter = nil
            }
        }
        if let error { throw error }
        let url = responseURL ?? request.url!
        let response: URLResponse = nonHTTP
            ? URLResponse(url: url, mimeType: contentType, expectedContentLength: body.utf8.count, textEncodingName: "utf-8")
            : HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": contentType])!
        return (Data(body.utf8), response)
    }

    func waitUntilRequested() async {
        if completion != nil { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func resume() {
        completion?.resume()
        completion = nil
    }
}

private final class DeviceAuthorizationClock: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Date]

    init(_ values: [Date]) { self.values = values }

    func next() -> Date {
        lock.withLock { values.count > 1 ? values.removeFirst() : values[0] }
    }
}
