import Foundation
import Security
import XCTest
@testable import SubscriptionUsage

@MainActor
final class CodexIdentityVerifierTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 1_790_000_000)

    func testSignedIdentityAndLiveScopeProduceVerifiedCapabilityWithoutPublishingQuota() async throws {
        let signer = try SyntheticJWTSigner()
        let transport = IdentityTransportStub(jwks: signer.jwks)
        let gate = IdentityNetworkGate(.allowed(score: 51))
        let tokens = try tokens(signer)
        let result = try await verifier(transport, gate: gate).verify(tokens)
        XCTAssertEqual(result.email, "synthetic@example.invalid")
        XCTAssertEqual(result.remoteUserID, "user-synthetic")
        XCTAssertEqual(result.scope.remoteAccountID, "account-synthetic")
        XCTAssertEqual(result.scope.kind, .personal)
        XCTAssertNil(result.scope.label, "没有服务端名称就不编造")
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.url), [CodexIdentityVerifier.jwksURL, CodexIdentityVerifier.usageURL])
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer \(tokens.accessToken)")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "ChatGPT-Account-Id"), "account-synthetic")
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Cookie"))
        let checks = await gate.count
        XCTAssertEqual(checks, 1)
        let package = try XCTUnwrap(JSONSerialization.jsonObject(with: result.credentials.data) as? [String: Any])
        XCTAssertEqual(package["issuer"] as? String, "https://auth.openai.com")
        XCTAssertEqual(package["subject"] as? String, "subject-synthetic")
        XCTAssertEqual(package["credentialVersion"] as? Int, 1)
        XCTAssertNil(package["rate_limit"])
        XCTAssertNil(package["fetchedAt"])
        XCTAssertEqual(String(describing: result), "CodexVerifiedLogin(<redacted>)")
        XCTAssertEqual(Mirror(reflecting: result).children.count, 0)
        print("T08 | 身份核验 | 双令牌真实 RSA 验签及服务端作用域一致后才允许绑定；未发布额度")
    }

    func testTamperedClaimAndDifferentSigningKeyCannotBecomeVerifiedIdentity() async throws {
        let signer = try SyntheticJWTSigner()
        let otherSigner = try SyntheticJWTSigner()
        let original = try tokens(signer)
        var pieces = original.idToken.split(separator: ".").map(String.init)
        var changed = idClaims()
        changed["email"] = "someoneelse@example.invalid"
        pieces[1] = try encodedJSON(changed)
        let tampered = response(id: pieces.joined(separator: "."), access: original.accessToken)
        for input in [tampered, try tokens(otherSigner)] {
            let transport = IdentityTransportStub(jwks: signer.jwks)
            await assertFailure(input, transport: transport)
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1, "签名失败时不得请求额度接口")
        }
        print("T08 | 仅解码或伪造身份 | 签名不正确，无有效绑定")
    }

    func testWrongIssuerAudiencePartyAndExpiredOrFutureClaimsFailBeforeUsage() async throws {
        let signer = try SyntheticJWTSigner()
        let changes: [(String, Any)] = [
            ("iss", "https://unexpected.example.invalid"), ("aud", "another-client"),
            ("azp", "another-client"), ("aud", [CodexDeviceAuthorization.clientID, "another-client"]),
            ("exp", 1_789_999_994), ("iat", 1_790_000_010), ("nbf", 1_790_000_010),
            ("exp", "1790003600"), ("iat", true), ("sub", ""), ("sub", "subject\nvalue")
        ]
        for (key, value) in changes {
            var claims = idClaims()
            claims[key] = value
            let transport = IdentityTransportStub(jwks: signer.jwks)
            await assertFailure(try tokens(signer, id: claims), transport: transport)
            let requests = await transport.requests
            XCTAssertLessThanOrEqual(requests.count, 1)
        }
    }

    func testAccessTokenMustBeSignedForSamePersonClientAndScope() async throws {
        let signer = try SyntheticJWTSigner()
        var inputs: [[String: Any]] = []
        for (key, value) in [("sub", "another-subject"), ("aud", "another-resource"),
                             ("client_id", "another-client"), ("iss", "https://wrong.invalid")] {
            var claims = accessClaims()
            claims[key] = value
            inputs.append(claims)
        }
        for (key, value) in [("chatgpt_account_id", "another-account"), ("chatgpt_user_id", "another-user")] {
            var claims = accessClaims()
            var auth = try XCTUnwrap(claims["https://api.openai.com/auth"] as? [String: Any])
            auth[key] = value
            claims["https://api.openai.com/auth"] = auth
            inputs.append(claims)
        }
        for claims in inputs {
            let transport = IdentityTransportStub(jwks: signer.jwks)
            await assertFailure(try tokens(signer, access: claims), transport: transport)
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
        print("T08 | 两个账户令牌混用 | 即使同工作区也因签名身份不一致被拒绝")
    }

    func testMissingConflictingOrExplicitlyUnverifiedEmailAndScopeAreRejected() async throws {
        let signer = try SyntheticJWTSigner()
        var inputs: [[String: Any]] = []
        var noEmail = idClaims(); noEmail.removeValue(forKey: "email"); inputs.append(noEmail)
        var noAuth = idClaims(); noAuth.removeValue(forKey: "https://api.openai.com/auth"); inputs.append(noAuth)
        var unverified = idClaims(); unverified["email_verified"] = false; inputs.append(unverified)
        var conflict = idClaims(); conflict["https://api.openai.com/profile"] = ["email": "different@example.invalid"]; inputs.append(conflict)
        var badEmail = idClaims(); badEmail["email"] = "invalid\n@example.invalid"; inputs.append(badEmail)
        var badScope = idClaims(); badScope["https://api.openai.com/auth"] = ["chatgpt_account_id": "account\r\nvalue"]; inputs.append(badScope)
        var userConflict = idClaims(); userConflict["https://api.openai.com/auth"] = ["chatgpt_account_id": "account-synthetic", "chatgpt_user_id": "user-synthetic", "user_id": "another-user"]; inputs.append(userConflict)
        for claims in inputs {
            await assertFailure(try tokens(signer, id: claims), transport: .init(jwks: signer.jwks))
        }
    }

    func testProfileEmailAndAuthorizedPartyAliasesRemainSignedAndExplicit() async throws {
        let signer = try SyntheticJWTSigner()
        var id = idClaims()
        id.removeValue(forKey: "email")
        id["https://api.openai.com/profile"] = ["email": "profile@example.invalid", "email_verified": true]
        id["aud"] = [CodexDeviceAuthorization.clientID, "another-audience"]
        id["azp"] = CodexDeviceAuthorization.clientID
        id["https://api.openai.com/auth"] = ["chatgpt_account_id": "account-synthetic", "user_id": "user-synthetic", "chatgpt_plan_type": "business"]
        var access = accessClaims()
        access.removeValue(forKey: "client_id")
        access["azp"] = CodexDeviceAuthorization.clientID
        let result = try await verifier(.init(jwks: signer.jwks)).verify(tokens(signer, id: id, access: access))
        XCTAssertEqual(result.email, "profile@example.invalid")
        XCTAssertEqual(result.scope.kind, .workspace)
    }

    func testUsageMustConfirmAccountAndAnyReturnedUserWithoutFallbackToAnotherScope() async throws {
        let signer = try SyntheticJWTSigner()
        let input = try tokens(signer)
        for usage in ["{}", "[]", "{\"account_id\":\"another-account\"}",
                      "{\"account_id\":\"account-synthetic\",\"user_id\":\"another-user\"}",
                      "{\"account_id\":\"account-synthetic\",\"accountId\":\"another-account\"}",
                      "{\"account_id\":\"account-synthetic\",\"email\":\"different@example.invalid\"}",
                      "{\"account_id\":\"account-synthetic\",\"user_id\":true}"] {
            await assertFailure(input, transport: .init(jwks: signer.jwks, usage: Data(usage.utf8)))
        }
        print("T08 | 核验请求返回错误或缺失身份 | 保持未验证，不回退其他账户")
    }

    func testLowOrUnknownNetworkStopsUsageAndCancellationRemainsCancellation() async throws {
        let signer = try SyntheticJWTSigner()
        let input = try tokens(signer)
        for (network, expected) in [(NetworkScoreResult.blocked(score: 50), CodexLoginError.networkBlocked),
                                     (.blocked(score: 0), .networkBlocked), (.unavailable(.timeout), .failed)] {
            let transport = IdentityTransportStub(jwks: signer.jwks)
            await assertFailure(input, transport: transport, gate: .init(network), expected: expected)
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1, "低分或未知不得请求 usage")
        }
        do {
            _ = try await verifier(.init(jwks: signer.jwks), gate: .init(.cancelled)).verify(input)
            XCTFail("取消后不能绑定")
        } catch { XCTAssertTrue(error is CancellationError) }
        print("T08 | 验证前网络不达标或未知 | 不请求额度接口，不生成有效账户")
    }

    func testInvalidKeyAlgorithmUnknownOrDuplicateKeyIDAreRejected() async throws {
        let signer = try SyntheticJWTSigner()
        let input = try tokens(signer)
        var wrongAlgorithm = signer.jwk; wrongAlgorithm["alg"] = "HS256"
        var wrongUsage = signer.jwk; wrongUsage["use"] = "enc"
        var unknownKey = signer.jwk; unknownKey["kid"] = "unknown"
        for keys in [[], [wrongAlgorithm], [wrongUsage], [unknownKey], [signer.jwk, signer.jwk]] {
            let jwks = try JSONSerialization.data(withJSONObject: ["keys": keys])
            await assertFailure(input, transport: .init(jwks: jwks))
        }
        for header in [["alg": "none", "kid": "synthetic-key"], ["alg": "HS256", "kid": "synthetic-key"]] {
            let id = try signer.sign(idClaims(), header: header)
            await assertFailure(response(id: id, access: input.accessToken), transport: .init(jwks: signer.jwks))
        }
    }

    func testRedirectedFailedOversizedAndNonJSONServerResponsesNeverVerify() async throws {
        let signer = try SyntheticJWTSigner()
        let input = try tokens(signer)
        for status in [301, 400, 401, 403, 429, 500] {
            await assertFailure(input, transport: .init(jwks: signer.jwks, usageStatus: status))
        }
        await assertFailure(input, transport: .init(jwks: signer.jwks, usageURL: URL(string: "https://other.invalid")!))
        await assertFailure(input, transport: .init(jwks: signer.jwks, usage: Data(repeating: 65, count: 256 * 1024 + 1)))
        await assertFailure(input, transport: .init(jwks: Data("<html>synthetic</html>".utf8)))
    }

    func testCancelledVerificationRejectsLateServerIdentityResponse() async throws {
        let signer = try SyntheticJWTSigner()
        let transport = IdentityTransportStub(jwks: signer.jwks, holdUsage: true)
        let input = try tokens(signer)
        let service = verifier(transport)
        let task = Task { try await service.verify(input) }
        await transport.waitForUsage()
        task.cancel()
        await transport.releaseUsage()
        do { _ = try await task.value; XCTFail("取消后的迟到响应不能产生有效绑定") }
        catch { XCTAssertTrue(error is CancellationError) }
        print("T08 | 核验取消后响应迟到 | 无有效绑定能力，无秘密日志")
    }

    private func verifier(_ transport: IdentityTransportStub,
                          gate: IdentityNetworkGate = .init(.allowed(score: 57))) -> CodexIdentityVerifier {
        let instant = instant
        return CodexIdentityVerifier(transport: transport, checkNetwork: { await gate.check() }, now: { instant })
    }

    private func assertFailure(_ tokens: CodexTokenResponse, transport: IdentityTransportStub,
                               gate: IdentityNetworkGate = .init(.allowed(score: 57)),
                               expected: CodexLoginError = .failed,
                               file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await verifier(transport, gate: gate).verify(tokens); XCTFail("不能核验为成功", file: file, line: line) }
        catch { XCTAssertEqual(error as? CodexLoginError, expected, file: file, line: line) }
    }

    private func response(id: String, access: String) -> CodexTokenResponse {
        CodexTokenResponse(accessToken: access, refreshToken: "synthetic-refresh", idToken: id,
                           obtainedAt: instant, expiresAt: instant.addingTimeInterval(3600))
    }

    private func tokens(_ signer: SyntheticJWTSigner, id: [String: Any]? = nil,
                        access: [String: Any]? = nil) throws -> CodexTokenResponse {
        response(id: try signer.sign(id ?? idClaims()), access: try signer.sign(access ?? accessClaims()))
    }

    private func idClaims() -> [String: Any] {
        ["iss": CodexIdentityVerifier.issuer, "sub": "subject-synthetic", "aud": CodexDeviceAuthorization.clientID,
         "iat": 1_790_000_000, "exp": 1_790_003_600, "email": "synthetic@example.invalid", "email_verified": true,
         "https://api.openai.com/auth": ["chatgpt_account_id": "account-synthetic", "chatgpt_user_id": "user-synthetic", "chatgpt_plan_type": "plus"]]
    }

    private func accessClaims() -> [String: Any] {
        var value = idClaims()
        value["aud"] = ["https://api.openai.com/v1"]
        value["client_id"] = CodexDeviceAuthorization.clientID
        return value
    }
}

private actor IdentityNetworkGate {
    let result: NetworkScoreResult
    private(set) var count = 0
    init(_ result: NetworkScoreResult) { self.result = result }
    func check() -> NetworkScoreResult { count += 1; return result }
}

private actor IdentityTransportStub: CodexDeviceAuthorizationTransport {
    let jwks: Data
    let usage: Data
    let usageStatus: Int
    let usageURL: URL
    let holdUsage: Bool
    private(set) var requests: [URLRequest] = []
    private var usageStarted = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var usageWaiter: CheckedContinuation<Void, Never>?

    init(jwks: Data, usage: Data = Data("{\"account_id\":\"account-synthetic\",\"user_id\":\"user-synthetic\",\"rate_limit\":{\"primary_window\":{\"used_percent\":22}}}".utf8),
         usageStatus: Int = 200, usageURL: URL = CodexIdentityVerifier.usageURL, holdUsage: Bool = false) {
        self.jwks = jwks; self.usage = usage; self.usageStatus = usageStatus; self.usageURL = usageURL
        self.holdUsage = holdUsage
    }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let isKeys = request.url == CodexIdentityVerifier.jwksURL
        if !isKeys && holdUsage {
            usageStarted = true
            startWaiter?.resume(); startWaiter = nil
            await withCheckedContinuation { usageWaiter = $0 }
        }
        return (isKeys ? jwks : usage,
                HTTPURLResponse(url: isKeys ? CodexIdentityVerifier.jwksURL : usageURL,
                                statusCode: isKeys ? 200 : usageStatus, httpVersion: nil,
                                headerFields: ["Content-Type": "application/json"])!)
    }
    func waitForUsage() async {
        if usageStarted { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func releaseUsage() { usageWaiter?.resume(); usageWaiter = nil }
}

/// Ephemeral RSA keys generated entirely in memory; no real accounts or Keychain.
private struct SyntheticJWTSigner {
    let key: SecKey
    let jwk: [String: String]
    let jwks: Data

    init() throws {
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048]
        let key = try XCTUnwrap(SecKeyCreateRandomKey(attributes as CFDictionary, nil))
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(key))
        let encoded = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, nil)) as Data
        var cursor = 0
        let sequence = try readDER(encoded, cursor: &cursor, expected: 0x30)
        cursor = 0
        var modulus = try readDER(sequence, cursor: &cursor, expected: 0x02)
        while modulus.first == 0 { modulus.removeFirst() }
        var exponent = try readDER(sequence, cursor: &cursor, expected: 0x02)
        while exponent.first == 0 { exponent.removeFirst() }
        let jwk = ["kty": "RSA", "kid": "synthetic-key", "use": "sig", "alg": "RS256",
                   "n": encodedBase64(modulus), "e": encodedBase64(exponent)]
        self.key = key; self.jwk = jwk
        self.jwks = try JSONSerialization.data(withJSONObject: ["keys": [jwk]])
    }

    func sign(_ claims: [String: Any], header: [String: String] = ["alg": "RS256", "kid": "synthetic-key"]) throws -> String {
        let unsigned = try "\(encodedJSON(header)).\(encodedJSON(claims))"
        let signature = try XCTUnwrap(SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256,
                                                          Data(unsigned.utf8) as CFData, nil)) as Data
        return "\(unsigned).\(encodedBase64(signature))"
    }
}

private func encodedJSON(_ object: Any) throws -> String { encodedBase64(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) }
private func encodedBase64(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

private func readDER(_ data: Data, cursor: inout Int, expected: UInt8) throws -> Data {
    enum InvalidDER: Error { case malformed }
    let bytes = Array(data)
    guard cursor + 2 <= bytes.count, bytes[cursor] == expected else { throw InvalidDER.malformed }
    cursor += 1
    let first = bytes[cursor]; cursor += 1
    var length = Int(first)
    if first & 0x80 != 0 {
        let count = Int(first & 0x7f)
        guard count > 0, count <= 4, cursor + count <= bytes.count else { throw InvalidDER.malformed }
        length = 0
        for _ in 0..<count { length = (length << 8) | Int(bytes[cursor]); cursor += 1 }
    }
    guard cursor + length <= bytes.count else { throw InvalidDER.malformed }
    defer { cursor += length }
    return Data(bytes[cursor..<(cursor + length)])
}
