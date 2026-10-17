#if DEBUG
import SwiftUI

/// T105 launch-only probe for Grok Bot ("Sand") weekly usage. Reads the Cursor
/// session the App already saved; never writes accounts or credentials, never
/// logs tokens, and saves only a de-identified report.
struct GrokBotUsageProbeView: View {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("--t105-grok-probe") }

    @StateObject private var probe = GrokBotUsageProbe()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(probe.status).font(.headline)
                    Button(probe.running ? "正在查询…" : "重新验证") { Task { await probe.run() } }
                        .disabled(probe.running)
                }
                ForEach(probe.results) { result in
                    Section("Cursor 账户 \(result.index)") {
                        LabeledContent("邮箱", value: result.email)
                        LabeledContent("Grok Bot 剩余", value: result.remaining ?? "—")
                        LabeledContent("Grok Bot 已用", value: result.used ?? "—")
                        LabeledContent("下次重置", value: result.resetsAt ?? "—")
                        LabeledContent("有套餐内额度", value: result.hasIncluded ?? "—")
                        LabeledContent("仅试用", value: result.trialOnly ?? "—")
                        LabeledContent("来源", value: result.source)
                    }
                }
                Section("过程（不含凭据）") {
                    ForEach(Array(probe.steps.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("Grok Bot 额度验证")
        }
        .task { await probe.run() } // Read-only; the button repeats it.
    }
}

@MainActor
final class GrokBotUsageProbe: ObservableObject {
    struct Result: Identifiable {
        let index: Int
        var id: Int { index }
        var email = "—"
        var remaining: String?
        var used: String?
        var resetsAt: String?
        var hasIncluded: String?
        var trialOnly: String?
        var source = "—"
    }

    @Published var status = "正在用已保存的 Cursor 账户查询"
    @Published var running = false
    @Published var results: [Result] = []
    @Published var steps: [String] = []
    private var report: [String: String] = [:]
    private var startedAt = Date()

    func run() async {
        running = true; results = []; steps = []; report = [:]; startedAt = Date()
        status = "正在查询"
        defer { running = false; writeReport() }
        let accounts: [ConnectedAccount]
        do {
            accounts = try await AccountStore.applicationStore().load()
                .filter { $0.platform == .cursor && !$0.isDemo }
        } catch {
            finish("读取账户失败"); return
        }
        note("已保存 Cursor 账户 \(accounts.count) 个")
        guard !accounts.isEmpty else { finish("没有已保存的 Cursor 账户"); return }
        let vault = CredentialVault.applicationVault()
        var anySuccess = false
        for (offset, account) in accounts.enumerated() {
            let index = offset + 1
            var result = Result(index: index, email: account.verifiedEmail ?? "—")
            guard let payload = try? await vault.load(for: .credential(account.credentialRef)),
                  let credential = try? CursorCredential(payload: payload), let cookie = credential.cookie else {
                note("账户\(index)：读取本机授权失败"); results.append(result); continue
            }
            var response = await GrokBotProbeNetwork.cookieRequest(cookie: cookie)
            note("账户\(index)：cursor.com get-sand-usage-status（Cookie）→ \(response.status)")
            report["account\(index)_cookie_status"] = String(response.status)
            report["account\(index)_cookie_shape"] = response.shape
            result.source = "cursor.com（Cookie）"
            if response.status != 200 {
                let backup = await GrokBotProbeNetwork.bearerRequest(token: credential.accessToken)
                note("账户\(index)：api2 GetSandUsageStatus（Bearer）→ \(backup.status)")
                report["account\(index)_bearer_status"] = String(backup.status)
                report["account\(index)_bearer_shape"] = backup.shape
                if backup.status == 200 { response = backup; result.source = "api2.cursor.sh（Bearer）" }
            }
            report["account\(index)_flags"] = response.flags
            if let used = response.usagePercent {
                result.used = String(format: "%.2f%%", used)
                result.remaining = String(format: "%.2f%%", max(0, 100 - used))
            }
            result.resetsAt = response.nextReset?.formatted(date: .abbreviated, time: .shortened)
            result.hasIncluded = response.hasIncluded.map { $0 ? "是" : "否" }
            result.trialOnly = response.trialOnly.map { $0 ? "是" : "否" }
            if response.status == 200 && response.usagePercent != nil { anySuccess = true }
            results.append(result)
        }
        finish(anySuccess ? "完成：请与 Grok Bot App 核对" : "未取得 Grok Bot 额度")
    }

    private func finish(_ text: String) {
        status = text
        report["result"] = text
    }

    private func writeReport() {
        report["steps"] = steps.joined(separator: "\n")
        report["finished_at"] = ISO8601DateFormatter().string(from: Date())
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
           let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? data.write(to: dir.appendingPathComponent("t105-grok-probe-report.json"), options: .completeFileProtection)
        }
    }

    private func note(_ line: String) {
        steps.append("+\(Int(Date().timeIntervalSince(startedAt)))s \(line)")
    }
}

enum GrokBotProbeNetwork {
    struct Response: Sendable {
        var status = 0
        var shape = ""
        var flags = ""
        var usagePercent: Double?
        var nextReset: Date?
        var hasIncluded: Bool?
        var trialOnly: Bool?
    }

    static func cookieRequest(cookie: String) async -> Response {
        var request = URLRequest(url: URL(string: "https://cursor.com/api/dashboard/get-sand-usage-status")!,
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        return await post(request)
    }

    static func bearerRequest(token: String) async -> Response {
        var request = URLRequest(url: URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus")!,
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        return await post(request)
    }

    private static func post(_ input: URLRequest) async -> Response {
        var request = input
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        var result = Response()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            result.status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let json = try? JSONSerialization.jsonObject(with: data) else {
                result.shape = "<non-json \(data.count) bytes>"; return result
            }
            result.shape = CursorProbeNetwork.shape(json)
            guard let root = json as? [String: Any] else { return result }
            result.usagePercent = (root["usagePercent"] as? NSNumber)?.doubleValue
            result.nextReset = date(root["nextResetTimestampUtc"])
            let included = (root["includedLimitZero"] as? Bool).map { !$0 } ?? root["hasNonZeroIncludedLimit"] as? Bool
            result.hasIncluded = included
            let trial = date(root["sandTrialExpiresAt"]).map { $0 > Date() }
            result.trialOnly = included == true ? false : trial
            // Booleans and presence only: no amounts, dates or identity.
            result.flags = ["hasAvailableUsage", "hasNonZeroIncludedLimit", "includedLimitZero"]
                .map { key in "\(key)=\((root[key] as? Bool).map { String($0) } ?? "nil")" }
                .joined(separator: " ")
                + " usagePercent=\(result.usagePercent == nil ? "nil" : "present")"
                + " nextReset=\(result.nextReset == nil ? "nil" : "present")"
                + " trialExpiresAt=\(root["sandTrialExpiresAt"] == nil || root["sandTrialExpiresAt"] is NSNull ? "nil" : "present")"
        } catch {
            result.shape = (error as? URLError).map { "URLError \($0.code.rawValue)" } ?? "error"
        }
        return result
    }

    private static func date(_ value: Any?) -> Date? {
        if let n = value as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue > 1e12 ? n.doubleValue / 1000 : n.doubleValue) }
        return (value as? String).flatMap(parseDate)
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) ?? ISO8601DateFormatter().date(from: s) { return d }
        // Some dashboard timestamps are epoch milliseconds as strings.
        return Double(s).map { Date(timeIntervalSince1970: $0 > 1e12 ? $0 / 1000 : $0) }
    }
}
#endif
