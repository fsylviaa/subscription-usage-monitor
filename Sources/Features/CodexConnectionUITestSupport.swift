#if DEBUG
import Foundation

/// Only explicit UI test launches can use these fixtures; no product menu or saved
/// preference enables them, and neither requests nor storage touch a real account.
@MainActor
enum CodexConnectionUITestSupport {
    static func makeFlow() -> CodexConnectionFlow {
        let arguments = ProcessInfo.processInfo.arguments
        guard let marker = arguments.firstIndex(of: "--t07-isolated-ui"),
              arguments.indices.contains(marker + 1) else { return CodexConnectionFlow() }
        let scenario = arguments[marker + 1]
        return CodexConnectionFlow(
            checkNetwork: {
                switch scenario {
                case "50": return .blocked(score: 50)
                case "unknown": return .unavailable(.transport)
                case "slow":
                    // Intentionally ignores cancellation to exercise stale-result guards.
                    await withCheckedContinuation { continuation in
                        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                            continuation.resume()
                        }
                    }
                    return .allowed(score: 51)
                default: return .allowed(score: 51)
                }
            },
            authorizer: FixtureAuthorizer(fails: scenario == "request-failure"),
            transactions: FixtureTransactions(),
            openURL: { $0 == CodexDeviceAuthorization.verificationURL }
        )
    }

    private struct FixtureAuthorizer: CodexDeviceAuthorizing {
        let fails: Bool
        func requestAuthorization() async throws -> CodexDeviceAuthorization {
            if fails { throw CodexDeviceAuthorizationError.requestFailed }
            return try CodexDeviceAuthorization(deviceAuthID: "isolated-ui-transaction",
                                                userCode: "TEST-CODE", pollInterval: 5,
                                                startedAt: Date())
        }
    }

    private actor FixtureTransactions: CodexLoginTransactionStoring {
        func save(_ authorization: CodexDeviceAuthorization) { }
        func remove(transactionID: UUID) { }
    }
}
#endif
