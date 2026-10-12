import SwiftUI

struct CodexConnectionView: View {
    @ObservedObject var flow: CodexConnectionFlow
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .headline) private var titleSize = 18

    private var title: String {
        if flow.state == .choosingPlatform { return "连接账号" }
        if flow.state == .quota {
            return flow.quotaFailure == nil ? "正在获取额度" : "首次额度查询失败"
        }
        return "连接 Codex"
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title).font(.system(size: titleSize, weight: .semibold))
                    .multilineTextAlignment(.center).padding(.horizontal, 48)
                    .accessibilityIdentifier("connection.title")
                HStack {
                    Button(action: flow.cancel) {
                        DesignIcon(name: "Close").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain).accessibilityLabel(flow.state == .quota || flow.state == .choosingPlatform ? "关闭" : "取消")
                    .accessibilityIdentifier("connection.cancel").disabled(flow.state == .saving)
                    Spacer()
                }
            }
            .frame(minHeight: 52).padding(.top, 18).padding(.horizontal, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch flow.state {
                    case .choosingPlatform:
                        ConnectionPlatformGrid(select: { flow.selectPlatform($0) })
                    case .quota:
                        quotaContent
                    case .idle, .checking, .requesting, .verifying, .saving:
                        ProgressView(flow.state == .verifying || flow.state == .saving ? "正在完成登录…" : "连接中…")
                            .frame(maxWidth: .infinity, minHeight: 88)
                            .accessibilityIdentifier("connection.progress")
                    case let .failure(message):
                        Text(message).font(.subheadline).foregroundStyle(DashboardStyle.secondary)
                            .accessibilityIdentifier("connection.failure")
                        Button("重试", action: { flow.begin() })
                            .buttonStyle(DashboardButtonStyle()).accessibilityIdentifier("connection.retry")
                        Button("关闭", action: flow.cancel).buttonStyle(DashboardButtonStyle(secondary: true))
                    case let .code(authorization):
                        VStack(spacing: 24) {
                            Image(systemName: "key.horizontal").font(.largeTitle).accessibilityHidden(true)
                            Text("在官网输入一次性代码").font(.title2.bold()).multilineTextAlignment(.center)
                            Text(authorization.userCode).font(.title.monospaced().bold())
                                .multilineTextAlignment(.center).privacySensitive()
                                .accessibilityIdentifier("connection.code")
                            Button(flow.copied ? "已复制" : "复制代码", systemImage: "doc.on.doc", action: flow.copy)
                                .buttonStyle(DashboardButtonStyle(secondary: true))
                                .accessibilityIdentifier("connection.copy")
                            Button("打开官网") { Task { await flow.openWebsite() } }
                                .buttonStyle(DashboardButtonStyle()).accessibilityIdentifier("connection.open")
                            if flow.browserFailed { Text("登录未完成，请重试").foregroundStyle(DashboardStyle.secondary) }
                            Text("使用已有账户登录，完成后返回 App。")
                                .foregroundStyle(DashboardStyle.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 24)
            }
        }
        .foregroundStyle(DashboardStyle.text)
        .background(DashboardStyle.card)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { flow.expireIfNeeded() }
        }
    }

    @ViewBuilder private var quotaContent: some View {
        let account = flow.accounts.first { $0.id == (flow.quotaUpdatingID ?? flow.quotaFailureID) }
        if let account {
            Text(account.verifiedEmail ?? account.remoteUserID ?? "Codex 账户")
                .font(.subheadline).privacySensitive().foregroundStyle(DashboardStyle.secondary)
                .accessibilityIdentifier("connection.accountIdentity")
        }
        if let failure = flow.quotaFailure, let id = flow.quotaFailureID {
            Text(failure).font(.subheadline).foregroundStyle(DashboardStyle.secondary)
                .accessibilityIdentifier("connection.quotaFailure")
            VStack(spacing: 12) {
                Button("重试") { flow.retryInitialQuota(for: id, location: .connection) }
                    .buttonStyle(DashboardButtonStyle()).accessibilityIdentifier("connection.quotaRetry")
                Button("关闭", action: flow.cancel)
                    .buttonStyle(DashboardButtonStyle(secondary: true)).accessibilityIdentifier("connection.quotaClose")
            }
        } else {
            ProgressView("正在获取额度…").frame(maxWidth: .infinity, minHeight: 60)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("connection.quotaProgress")
        }
    }
}


private struct ConnectionPlatformGrid: View {
    let select: (ConnectionPlatform) -> Void
    @ScaledMetric(relativeTo: .title) private var iconSize = 36

    private var platforms: [ConnectionPlatform] {
        #if DEBUG
        // Layout-only overflow fixture; never registers a real extra provider.
        if ProcessInfo.processInfo.arguments.contains("--t16-platform-grid-overflow") {
            return Array(repeating: .codex, count: 30)
        }
        #endif
        return ConnectionPlatform.allCases
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 20) {
            ForEach(platforms.indices, id: \.self) { index in
                let platform = platforms[index]
                Button { select(platform) } label: {
                    DesignIcon(name: platform.iconName, size: min(iconSize, 56))
                        .frame(maxWidth: .infinity, minHeight: max(88, min(iconSize, 56) + 32))
                        .background(DashboardStyle.elevated, in: RoundedRectangle(cornerRadius: 24))
                        .contentShape(RoundedRectangle(cornerRadius: 24))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(platform.accessibilityName)
                .accessibilityIdentifier(index == 0 ? "platforms.codex" : "platforms.fixture.\(index)")
            }
        }
        .accessibilityIdentifier("platforms.grid")
    }
}
