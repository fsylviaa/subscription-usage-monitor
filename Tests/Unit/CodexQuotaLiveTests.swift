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
        if account.quotaState == .notFetched || account.subscription == nil {
            let flow = CodexConnectionFlow(transactions: CodexLoginTransactionStore(vault: vault),
                bindings: CodexAccountBindingStore(accountStore: store, vault: vault),
                pending: CodexPendingLoginStore(vault: vault), quotaUpdater: updater)
            await flow.loadAccounts()
            await flow.waitForInitialQuota()
            guard let fetched = flow.accounts.first, fetched.subscription != nil, flow.quotaFailure == nil,
                  fetched.quotaState == .available || fetched.quotaState == .notApplicable else {
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
        let subscription = try XCTUnwrap(updated.subscription)
        let captured = await recorder.captured
        guard captured.count == 1, let response = captured.first,
              let body = try JSONSerialization.jsonObject(with: response) as? [String: Any],
              let rate = body["rate_limit"] as? [String: Any] else {
            XCTFail("未捕获同次真实平台主窗口，不能用样例证明一致。")
            return
        }
        let identityMatches = (body["account_id"] as? String ?? body["accountId"] as? String) == account.scope.remoteAccountID
        XCTAssertTrue(identityMatches, "同次平台响应对应已验证作用域")
        XCTAssertEqual(subscription.planType, body["plan_type"] as? String)
        XCTAssertTrue(subscription.observedAt >= startedAt && subscription.observedAt <= Date())
        print("T12 | 真实套餐 | 平台原始名称=\(subscription.planType)；显示Codex · \(subscription.planType)")
        if let quota = updated.quotaSnapshot {
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
        } else {
            XCTAssertEqual(updated.quotaState, .notApplicable)
            XCTAssertEqual(subscription.planType.lowercased(), "free")
            let windows = [rate["primary_window"], rate["secondary_window"]].compactMap { $0 as? [String: Any] }
            XCTAssertFalse(windows.contains { [18000, 604800].contains(($0["limit_window_seconds"] as? NSNumber)?.intValue ?? 0) })
            print("T12 | 真实Free无适用额度 | 套餐识别成功；不创建周/5小时快照，不报失败")
        }
        let reloaded = try await AccountStore.applicationStore().load()
        XCTAssertTrue(reloaded == [updated], "重新实例化后数值、时间与本次作用域一致")
        let credentialAfter = try await vault.load(for: .credential(account.credentialRef))
        XCTAssertTrue(credentialBefore == credentialAfter, "查询没有消费或替换原登录授权")
        XCTAssertTrue(updated.id == account.id && updated.scope == account.scope
            && updated.remoteUserID == account.remoteUserID && updated.verifiedEmail == account.verifiedEmail)
        print("T12 | 真实保存重读 | 成功时间\(Self.time(subscription.observedAt))；身份、套餐、额度适用性与保存时间一致；授权未改")
    }

    func testT13RealSavedLoginRetriesAfterControlledFirstFailure() async throws {
        guard ProcessInfo.processInfo.environment["T13_LIVE_RETRY"] == "1" else {
            throw XCTSkip("T13真实重试需要显式启用；默认不读取正式账户或联网。")
        }
        let formalStore = try AccountStore.applicationStore()
        let before = try await formalStore.load()
        guard before.count == 1, var account = before.first else {
            XCTFail("需要本App已验证的真实账户。")
            return
        }
        let vault = CredentialVault.applicationVault()
        let credentialBefore = try await vault.load(for: .credential(account.credentialRef))
        XCTAssertNotNil(credentialBefore)
        // Copy metadata only into isolated storage; the formal binding/snapshot
        // and Keychain credential are never rewritten for a failure scenario.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T13-live-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("accounts.json")
        let store = AccountStore(fileURL: url)
        account.quotaState = .notFetched
        account.quotaSnapshot = nil
        try await store.append(account)
        let gate = T13LiveRetryGate()
        let transport = T13LiveRetryTransport()
        let updater = CodexQuotaService(store: store,
            loadCredential: { try await vault.load(for: .credential($0)) }, transport: transport,
            checkNetwork: { await gate.check() })
        let flow = CodexConnectionFlow(transactions: T13ReadOnlyTransactions(),
            bindings: CodexAccountBindingStore(accountStore: store, vault: vault), quotaUpdater: updater)
        await flow.loadAccounts()
        await flow.waitForInitialQuota()
        XCTAssertEqual(flow.quotaFailure, "获取失败")
        XCTAssertTrue(flow.accounts == [account], "隔离副本首次受控失败保留身份和已知套餐")
        let initialRequests = await transport.count
        XCTAssertEqual(initialRequests, 0)
        let retryStarted = Date()
        flow.retryInitialQuota(for: account.id)
        await flow.waitForInitialQuota()
        guard flow.quotaFailure == nil, let updated = flow.accounts.first,
              let subscription = updated.subscription else {
            XCTFail("T13真实重试尚未成功：\(flow.quotaFailure ?? "获取失败")")
            return
        }
        let capturedBody = await transport.bodyValue()
        let raw = try XCTUnwrap(capturedBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        XCTAssertTrue(subscription.planType == object["plan_type"] as? String)
        XCTAssertTrue(subscription.observedAt >= retryStarted && subscription.observedAt <= Date())
        XCTAssertTrue(updated.id == account.id && updated.scope == account.scope && updated.credentialRef == account.credentialRef)
        if updated.quotaState == .notApplicable {
            XCTAssertTrue(subscription.planType.lowercased() == "free")
            XCTAssertNil(updated.quotaSnapshot)
            print("T13 | 真实重试 | 平台返回free，无适用周/5小时；正常清除失败，不造额度及成功时间")
        } else {
            XCTAssertEqual(updated.quotaState, .available)
            let snapshot = try XCTUnwrap(updated.quotaSnapshot)
            XCTAssertTrue(snapshot == (try CodexUsageParser().parse(raw, for: account, observedAt: subscription.observedAt)))
            print("T13 | 真实重试 | 有适用额度，同次平台响应与保存快照一致")
        }
        let reloaded = try await AccountStore(fileURL: url).load()
        XCTAssertTrue(reloaded == [updated])
        let formalAfter = try await formalStore.load()
        let credentialAfter = try await vault.load(for: .credential(account.credentialRef))
        XCTAssertTrue(formalAfter == before && credentialBefore == credentialAfter, "原账户、授权和数据保持不变")
        let checks = await gate.count
        let requests = await transport.count
        XCTAssertEqual(checks, 2)
        XCTAssertEqual(requests, 1)
        print("T13 | 受控失败→真实网络重试 | 2次检查、1次真实查询；无重登/重复账户，隔离保存重读一致，原数据不变")
    }

    func testT15RealSavedAccountRestoresWithNetworkUnavailable() async throws {
        guard ProcessInfo.processInfo.environment["T15_LIVE_RESTORE"] == "1" else {
            throw XCTSkip("T15真实缓存检查需显式启用；不修改真实账户或授权。")
        }
        let store = try AccountStore.applicationStore()
        let before = try await store.load()
        guard !before.isEmpty, before.allSatisfy({ $0.subscription != nil && $0.quotaState != .notFetched }) else {
            XCTFail("需要本App已保存的真实成功资料。")
            return
        }
        let calls = T15ReadProbe()
        let updater = CodexQuotaService(store: store, loadCredential: { _ in
            await calls.credentialRead()
            throw CodexLoginError.failed
        }, checkNetwork: {
            await calls.networkCheck()
            return .unavailable(.transport)
        })
        for _ in 0..<2 {
            let flow = CodexConnectionFlow(transactions: T13ReadOnlyTransactions(),
                bindings: CodexAccountBindingStore(accountStore: try .applicationStore(), vault: .applicationVault()),
                quotaUpdater: updater)
            await flow.loadAccounts()
            await flow.waitForInitialQuota()
            XCTAssertTrue(flow.accounts == before, "真实身份、套餐、适用性、快照及原时间应完全相同")
            XCTAssertFalse(flow.loadingAccounts)
            XCTAssertFalse(flow.accountLoadFailed)
            XCTAssertFalse(flow.isPresented)
            XCTAssertNil(flow.quotaFailure)
        }
        let counts = await calls.counts()
        XCTAssertEqual(counts.0, 0)
        XCTAssertEqual(counts.1, 0)
        let after = try await store.load()
        XCTAssertTrue(after == before)
        print("T15 | 真实手机资料+受控断网 | 两次新实例恢复完全一致；网络检查0、正式授权读取0、查询0；无写回/新成功时间")
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

private actor T13LiveRetryGate {
    private(set) var count = 0
    func check() async -> NetworkScoreResult {
        count += 1
        if count == 1 { return .unavailable(.transport) }
        let result = await NetworkScoreChecker().check()
        switch result {
        case let .allowed(score): print("T13 | 真实查询前网络 | 允许，分数\(score)")
        case let .blocked(score): print("T13 | 真实查询前网络 | 阻止，分数\(score)")
        case .unavailable: print("T13 | 真实查询前网络 | 未取得有效评分")
        case .cancelled: print("T13 | 真实查询前网络 | 取消")
        }
        return result
    }
}
private actor T13LiveRetryTransport: CodexDeviceAuthorizationTransport {
    private(set) var count = 0
    private var body: Data?
    func bodyValue() -> Data? { body }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        count += 1
        let result = try await URLSessionCodexDeviceAuthorizationTransport().data(for: request)
        body = result.0
        print("T13 | 真实额度请求 | HTTP \((result.1 as? HTTPURLResponse)?.statusCode ?? 0)")
        return result
    }
}
private actor T13ReadOnlyTransactions: CodexLoginTransactionStoring {
    func save(_ authorization: CodexDeviceAuthorization) { }
    func remove(transactionID: UUID) { }
}

private actor T15ReadProbe {
    private var checks = 0
    private var credentials = 0
    func networkCheck() { checks += 1 }
    func credentialRead() { credentials += 1 }
    func counts() -> (Int, Int) { (checks, credentials) }
}
