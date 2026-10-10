import Foundation
import XCTest
@testable import SubscriptionUsage

/// Reads only this iPhone App's own saved login. No desktop authorization,
/// refresh-token exchange, new login or hidden bypass of the network gate.
@MainActor
final class CodexQuotaLiveTests: XCTestCase {
    func testExistingRealLoginAutomaticallyFetchesAndPersistsFirstQuota() async throws {
        guard ProcessInfo.processInfo.environment["T12_LIVE_QUERY"] == "1" else {
            throw XCTSkip("真实额度查询需要显式启用；默认隔离检查不联网。")
        }
        let store = try AccountStore.applicationStore()
        let before = try await store.load()
        guard before.count == 1, let account = before.first else {
            XCTFail("需要先有本App已验证的真实登录。")
            return
        }
        let vault = CredentialVault.applicationVault()
        let credentialBefore = try await vault.load(for: .credential(account.credentialRef))
        let recorder = LiveQuotaRecorder()
        let updater = CodexQuotaService(store: store,
            loadCredential: { try await vault.load(for: .credential($0)) }, transport: recorder,
            checkNetwork: {
                let result = await NetworkScoreChecker(transport: LiveScoreRecorder()).check()
                switch result {
                case let .allowed(score): print("T12 | 真实网络门控 | 允许，分数\(score)")
                case let .blocked(score): print("T12 | 真实网络门控 | 阻止，分数\(score)")
                case let .unavailable(failure): print("T12 | 真实网络门控 | 未取得有效评分；内部结果\(failure)")
                case .cancelled: print("T12 | 真实网络门控 | 已取消")
                }
                return result
            })
        let startedAt = Date()
        let updated: ConnectedAccount
        if account.quotaState == .notFetched {
            let flow = CodexConnectionFlow(transactions: CodexLoginTransactionStore(vault: vault),
                bindings: CodexAccountBindingStore(accountStore: store, vault: vault),
                pending: CodexPendingLoginStore(vault: vault), quotaUpdater: updater)
            await flow.loadAccounts()
            await flow.waitForInitialQuota()
            guard let fetched = flow.accounts.first, fetched.quotaState == .available else {
                XCTFail("真实自动查询尚未成功：\(flow.quotaFailure ?? "刷新失败")")
                return
            }
            updated = fetched
            print("T12 | 真实触发 | T08已验证登录的首次额度在加载账户后自动查询，无点击刷新或重新登录")
        } else {
            // A rerun may verify the result, but cannot pretend that an initial
            // automatic query happened again or overwrite that historical fact.
            updated = try await updater.update(account)
            print("T12 | 真实复核 | 已有成功快照，显式复核请求；不冒称再次首次自动查询")
        }
        guard let quota = updated.quotaSnapshot else { XCTFail("缺少成功快照"); return }
        let captured = await recorder.captured
        guard captured.count == 1, let response = captured.first,
              let body = try JSONSerialization.jsonObject(with: response) as? [String: Any],
              let rate = body["rate_limit"] as? [String: Any] else {
            XCTFail("未捕获同次真实平台主窗口，不能用样例证明一致。")
            return
        }
        let identityMatches = (body["account_id"] as? String ?? body["accountId"] as? String) == account.scope.remoteAccountID
        XCTAssertTrue(identityMatches, "同次平台响应对应已验证作用域")
        let rawWindows = [rate["primary_window"], rate["secondary_window"]].compactMap { $0 as? [String: Any] }
        for window in [quota.weekly, quota.fiveHours] {
            let raw = rawWindows.first { ($0["limit_window_seconds"] as? NSNumber)?.intValue == window.window.rawValue }
            let used = (raw?["used_percent"] as? NSNumber)?.doubleValue
            XCTAssertEqual(window.amount.remainingPercent, used.map { 100 - $0 })
            let reset = (raw?["reset_at"] as? NSNumber)?.doubleValue
            XCTAssertEqual(window.resetsAt?.timeIntervalSince1970, reset)
            let name = window.window == .weekly ? "周" : "5小时"
            let remaining = window.amount.remainingPercent.map { String($0) + "%" } ?? "未知"
            let resetText = window.resetsAt.map { Self.time($0) } ?? "未提供"
            print("T12 | 同次真实平台核对 | \(name)窗口\(window.window.rawValue)秒；剩余\(remaining)；预计重置\(resetText)；平台/解释/保存相同")
        }
        XCTAssertTrue(quota.hasKnownQuota)
        XCTAssertTrue(quota.observedAt >= startedAt && quota.observedAt <= Date())
        let reloaded = try await AccountStore.applicationStore().load()
        XCTAssertTrue(reloaded == [updated], "重新实例化后数值、时间与本次作用域一致")
        let credentialAfter = try await vault.load(for: .credential(account.credentialRef))
        XCTAssertTrue(credentialBefore == credentialAfter, "查询没有消费或替换原登录授权")
        XCTAssertTrue(updated.id == account.id && updated.scope == account.scope
            && updated.remoteUserID == account.remoteUserID && updated.verifiedEmail == account.verifiedEmail)
        print("T12 | 真实保存重读 | 成功时间\(Self.time(quota.observedAt))；身份、两窗口、原始重置时间与成功时间一致；授权未改")
    }

    private static func time(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return formatter.string(from: date)
    }
}

private actor LiveQuotaRecorder: CodexDeviceAuthorizationTransport {
    private let transport = URLSessionCodexDeviceAuthorizationTransport()
    private(set) var captured: [Data] = []
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = try await transport.data(for: request)
        print("T12 | 真实响应 | HTTP \((response.1 as? HTTPURLResponse)?.statusCode ?? 0)")
        if let object = try? JSONSerialization.jsonObject(with: response.0) as? [String: Any] {
            for key in ["rate_limit", "rate_limits", "additional_rate_limits", "plan_type"] {
                let kind = object[key].map { String(describing: type(of: $0)) } ?? "missing"
                print("T12 | 响应字段结构 | \(key):\(kind)")
            }
            if let rate = object["rate_limit"] as? [String: Any] {
                for name in ["primary_window", "secondary_window"] {
                    guard let window = rate[name] as? [String: Any] else {
                        print("T12 | 主窗口结构 | \(name):缺失/null")
                        continue
                    }
                    for key in ["limit_window_seconds", "used_percent", "reset_at"] {
                        let number = window[key] as? NSNumber
                        print("T12 | 主窗口数值 | \(name).\(key)=\(number?.stringValue ?? "缺失/null/非数值")")
                    }
                }
            }
        }
        captured.append(response.0) // Memory-only; no raw response, identity or token in logs.
        return response
    }
}

private struct LiveScoreRecorder: NetworkScoreTransport {
    private let transport = URLSessionNetworkScoreTransport()
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let name = request.url?.host == "claude.ai" ? "出口查询" : "指定评分"
        do {
            let response = try await transport.data(for: request)
            let http = response.1 as? HTTPURLResponse
            print("T12 | \(name) | HTTP \(http?.statusCode ?? 0)；HTML=\(http?.mimeType?.contains("html") ?? false)")
            return response
        } catch {
            print("T12 | \(name) | 请求失败；URL错误码\((error as? URLError)?.code.rawValue ?? 0)")
            throw error
        }
    }
}
