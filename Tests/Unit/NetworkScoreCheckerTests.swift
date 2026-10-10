import Foundation
import XCTest
@testable import SubscriptionUsage

@MainActor
final class NetworkScoreCheckerTests: XCTestCase {
    func test49And50BlockFollowingOperation() async throws {
        for score in [49, 50] {
            let transport = ScoreTransportStub(steps: [.trace(), .risk("{\"trust_score\":\(score)}")])
            let calls = OperationCounter()
            let result = try await NetworkScoreChecker(transport: transport).checkThenPerform {
                await calls.increment()
            }

            XCTAssertEqual(result, .blocked(score: Double(score)))
            let count = await calls.value
            XCTAssertEqual(count, 0, "未超过 50 分时不启动后续操作")
            print("T06 | 固定评分 \(score) | 阻止；后续操作 0 次")
        }
    }

    func test51AllowsFollowingOperationExactlyOnce() async throws {
        let transport = ScoreTransportStub(steps: [.trace(), .risk("{\"trust_score\":51}")])
        let calls = OperationCounter()
        let result = try await NetworkScoreChecker(transport: transport).checkThenPerform {
            await calls.increment()
        }

        XCTAssertEqual(result, .allowed(score: 51))
        let count = await calls.value
        XCTAssertEqual(count, 1)
        print("T06 | 固定评分 51 | 允许；后续操作 1 次")
    }

    func testValidScoresPreserveZeroFractionAndUpperBound() async {
        for (score, expected) in [
            ("0", NetworkScoreResult.blocked(score: 0)),
            ("50.01", .allowed(score: 50.01)),
            ("100", .allowed(score: 100))
        ] {
            let result = await checkRisk("{\"trust_score\":\(score)}")
            XCTAssertEqual(result, expected)
        }
    }

    func testMissingInvalidTypeOutOfRangeAndMalformedScoresRemainUnknown() async throws {
        let invalidBodies = [
            "{}", "{\"trust_score\":null}", "{\"trust_score\":\"51\"}",
            "{\"trust_score\":true}", "{\"trust_score\":false}",
            "{\"trust_score\":-1}", "{\"trust_score\":100.1}",
            "{\"trust_score\":1e999}", "{\"trust_score\":NaN}",
            "{\"trust_score\":[]}", "{\"trust_score\":{}}", "[]", "not-json"
        ]
        for body in invalidBodies {
            let transport = ScoreTransportStub(steps: [.trace(), .risk(body)])
            let calls = OperationCounter()
            let result = try await NetworkScoreChecker(transport: transport).checkThenPerform {
                await calls.increment()
            }
            XCTAssertEqual(result, .unavailable(.invalidScore))
            let count = await calls.value
            XCTAssertEqual(count, 0)
        }
        print("T06 | 缺失、类型错误、越界及无效评分 | 保持未知；全部阻止")
    }

    func testSpecifiedRestrictedCountriesMapValidScoreToZero() async {
        for country in ["CN", "HK", "MO", "RU", "KP", "IR", "SY", "CU", "BY", "VE"] {
            let result = await checkRisk("{\"trust_score\":99,\"countryCode\":\"\(country)\"}")
            XCTAssertEqual(result, .blocked(score: 0))
        }
        let unrestricted = await checkRisk("{\"trust_score\":99,\"countryCode\":\"US\"}")
        XCTAssertEqual(unrestricted, .allowed(score: 99))
    }

    func testRestrictedCountryWithoutValidScoreDoesNotInventZero() async {
        for body in [
            "{\"countryCode\":\"CN\"}",
            "{\"countryCode\":\"CN\",\"trust_score\":null}",
            "{\"countryCode\":\"CN\",\"trust_score\":\"99\"}",
            "{\"countryCode\":\"CN\",\"trust_score\":101}"
        ] {
            let result = await checkRisk(body)
            XCTAssertEqual(result, .unavailable(.invalidScore))
        }
    }

    func testRequestsUseSpecifiedSourcesCurrentExitAddressAndNoCache() async {
        let transport = ScoreTransportStub(steps: [.trace(), .risk("{\"trust_score\":51}")])
        let result = await NetworkScoreChecker(transport: transport).check()
        XCTAssertEqual(result, .allowed(score: 51))

        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        guard requests.count == 2 else { return }
        XCTAssertEqual(requests[0].url?.absoluteString, "https://claude.ai/cdn-cgi/trace")
        XCTAssertEqual(requests[1].url?.absoluteString, "https://ip.net.coffee/api/iprisk/192.0.2.1")
        XCTAssertEqual(requests[0].timeoutInterval, 8)
        XCTAssertEqual(requests[1].timeoutInterval, 10)
        XCTAssertEqual(requests[0].cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Cache-Control"), "no-cache, no-store")
        // The page uses its service's cached score; every check still fetches a new
        // trace and the production session has no local URLCache.
        XCTAssertEqual(requests[1].cachePolicy, .useProtocolCachePolicy)
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Cache-Control"))
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Pragma"))
        for request in requests {
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        }
    }

    func testIPv6ExitAddressIsAcceptedAndUsedForScoring() async {
        let transport = ScoreTransportStub(steps: [
            .trace("ip=2001:db8::1\nloc=US\n"), .risk("{\"trust_score\":51}")
        ])
        let result = await NetworkScoreChecker(transport: transport).check()
        XCTAssertEqual(result, .allowed(score: 51))
        let requests = await transport.requests
        XCTAssertEqual(requests.last?.url?.path, "/api/iprisk/2001:db8::1")
    }

    func testMissingMalformedAndAmbiguousExitAddressStopsBeforeScoreRequest() async {
        for body in [
            "loc=US\n", "ip=\n", "ip=not-an-address\n", "ip=999.1.2.3\n",
            "ip=192.0.2.1/other\n", "ip=192.0.2.1\nip=192.0.2.2\n"
        ] {
            let transport = ScoreTransportStub(steps: [.trace(body)])
            let result = await NetworkScoreChecker(transport: transport).check()
            XCTAssertEqual(result, .unavailable(.invalidExitAddress))
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testNon200ResponsesAtEitherStageAreUnavailable() async {
        for status in [204, 301, 403, 429, 500] {
            for steps in [
                [ScoreStubStep.response(body: "ip=192.0.2.1\n", status: status)],
                [.trace(), .response(body: "{\"trust_score\":99}", status: status)]
            ] {
                let result = await NetworkScoreChecker(transport: ScoreTransportStub(steps: steps)).check()
                XCTAssertEqual(result, .unavailable(.invalidResponse))
            }
        }
    }

    func testHTMLChallengeAtEitherStageCannotBecomeValidResult() async {
        for steps in [
            [ScoreStubStep.response(body: "<html>ip=192.0.2.1</html>", contentType: "text/html")],
            [.trace(), .response(body: "{\"trust_score\":99}", contentType: "text/html")]
        ] {
            let result = await NetworkScoreChecker(transport: ScoreTransportStub(steps: steps)).check()
            XCTAssertEqual(result, .unavailable(.invalidResponse))
        }
    }

    func testRedirectedResponseAtEitherStageCannotSubstituteAnotherSource() async {
        let changedURL = URL(string: "https://example.invalid/redirected")!
        for steps in [
            [ScoreStubStep.response(body: "ip=192.0.2.1\n", responseURL: changedURL)],
            [.trace(), .response(body: "{\"trust_score\":99}", responseURL: changedURL)]
        ] {
            let result = await NetworkScoreChecker(transport: ScoreTransportStub(steps: steps)).check()
            XCTAssertEqual(result, .unavailable(.invalidResponse))
        }
    }

    func testNonHTTPResponseCannotBecomeValidScore() async {
        let transport = ScoreTransportStub(steps: [.trace(), .nonHTTP("{\"trust_score\":99}")])
        let result = await NetworkScoreChecker(transport: transport).check()
        XCTAssertEqual(result, .unavailable(.invalidResponse))
    }

    func testTimeoutAtEitherStageIsUnknownAndBlocksFollowingOperation() async throws {
        for steps in [
            [ScoreStubStep.failure(.timedOut)], [.trace(), .failure(.timedOut)]
        ] {
            let calls = OperationCounter()
            let result = try await NetworkScoreChecker(transport: ScoreTransportStub(steps: steps))
                .checkThenPerform { await calls.increment() }
            XCTAssertEqual(result, .unavailable(.timeout))
            let count = await calls.value
            XCTAssertEqual(count, 0)
        }
        print("T06 | 两阶段分别超时 | 保持未知；后续操作 0 次")
    }

    func testDisconnectedTransportIsUnknownRatherThanLowScore() async {
        let transport = ScoreTransportStub(steps: [.failure(.notConnectedToInternet)])
        let result = await NetworkScoreChecker(transport: transport).check()
        XCTAssertEqual(result, .unavailable(.transport))
        XCTAssertNotEqual(result, .blocked(score: 0))
    }

    func testTransportCancellationIsNotReportedAsScoreFailure() async {
        let transport = ScoreTransportStub(steps: [.failure(.cancelled)])
        let result = await NetworkScoreChecker(transport: transport).check()
        XCTAssertEqual(result, .cancelled)
    }

    func testAlreadyCancelledCheckMakesNoRequestOrFollowingOperation() async throws {
        let start = ScoreTestGate()
        let transport = ScoreTransportStub(steps: [.trace(), .risk("{\"trust_score\":51}")])
        let calls = OperationCounter()
        let checker = NetworkScoreChecker(transport: transport)
        let task = Task {
            await start.wait()
            return try await checker.checkThenPerform { await calls.increment() }
        }
        task.cancel()
        await start.open()

        let result = try await task.value
        let requests = await transport.requests
        let count = await calls.value
        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(requests.count, 0)
        XCTAssertEqual(count, 0)
    }

    func testCancellationDuringExitRequestStopsBeforeScoring() async throws {
        let transport = SuspendedScoreTransport(suspendRequest: 1)
        let calls = OperationCounter()
        let checker = NetworkScoreChecker(transport: transport)
        let task = Task {
            try await checker.checkThenPerform { await calls.increment() }
        }
        await transport.suspended.wait()
        task.cancel()
        await transport.release.open()

        let result = try await task.value
        let count = await calls.value
        let requests = await transport.requestCount
        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(count, 0)
    }

    func testLate51AfterCancellationCannotStartFollowingOperation() async throws {
        let transport = SuspendedScoreTransport(suspendRequest: 2)
        let calls = OperationCounter()
        let checker = NetworkScoreChecker(transport: transport)
        let task = Task {
            try await checker.checkThenPerform { await calls.increment() }
        }
        await transport.suspended.wait()
        task.cancel()
        // The transport deliberately ignores cancellation and still returns 51.
        await transport.release.open()

        let result = try await task.value
        let count = await calls.value
        let requests = await transport.requestCount
        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(count, 0)
        print("T06 | 取消后迟到 51 分 | 保持取消；后续操作 0 次")
    }

    func testEveryRetryFetchesFreshExitAndScoreInsteadOfReusingAllowedResult() async throws {
        let transport = ScoreTransportStub(steps: [
            .trace(), .risk("{\"trust_score\":51}"),
            .trace("ip=192.0.2.2\n"), .risk("{\"trust_score\":49}")
        ])
        let checker = NetworkScoreChecker(transport: transport)
        let calls = OperationCounter()
        let first = try await checker.checkThenPerform { await calls.increment() }
        let second = try await checker.checkThenPerform { await calls.increment() }

        XCTAssertEqual(first, .allowed(score: 51))
        XCTAssertEqual(second, .blocked(score: 49))
        let requests = await transport.requests
        let count = await calls.value
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests.last?.url?.path, "/api/iprisk/192.0.2.2")
        XCTAssertEqual(count, 1)
    }

    func testFollowingOperationFailureIsPropagatedWithoutRetryingOperation() async {
        let calls = OperationCounter()
        let checker = NetworkScoreChecker(transport: ScoreTransportStub(steps: [
            .trace(), .risk("{\"trust_score\":51}")
        ]))
        do {
            _ = try await checker.checkThenPerform {
                await calls.increment()
                throw ScoreTestFailure.operation
            }
            XCTFail("后续操作的错误应继续交给调用方")
        } catch {
            XCTAssertTrue(error is ScoreTestFailure)
        }
        let count = await calls.value
        XCTAssertEqual(count, 1)
    }

    private func checkRisk(_ body: String) async -> NetworkScoreResult {
        await NetworkScoreChecker(transport: ScoreTransportStub(steps: [.trace(), .risk(body)])).check()
    }
}

private enum ScoreTestFailure: Error {
    case unexpectedRequest
    case operation
}

private enum ScoreStubStep: Sendable {
    case response(
        body: String,
        status: Int = 200,
        contentType: String = "text/plain",
        responseURL: URL? = nil
    )
    case failure(URLError.Code)
    case nonHTTP(String)

    static func trace(_ body: String = "fl=fixture\nip=192.0.2.1\nloc=US\n") -> Self {
        .response(body: body)
    }

    static func risk(_ body: String) -> Self {
        .response(body: body, contentType: "application/json")
    }

    func result(for request: URLRequest) throws -> (Data, URLResponse) {
        guard let url = request.url else { throw ScoreTestFailure.unexpectedRequest }
        switch self {
        case let .response(body, status, contentType, responseURL):
            let response = HTTPURLResponse(
                url: responseURL ?? url, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": contentType]
            )!
            return (Data(body.utf8), response)
        case let .failure(code):
            throw URLError(code)
        case let .nonHTTP(body):
            return (Data(body.utf8), URLResponse(url: url, mimeType: nil, expectedContentLength: 0,
                                               textEncodingName: nil))
        }
    }
}

private actor ScoreTransportStub: NetworkScoreTransport {
    private var steps: [ScoreStubStep]
    private(set) var requests: [URLRequest] = []

    init(steps: [ScoreStubStep]) { self.steps = steps }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !steps.isEmpty else { throw ScoreTestFailure.unexpectedRequest }
        return try steps.removeFirst().result(for: request)
    }
}

private actor OperationCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

/// A deterministic one-shot gate: tests control completion without wall-clock sleeps.
private actor ScoreTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private actor SuspendedScoreTransport: NetworkScoreTransport {
    let suspended = ScoreTestGate()
    let release = ScoreTestGate()
    private let suspendRequest: Int
    private(set) var requestCount = 0

    init(suspendRequest: Int) { self.suspendRequest = suspendRequest }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestCount += 1
        let current = requestCount
        if current == suspendRequest {
            await suspended.open()
            await release.wait()
        }
        let step: ScoreStubStep = current == 1 ? .trace() : .risk("{\"trust_score\":51}")
        return try step.result(for: request)
    }
}
