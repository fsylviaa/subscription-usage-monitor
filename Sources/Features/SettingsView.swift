import SwiftUI

struct SettingsView: View {
    var supportBottomInset: CGFloat = 60
    var demoEnabled = false
    var canManage = true
    var setDemoMode: (Bool) -> Void = { _ in }
    var darkAppearance = false
    var setDarkAppearance: (Bool) -> Void = { _ in }
    @ObservedObject var reminders: ResetReminderSettings
    var openNotificationSettings: () -> Void = {}
    var openWidgetTutorial: () -> Void = {}
    var body: some View {
        Form {
            Section("通用") {
                Toggle("深色模式", isOn: Binding(get: { darkAppearance }, set: setDarkAppearance))
                    .accessibilityIdentifier("settings.darkAppearance")
                Toggle(isOn: Binding(get: { reminders.isEnabled }, set: { enabled in
                    if enabled && reminders.showsSystemSettings {
                        openNotificationSettings()
                    } else {
                        Task { await reminders.setEnabled(enabled) }
                    }
                })) {
                    Label("重置提醒", systemImage: "bell")
                }
                .disabled(reminders.isRefreshing || reminders.isRequestingAuthorization)
                .accessibilityIdentifier("settings.resetReminder")
                if reminders.showsSystemSettings {
                    Button(action: openNotificationSettings) {
                        HStack {
                            Text("通知未允许").foregroundStyle(.secondary)
                            Spacer()
                            Text("去设置")
                        }
                    }
                    .accessibilityIdentifier("settings.notificationSettings")
                } else if reminders.hasError {
                    Button("重试") {
                        Task {
                            if reminders.wantsReminders { await reminders.setEnabled(true) }
                            else { await reminders.refreshAuthorization() }
                        }
                    }
                    .accessibilityIdentifier("settings.reminderRetry")
                }
            }

            Section("支持") {
                Button(action: openWidgetTutorial) {
                    Label("如何添加小组件", systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("settings.widgetTutorial")
                NavigationLink {
                    HelpView(bottomInset: supportBottomInset)
                } label: {
                    Label("帮助与说明", systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("settings.help")
                NavigationLink {
                    PrivacyView(bottomInset: supportBottomInset)
                } label: {
                    Label("隐私说明", systemImage: "hand.raised")
                }
                .accessibilityIdentifier("settings.privacy")
                NavigationLink {
                    OpenSourceView(bottomInset: supportBottomInset)
                } label: {
                    Label("开源许可", systemImage: "info.circle")
                }
                .accessibilityIdentifier("settings.licenses")
            }
            Section {
                Toggle("演示模式", isOn: Binding(get: { demoEnabled }, set: setDemoMode))
                    .disabled(!canManage)
                    .accessibilityIdentifier("settings.demo")
            } footer: {
                Text("开启后可添加演示账户，关闭时清除全部演示账户。")
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }


}


private struct HelpView: View {
    let bottomInset: CGFloat
    var body: some View {
        Form {
            Section("额度与重置") {
                Text("显示 Codex 订阅的剩余额度，包括每周和5小时窗口；只显示账户适用的窗口。预计重置时间来自平台，到点后仍以实际查询结果为准，不会自行变满。")
                    .accessibilityIdentifier("help.quota")
            }
            Section("刷新与旧数据") {
                Text("打开或回到 App 会自动刷新。下拉额度列表刷新全部账户，也可在账户菜单刷新单个账户。后台以约30分钟为目标，由系统允许时尽力更新，不保证准点。")
                Text("刷新失败时保留最近成功的额度和原更新时间，可点重试；尚无成功数据时显示未知。")
                    .accessibilityIdentifier("help.refresh")
            }
            Section("预计重置提醒") {
                Text("一个开关管理全部账户的预计重置提醒。提醒后打开 App 查看实际额度；通知显示受系统设置影响。")
                    .accessibilityIdentifier("help.reminders")
            }
            Section("小组件") {
                Text("小号和中号显示所选账户适用的每周和5小时额度。默认跟随列表首个账户；长按小组件，在“编辑小组件”的“显示账户”中可为每个组件选择账户，选定后不随排序改变。")
                Text("小组件会自动尝试更新，也会接收 App 的更新结果；系统可能延后显示，不保证固定更新间隔。")
                    .accessibilityIdentifier("help.widgets")
            }
        }
        .safeAreaPadding(.bottom, bottomInset)
        .navigationTitle("帮助与说明")
        .navigationBarTitleDisplayMode(.inline)
    }
}


private struct PrivacyView: View {
    let bottomInset: CGFloat
    var body: some View {
        Form {
            Section("数据来源与用途") {
                Text("通过 OpenAI 登录并查询 Codex 订阅的账户资料、剩余额度和预计重置时间，用于额度展示、小组件更新及重置提醒。")
                    .accessibilityIdentifier("privacy.source")
                Text("连接和刷新前进行必要网络检查：通过 Claude 获取网络出口地址，再交由 Net.Coffee 检查该地址。账户授权不会发送给这些网络检查服务。")
                    .accessibilityIdentifier("privacy.network")
            }
            Section("本机保存") {
                Text("登录授权安全保存在本机钥匙串；本机同时保存账户身份与顺序、最近成功的额度及重置时间、原成功时间和用户设置。App 与小组件共享更新所需的必要本机数据及授权。")
                    .accessibilityIdentifier("privacy.storage")
                Text("不采集电脑上的聊天、代码或会话日志。")
                    .accessibilityIdentifier("privacy.collection")
            }
            Section("删除账户") {
                Text("在额度页的账户菜单选择“删除账户”，移除本 App 对应的连接、授权和缓存数据。不会取消订阅，也不会退出浏览器或其他设备上的登录。")
                    .accessibilityIdentifier("privacy.deletion")
            }
        }
        .safeAreaPadding(.bottom, bottomInset)
        .navigationTitle("隐私说明")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct OpenSourceView: View {
    let bottomInset: CGFloat
    var body: some View {
        Form {
            Section {
                NavigationLink {
                    CodexBarLicenseView(bottomInset: bottomInset)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CodexBar")
                        Text("MIT · Codex 平台标志素材")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("licenses.codexBar")
            } footer: {
                Text("仅列出实际采用的开源项目或素材。完整许可随 App 提供，可离线查看。")
            }
        }
        .safeAreaPadding(.bottom, bottomInset)
        .navigationTitle("开源许可")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CodexBarLicenseView: View {
    let bottomInset: CGFloat
    // Read the bundled original; license details never depend on a web request.
    private let license = Bundle.main.url(forResource: "CodexBar-MIT", withExtension: "txt")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("CodexBar · MIT")
                    .font(.headline)
                Text("采用内容：Codex 平台标志素材\n来源：github.com/steipete/CodexBar")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let license {
                    ForEach(Array(license.components(separatedBy: "\n\n").enumerated()), id: \.offset) { index, paragraph in
                        Text(paragraph)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("license.paragraph.\(index)")
                    }
                } else {
                    Text("许可暂不可用")
                        .accessibilityIdentifier("license.unavailable")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .safeAreaPadding(.bottom, bottomInset)
        .background(DashboardStyle.background)
        .navigationTitle("CodexBar 许可")
        .navigationBarTitleDisplayMode(.inline)
    }
}
