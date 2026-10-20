import SwiftUI
import UIKit

struct CodexConnectionView: View {
    @ObservedObject var flow: CodexConnectionFlow
    /// Reports the picker's full natural height so the sheet opens showing every platform.
    var platformPickerHeight: (CGFloat) -> Void = { _ in }
    @State private var headerHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .headline) private var titleSize = 18
    @ScaledMetric(relativeTo: .largeTitle) private var keySize: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var copySize: CGFloat = 19

    private var title: String {
        if flow.state == .choosingPlatform { return "连接账号" }
        if flow.state == .quota {
            return flow.quotaFailure == nil ? "正在获取额度" : "首次额度查询失败"
        }
        return "连接 \(flow.connectingPlatform.accessibilityName)"
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title).font(.system(size: titleSize, weight: .semibold))
                    .multilineTextAlignment(.center).padding(.horizontal, 48)
                    .accessibilityIdentifier("connection.title")
                HStack {
                    Button(action: flow.cancel) {
                        AppIconView(.close).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain).accessibilityLabel(flow.state == .quota || flow.state == .choosingPlatform ? "关闭" : "取消")
                    .accessibilityIdentifier("connection.cancel").disabled(flow.state == .saving)
                    Spacer()
                }
            }
            .frame(minHeight: 52).padding(.top, 18).padding(.horizontal, 8)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { headerHeight = $0 }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch flow.state {
                    case .choosingPlatform:
                        ConnectionPlatformGrid(select: { flow.selectPlatform($0) })
                    case .quota:
                        quotaContent
                    case .keyEntry:
                        // Own view: the pasted key lives only in its state and is gone when it closes.
                        APIKeyEntryView(flow: flow)
                    case .idle, .checking, .requesting, .verifying, .saving:
                        ProgressView(flow.state == .verifying || flow.state == .saving
                                     ? (flow.connectingPlatform.balanceProvider != nil ? "正在连接…" : "正在完成登录…") : "连接中…")
                            .frame(maxWidth: .infinity, minHeight: 88)
                            .accessibilityIdentifier("connection.progress")
                    case .browser:
                        VStack(spacing: 24) {
                            DesignIcon(name: "Cursor", size: 44)
                            Text("在浏览器中登录 Cursor").font(.title2.bold()).multilineTextAlignment(.center)
                                .accessibilityIdentifier("connection.cursorTitle")
                            Text("在打开的 Cursor 页面登录并确认，完成后回到 App，会自动继续。")
                                .foregroundStyle(DashboardStyle.secondary).multilineTextAlignment(.center)
                            Button("重新打开登录页") { Task { await flow.openCursorBrowser() } }
                                .buttonStyle(DashboardButtonStyle(secondary: true)).accessibilityIdentifier("connection.cursorOpen")
                            if flow.browserFailed { Text("无法打开浏览器，请重试").foregroundStyle(DashboardStyle.secondary) }
                            ProgressView().accessibilityLabel("等待登录确认")
                        }
                        .frame(maxWidth: .infinity)
                    case let .failure(message):
                        Text(message).font(.subheadline).foregroundStyle(DashboardStyle.secondary)
                            .accessibilityIdentifier("connection.failure")
                        Button("重试", action: { flow.begin() })
                            .buttonStyle(DashboardButtonStyle()).accessibilityIdentifier("connection.retry")
                        Button("关闭", action: flow.cancel).buttonStyle(DashboardButtonStyle(secondary: true))
                    case let .code(authorization):
                        VStack(spacing: 24) {
                            AppIconView(.key, size: keySize)
                            Text("在官网输入一次性代码").font(.title2.bold()).multilineTextAlignment(.center)
                            Text(authorization.userCode).font(.title.monospaced().bold())
                                .multilineTextAlignment(.center).privacySensitive()
                                .accessibilityIdentifier("connection.code")
                            Button(action: flow.copy) {
                                Label { Text(flow.copied ? "已复制" : "复制代码") } icon: { AppIconView(.copy, size: copySize) }
                            }
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
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
            }
        }
        .onChange(of: flow.state == .choosingPlatform ? (headerHeight + contentHeight).rounded(.up) : 0, initial: true) { _, height in
            if height > 0, contentHeight > 0 { platformPickerHeight(height) }
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
            Text(account.identityText)
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
    @ScaledMetric(relativeTo: .title) private var iconSize = 48

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
                    // D-78: icon with the platform name below, both inside the grey tile.
                    VStack(spacing: 6) {
                        DesignIcon(name: platform.iconName, size: min(iconSize, 64))
                        Text(platform.accessibilityName).font(.subheadline.weight(.medium))
                            .lineLimit(1).minimumScaleFactor(0.5)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .background(DashboardStyle.elevated, in: RoundedRectangle(cornerRadius: 24))
                    .contentShape(RoundedRectangle(cornerRadius: 24))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(platform.accessibilityName)
                .accessibilityIdentifier(index < ConnectionPlatform.allCases.count
                    ? "platforms.\(platform.iconName.lowercased())" : "platforms.fixture.\(index)")
            }
        }
        .accessibilityIdentifier("platforms.grid")
    }
}


/// OpenRouter / DeepSeek key input (D-82, BAL-02/03): one secure field, a paste button and
/// 连接. The key is held only in this view's state and in memory for the one query.
private struct APIKeyEntryView: View {
    @ObservedObject var flow: CodexConnectionFlow
    @State private var key = ""
    @FocusState private var focused: Bool

    private var platform: ConnectionPlatform { flow.connectingPlatform }
    private var instruction: String {
        platform == .openRouter
            ? "请粘贴 OpenRouter 的 Management key（管理密钥），普通 API key 查不到账户余额。创建路径：openrouter.ai 左上角两条杠菜单 → Account → Management Keys（不是顶部 Settings）。"
            : "请粘贴你在 DeepSeek 开放平台已有的 API key，App 只用它查询余额。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DesignIcon(name: platform.iconName, size: 44).frame(maxWidth: .infinity)
            Text(instruction).font(.subheadline).foregroundStyle(DashboardStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("connection.keyInstruction")
            HStack(spacing: 10) {
                SecureField(platform == .openRouter ? "Management key" : "API key", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .privacySensitive().focused($focused).submitLabel(.go)
                    .onSubmit { flow.connectAPIKey(key) }
                    .padding(.horizontal, 14).frame(minHeight: 48)
                    .background(DashboardStyle.elevated, in: RoundedRectangle(cornerRadius: 14))
                    .disabled(flow.keyVerifying)
                    .accessibilityIdentifier("connection.keyField")
                Button("粘贴") {
                    key = (UIPasteboard.general.string ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 14))
                .tint(DashboardStyle.accent)
                .disabled(flow.keyVerifying)
                .accessibilityIdentifier("connection.keyPaste")
            }
            if let failure = flow.keyFailure {
                Text(failure).font(.subheadline).foregroundStyle(DashboardStyle.secondary)
                    .accessibilityIdentifier("connection.keyFailure")
            }
            Button { flow.connectAPIKey(key) } label: {
                if flow.keyVerifying { ProgressView().tint(DashboardStyle.accentText) } else { Text("连接") }
            }
            .buttonStyle(DashboardButtonStyle())
            .disabled(flow.keyVerifying || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(flow.keyVerifying ? "正在连接" : "连接")
            .accessibilityIdentifier("connection.keyConnect")
        }
        .onDisappear { key = "" }
    }
}
