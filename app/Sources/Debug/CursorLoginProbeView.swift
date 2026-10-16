#if DEBUG
import CryptoKit
import SwiftUI
import UIKit

/// T89 launch-only probe for Cursor's official browser polling login. It keeps
/// tokens in memory only, never logs them, and writes a de-identified report.
struct CursorLoginProbeView: View {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("--t89-cursor-probe") }

    @StateObject private var probe = CursorLoginProbe()
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(probe.status).font(.headline)
                    Button(probe.running ? "等待登录确认…" : "开始验证") { probe.start() }
                        .disabled(probe.running)
                }
                Section("结果") {
                    LabeledContent("邮箱", value: probe.email ?? "—")
                    LabeledContent("本月剩余", value: probe.remaining ?? "—")
                    LabeledContent("本月已用", value: probe.used ?? "—")
                    LabeledContent("重置时间", value: probe.resetsAt ?? "—")
                }
                Section("过程（不含凭据）") {
                    ForEach(Array(probe.steps.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("Cursor 登录验证")
        }
        .onChange(of: phase) { _, now in probe.sceneChanged(active: now == .active) }
    }
}

@MainActor
final class CursorLoginProbe: ObservableObject {
    @Published var status = "点“开始验证”，在浏览器登录并确认后回到本页"
    @Published var running = false
    @Published var email: String?
    @Published var remaining: String?
    @Published var used: String?
    @Published var resetsAt: String?
    @Published var steps: [String] = []

    private var attempt: (uuid: String, verifier: String)?
    private var pollTask: Task<Void, Never>?
    private var attempts = 0
    private var consecutiveErrors = 0
    private var startedAt = Date()
    private var report: [String: String] = [:]

    func start() {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return }
        let verifier = Self.base64url(Data(bytes))
        let challenge = Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        let uuid = UUID().uuidString.lowercased()
        var url = URLComponents(string: "https://cursor.com/loginDeepControl")!
        url.queryItems = [.init(name: "challenge", value: challenge), .init(name: "uuid", value: uuid),
                          .init(name: "mode", value: "login"), .init(name: "redirectTarget", value: "cli"),
                          .init(name: "supportsSelectedTeamLogin", value: "true")]
        attempt = (uuid, verifier); attempts = 0; consecutiveErrors = 0; startedAt = Date()
        email = nil; remaining = nil; used = nil; resetsAt = nil; steps = []; report = [:]
        running = true; status = "已打开浏览器，确认后回到本页"
        note("打开官方登录页 cursor.com/loginDeepControl（redirectTarget=cli）")
        UIApplication.shared.open(url.url!) { [weak self] ok in
            Task { @MainActor in self?.note(ok ? "系统已交给默认浏览器" : "无法打开浏览器") }
        }
        startPolling()
    }

    func sceneChanged(active: Bool) {
        guard running else { return }
        if active {
            note("回到App，继续领取")
            startPolling()
        } else {
            pollTask?.cancel(); pollTask = nil
        }
    }

    private func startPolling() {
        guard pollTask == nil, let attempt else { return }
        pollTask = Task { [weak self] in
            var delay: UInt64 = 1_000_000_000
            while !Task.isCancelled {
                guard let self else { return }
                if self.attempts >= 150 { self.finish("等待超时（150次）"); return }
                self.attempts += 1
                let outcome = await CursorProbeNetwork.poll(uuid: attempt.uuid, verifier: attempt.verifier)
                if Task.isCancelled { return }
                switch outcome {
                case .waiting:
                    self.consecutiveErrors = 0
                case let .token(access, _):
                    self.note("第\(self.attempts)次领取成功，用时\(Int(Date().timeIntervalSince(self.startedAt)))秒")
                    self.pollTask = nil
                    await self.verify(accessToken: access)
                    return
                case let .failed(code):
                    self.consecutiveErrors += 1
                    self.note("领取返回 \(code)")
                    if self.consecutiveErrors >= 3 { self.finish("领取连续失败"); return }
                }
                try? await Task.sleep(nanoseconds: delay)
                delay = min(delay * 3 / 2, 10_000_000_000)
            }
        }
    }

    private func verify(accessToken: String) async {
        status = "已领取，正在核对身份与额度"
        let claims = CursorProbeNetwork.jwtSummary(accessToken)
        report["jwt"] = claims.description
        note("token声明：\(claims.description)")
        guard let userID = claims.userID else { finish("token缺少用户ID"); return }
        let cookie = "WorkosCursorSessionToken=\(userID)%3A%3A\(accessToken)"

        let me = await CursorProbeNetwork.get("https://cursor.com/api/auth/me", cookie: cookie)
        note("auth/me（Cookie）→ \(me.status)")
        report["auth_me_status"] = String(me.status)
        report["auth_me_shape"] = me.shape
        email = me.email

        var summary = await CursorProbeNetwork.get("https://cursor.com/api/usage-summary", cookie: cookie)
        note("usage-summary（Cookie）→ \(summary.status)")
        report["usage_summary_cookie_status"] = String(summary.status)
        if summary.status != 200 {
            let bearer = await CursorProbeNetwork.get("https://cursor.com/api/usage-summary", bearer: accessToken)
            note("usage-summary（Bearer）→ \(bearer.status)")
            report["usage_summary_bearer_status"] = String(bearer.status)
            if bearer.status == 200 { summary = bearer }
        }
        report["usage_summary_shape"] = summary.shape
        if let pct = summary.usedPercent {
            used = String(format: "%.2f%%", pct)
            remaining = String(format: "%.2f%%", max(0, 100 - pct))
            report["used_percent_source"] = summary.percentSource ?? "?"
        }
        if let end = summary.cycleEnd {
            resetsAt = end.formatted(date: .abbreviated, time: .shortened)
        }
        finish(summary.status == 200 && summary.usedPercent != nil ? "完成：请与 Cursor 官网核对" : "未取得本月额度")
    }

    private func finish(_ text: String) {
        pollTask?.cancel(); pollTask = nil
        attempt = nil; running = false; status = text
        report["result"] = text
        report["steps"] = steps.joined(separator: "\n")
        report["finished_at"] = ISO8601DateFormatter().string(from: Date())
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
           let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? data.write(to: dir.appendingPathComponent("t89-cursor-probe-report.json"), options: .completeFileProtection)
        }
    }

    private func note(_ line: String) {
        let t = Int(Date().timeIntervalSince(startedAt))
        steps.append("+\(t)s \(line)")
    }

    nonisolated static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

enum CursorProbeNetwork {
    enum PollOutcome: Sendable { case waiting, token(String, String), failed(String) }

    struct Response: Sendable {
        var status = 0
        var shape = ""
        var email: String?
        var usedPercent: Double?
        var percentSource: String?
        var cycleEnd: Date?
    }

    struct Claims: Sendable, CustomStringConvertible {
        var userID: String?
        var keys: [String] = []
        var subShape = "?"
        var hoursLeft: Int?
        var description: String {
            "keys=\(keys.joined(separator: ",")) sub=\(subShape) 剩余约\(hoursLeft.map(String.init) ?? "?")小时"
        }
    }

    static func poll(uuid: String, verifier: String) async -> PollOutcome {
        var url = URLComponents(string: "https://api2.cursor.sh/auth/poll")!
        url.queryItems = [.init(name: "uuid", value: uuid), .init(name: "verifier", value: verifier)]
        var request = URLRequest(url: url.url!, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 { return .waiting }
            guard code == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let access = json["accessToken"] as? String, let refresh = json["refreshToken"] as? String
            else { return .failed("HTTP \(code)") }
            return .token(access, refresh)
        } catch {
            return .failed((error as? URLError).map { "URLError \($0.code.rawValue)" } ?? "error")
        }
    }

    static func jwtSummary(_ token: String) -> Claims {
        var claims = Claims()
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return claims }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return claims }
        claims.keys = json.keys.sorted()
        if let sub = json["sub"] as? String {
            let segments = sub.split(separator: "|").map(String.init)
            claims.subShape = segments.enumerated().map { i, s in
                i == segments.count - 1 ? "<id len \(s.count)>" : s
            }.joined(separator: "|")
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
            if let last = segments.last, !last.isEmpty, last.unicodeScalars.allSatisfy(allowed.contains) {
                claims.userID = last
            }
        }
        if let exp = json["exp"] as? Double { claims.hoursLeft = Int((exp - Date().timeIntervalSince1970) / 3600) }
        return claims
    }

    static func get(_ address: String, cookie: String? = nil, bearer: String? = nil) async -> Response {
        var request = URLRequest(url: URL(string: address)!, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        var result = Response()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            result.status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let json = try? JSONSerialization.jsonObject(with: data) else {
                result.shape = "<non-json \(data.count) bytes>"; return result
            }
            result.shape = shape(json)
            if let root = json as? [String: Any] {
                result.email = root["email"] as? String
                if let end = root["billingCycleEnd"] as? String { result.cycleEnd = parseDate(end) }
                let plan = (root["individualUsage"] as? [String: Any])?["plan"] as? [String: Any]
                if let total = number(plan?["totalPercentUsed"]) {
                    result.usedPercent = total; result.percentSource = "individualUsage.plan.totalPercentUsed"
                } else if let u = number(plan?["used"]), let l = number(plan?["limit"]), l > 0 {
                    result.usedPercent = u / l * 100; result.percentSource = "individualUsage.plan.used/limit"
                }
            }
        } catch {
            result.shape = (error as? URLError).map { "URLError \($0.code.rawValue)" } ?? "error"
        }
        return result
    }

    private static func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    /// Structure only: values replaced by type markers, except booleans and
    /// short enum-like strings that carry no identity (e.g. membershipType).
    static func shape(_ value: Any, key: String = "") -> String {
        let keepText: Set<String> = ["membershipType", "limitType"]
        switch value {
        case let dict as [String: Any]:
            return "{" + dict.keys.sorted().map { "\($0): \(shape(dict[$0]!, key: $0))" }.joined(separator: ", ") + "}"
        case let array as [Any]:
            return "[\(array.count)× " + (array.first.map { shape($0) } ?? "") + "]"
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            let d = n.doubleValue
            return d == d.rounded() ? "<int>" : "<decimal>"
        case let s as String:
            if keepText.contains(key) { return "\"\(s)\"" }
            if s.contains("@") { return "<email>" }
            if parseDate(s) != nil { return "<iso8601>" }
            return "<string>"
        case is NSNull:
            return "null"
        default:
            return "<?>"
        }
    }
}
#endif
