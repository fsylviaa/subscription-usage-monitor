import Foundation
import Network

/// Internal results only. Connection/refresh features map these to their brief user messages.
enum NetworkScoreResult: Equatable, Sendable {
    case allowed(score: Double)
    case blocked(score: Double)
    case unavailable(NetworkScoreFailure)
    case cancelled
}

enum NetworkScoreFailure: Error, Equatable, Sendable {
    case timeout
    case transport
    case invalidResponse
    case invalidExitAddress
    case invalidScore
}

protocol NetworkScoreTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// A fresh check of the source specified by NET-01. No score or exit address is persisted.
/// This measures the Claude destination's exit, as the source page does; it does not
/// establish that VPN rules route every other destination through the same exit.
struct NetworkScoreChecker: Sendable {
    private let transport: any NetworkScoreTransport

    init() {
        self.init(transport: URLSessionNetworkScoreTransport())
    }

    init(transport: any NetworkScoreTransport) {
        self.transport = transport
    }

    func check() async -> NetworkScoreResult {
        do {
            try Task.checkCancellation()
            let traceURL = URL(string: "https://claude.ai/cdn-cgi/trace")!
            let trace = try await fetch(traceURL, timeout: 8, freshTrace: true)
            let exitAddress = try Self.exitAddress(from: trace)

            try Task.checkCancellation()
            let scoreURL = URL(string: "https://ip.net.coffee/api/iprisk/")!
                .appendingPathComponent(exitAddress)
            let data = try await fetch(scoreURL, timeout: 10, freshTrace: false)
            let score = try Self.score(from: data)
            try Task.checkCancellation()
            return score > 50 ? .allowed(score: score) : .blocked(score: score)
        } catch {
            // A transport may ignore cancellation and deliver a late success or error.
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                return .cancelled
            }
            if let failure = error as? NetworkScoreFailure {
                return .unavailable(failure)
            }
            if (error as? URLError)?.code == .timedOut {
                return .unavailable(.timeout)
            }
            return .unavailable(.transport)
        }
    }

    /// Callers cancel the enclosing Task when the user exits. Every invocation checks
    /// afresh; a past allowed result must never be reused as permission for another action.
    /// Operation errors propagate separately: a passing score is not a successful login/query.
    func checkThenPerform(
        _ operation: @Sendable () async throws -> Void
    ) async throws -> NetworkScoreResult {
        let result = await check()
        guard !Task.isCancelled else { return .cancelled }
        if case .allowed = result {
            try await operation()
        }
        return result
    }

    private func fetch(_ url: URL, timeout: TimeInterval, freshTrace: Bool) async throws -> Data {
        try Task.checkCancellation()
        // Match the source page: trace is fresh; risk uses the source's server-side
        // score cache. The session has no local URLCache in either case. Forcing
        // remote revalidation here timed out on device while the page's policy worked.
        let policy: URLRequest.CachePolicy = freshTrace
            ? .reloadIgnoringLocalAndRemoteCacheData : .useProtocolCachePolicy
        var request = URLRequest(url: url, cachePolicy: policy,
                                 timeoutInterval: timeout)
        if freshTrace {
            request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        }
        let (data, response) = try await transport.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200, http.url == url, !data.isEmpty,
              http.mimeType?.lowercased().contains("html") != true else {
            throw NetworkScoreFailure.invalidResponse
        }
        return data
    }

    private static func exitAddress(from data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw NetworkScoreFailure.invalidExitAddress
        }
        let addresses = text.split(whereSeparator: \.isNewline)
            .filter { $0.hasPrefix("ip=") }
            .map { String($0.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
        guard addresses.count == 1, let address = addresses.first,
              IPv4Address(address) != nil || IPv6Address(address) != nil else {
            throw NetworkScoreFailure.invalidExitAddress
        }
        return address
    }

    private static func score(from data: Data) throws -> Double {
        struct Payload: Decodable {
            let trust_score: Double
            let countryCode: String?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.trust_score.isFinite, (0...100).contains(payload.trust_score) else {
            throw NetworkScoreFailure.invalidScore
        }
        // Source: /claude/claude-page.js?v=20260916a, render(). NET-05 is stricter
        // than the page: a missing/invalid raw score stays unknown, even in these regions.
        let restrictedRegions: Set<String> = ["CN", "HK", "MO", "RU", "KP", "IR", "SY", "CU", "BY", "VE"]
        if let country = payload.countryCode, restrictedRegions.contains(country.uppercased()) {
            return 0
        }
        return payload.trust_score
    }
}

/// Isolated from browser/login cookies, credentials and disk caches. URLSession's async
/// request is cancelled with its parent task; redirecting to a different source is refused.
private final class URLSessionNetworkScoreTransport: NSObject, NetworkScoreTransport,
    URLSessionTaskDelegate, @unchecked Sendable {
    private let session: URLSession

    override init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 18
        session = URLSession(configuration: configuration)
        super.init()
    }

    deinit {
        session.invalidateAndCancel()
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request, delegate: self)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
