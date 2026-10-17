#if DEBUG
import SwiftUI
import UIKit

/// T111 launch-only probe for OpenRouter and DeepSeek API balances. The pasted
/// key lives only in memory for one request and is cleared afterwards; nothing is
/// written to accounts, the keychain or logs. The saved report holds status codes
/// and field shapes only (no amounts, no key).
struct APIBalanceProbeView: View {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("--t111-balance-probe") }

    @StateObject private var probe = APIBalanceProbe()
    @State private var openRouterKey = ""
    @State private var deepSeekKey = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    keyField("粘贴 OpenRouter 管理密钥", text: $openRouterKey)
                    Button(probe.running ? "正在查询…" : "验证 OpenRouter") {
                        let key = openRouterKey; openRouterKey = ""
                        Task { await probe.runOpenRouter(key: key) }
                    }
                    .disabled(probe.running || openRouterKey.isEmpty)
                    ForEach(probe.openRouterRows) { row in LabeledContent(row.label, value: row.value) }
                } header: {
                    Text("OpenRouter")
                } footer: {
                    Text("对照 openrouter.ai 的 Credits 余额。也可以再贴一把普通 key 验证，预期被拒（403）。")
                }

                Section {
                    keyField("粘贴 DeepSeek API key", text: $deepSeekKey)
                    Button(probe.running ? "正在查询…" : "验证 DeepSeek") {
                        let key = deepSeekKey; deepSeekKey = ""
                        Task { await probe.runDeepSeek(key: key) }
                    }
                    .disabled(probe.running || deepSeekKey.isEmpty)
                    ForEach(probe.deepSeekRows) { row in LabeledContent(row.label, value: row.value) }
                } header: {
                    Text("DeepSeek")
                } footer: {
                    Text("对照 platform.deepseek.com 首页显示的余额。")
                }

                Section("过程（不含凭据）") {
                    ForEach(Array(probe.steps.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("API 余额验证")
        }
    }

    private func keyField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            SecureField(title, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("粘贴") {
                text.wrappedValue = (UIPasteboard.general.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .buttonStyle(.borderless)
        }
    }
}

@MainActor
final class APIBalanceProbe: ObservableObject {
    struct Row: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    @Published var running = false
    @Published var openRouterRows: [Row] = []
    @Published var deepSeekRows: [Row] = []
    @Published var steps: [String] = []
    private var report: [String: String] = [:]
    private let startedAt = Date()
    private var openRouterRuns = 0
    private var deepSeekRuns = 0

    func runOpenRouter(key: String) async {
        running = true; defer { running = false; writeReport() }
        openRouterRuns += 1
        let tag = "openrouter\(openRouterRuns)"
        var rows = [Row(label: "key", value: Self.tail(key))]
        let credits = await APIBalanceProbeNetwork.get("https://openrouter.ai/api/v1/credits", key: key)
        note("OpenRouter /credits → \(credits.status)")
        report["\(tag)_credits_status"] = String(credits.status)
        report["\(tag)_credits_shape"] = credits.shape
        rows.append(Row(label: "/credits 状态", value: String(credits.status)))
        if credits.status == 200, let data = (credits.json as? [String: Any])?["data"] as? [String: Any],
           let total = Self.decimal(data["total_credits"]), let used = Self.decimal(data["total_usage"]) {
            let balance = max(0, total - used)
            rows.append(Row(label: "累计充值", value: Self.money(total, "$", digits: 4)))
            rows.append(Row(label: "累计已用", value: Self.money(used, "$", digits: 4)))
            rows.append(Row(label: "余额（两位）", value: Self.money(balance, "$", digits: 2)))
            rows.append(Row(label: "余额（四位）", value: Self.money(balance, "$", digits: 4)))
            report["\(tag)_result"] = "balance_ok"
        } else {
            // Show whether the key itself is valid, to tell "wrong key type" from "bad key".
            let keyInfo = await APIBalanceProbeNetwork.get("https://openrouter.ai/api/v1/key", key: key)
            note("OpenRouter /key → \(keyInfo.status)")
            report["\(tag)_key_status"] = String(keyInfo.status)
            report["\(tag)_key_shape"] = keyInfo.shape
            rows.append(Row(label: "/key 状态", value: String(keyInfo.status)))
            let isManagement = ((keyInfo.json as? [String: Any])?["data"] as? [String: Any])?["is_management_key"] as? Bool
            rows.append(Row(label: "是管理密钥", value: isManagement.map { $0 ? "是" : "否" } ?? "—"))
            report["\(tag)_result"] = "no_balance"
        }
        openRouterRows = rows
    }

    func runDeepSeek(key: String) async {
        running = true; defer { running = false; writeReport() }
        deepSeekRuns += 1
        let tag = "deepseek\(deepSeekRuns)"
        var rows = [Row(label: "key", value: Self.tail(key))]
        let response = await APIBalanceProbeNetwork.get("https://api.deepseek.com/user/balance", key: key)
        note("DeepSeek /user/balance → \(response.status)")
        report["\(tag)_status"] = String(response.status)
        report["\(tag)_shape"] = response.shape
        rows.append(Row(label: "状态", value: String(response.status)))
        if response.status == 200, let root = response.json as? [String: Any] {
            rows.append(Row(label: "可调用 API", value: (root["is_available"] as? Bool).map { $0 ? "是" : "否" } ?? "—"))
            let infos = root["balance_infos"] as? [[String: Any]] ?? []
            report["\(tag)_currencies"] = infos.compactMap { $0["currency"] as? String }.joined(separator: ",")
            for info in infos {
                let currency = info["currency"] as? String ?? "?"
                let symbol = currency == "CNY" ? "¥" : currency == "USD" ? "$" : currency + " "
                for (field, label) in [("total_balance", "总余额"), ("topped_up_balance", "充值余额"), ("granted_balance", "赠送余额")] {
                    let value = Self.decimal(info[field]).map { Self.money($0, symbol, digits: 2) } ?? "—"
                    rows.append(Row(label: "\(currency) \(label)", value: value))
                }
            }
            report["\(tag)_result"] = infos.isEmpty ? "no_balance_infos" : "balance_ok"
        } else {
            report["\(tag)_result"] = "no_balance"
        }
        deepSeekRows = rows
    }

    private static func tail(_ key: String) -> String {
        key.count > 8 ? "…" + key.suffix(4) : "（太短）"
    }

    private static func decimal(_ value: Any?) -> Decimal? {
        switch value {
        case let s as String: return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
        case let n as NSNumber where CFGetTypeID(n) != CFBooleanGetTypeID():
            return Decimal(string: n.stringValue, locale: Locale(identifier: "en_US_POSIX"))
        default: return nil
        }
    }

    private static func money(_ value: Decimal, _ symbol: String, digits: Int) -> String {
        var input = value, rounded = Decimal()
        NSDecimalRound(&rounded, &input, digits, .plain)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return symbol + (f.string(from: rounded as NSDecimalNumber) ?? "\(rounded)")
    }

    private func writeReport() {
        report["steps"] = steps.joined(separator: "\n")
        report["finished_at"] = ISO8601DateFormatter().string(from: Date())
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
           let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? data.write(to: dir.appendingPathComponent("t111-balance-probe-report.json"), options: .completeFileProtection)
        }
    }

    private func note(_ line: String) {
        steps.append("+\(Int(Date().timeIntervalSince(startedAt)))s \(line)")
    }
}

enum APIBalanceProbeNetwork {
    struct Response {
        var status = 0
        var shape = ""
        var json: Any?
    }

    static func get(_ url: String, key: String) async -> Response {
        var request = URLRequest(url: URL(string: url)!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var result = Response()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            result.status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let json = try? JSONSerialization.jsonObject(with: data) {
                result.json = json
                result.shape = shape(json)
            } else {
                result.shape = "<non-json \(data.count) bytes>"
            }
        } catch {
            result.shape = (error as? URLError).map { "URLError \($0.code.rawValue)" } ?? "error"
        }
        return result
    }

    /// Structure only: amounts become <amount>, other text <string>; currency codes kept.
    static func shape(_ value: Any, key: String = "") -> String {
        switch value {
        case let dict as [String: Any]:
            return "{" + dict.keys.sorted().map { "\($0): \(shape(dict[$0]!, key: $0))" }.joined(separator: ", ") + "}"
        case let array as [Any]:
            return "[\(array.count)× " + (array.first.map { shape($0) } ?? "") + "]"
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return "<number>"
        case let s as String:
            if key == "currency" { return "\"\(s)\"" }
            return Decimal(string: s) != nil ? "<amount-string>" : "<string>"
        case is NSNull:
            return "null"
        default:
            return "<?>"
        }
    }
}
#endif
