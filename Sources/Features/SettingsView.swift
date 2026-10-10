import SwiftUI

struct SettingsView: View {
    var accounts: [ConnectedAccount] = []
    var canConnect = true
    var connect: () -> Void = {}
    var body: some View {
        Form {
            Section("账户") {
                NavigationLink {
                    List {
                        ForEach(accounts) { account in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(account.verifiedEmail ?? "Codex 账户")
                                    .accessibilityIdentifier("accounts.identity")
                                Text(account.subscription.map { "Codex · \($0.planType)" } ?? "Codex")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        Button("连接 Codex", systemImage: "plus", action: connect)
                            .disabled(!canConnect).accessibilityIdentifier("accounts.connect")
                    }
                    .navigationTitle("账户管理")
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label("账户管理", systemImage: "person.crop.circle")
                }
                .accessibilityIdentifier("settings.accounts")
                Button("连接 Codex", systemImage: "plus", action: connect)
                    .accessibilityIdentifier("settings.connect")
                    .disabled(!canConnect)
            }

            Section("通用") {
                // T38 接入持久化开关与系统通知权限后开放。
                Toggle(isOn: .constant(false)) {
                    Label("额度重置通知", systemImage: "bell")
                        .foregroundStyle(.secondary)
                }
                .disabled(true)
                .accessibilityIdentifier("settings.resetReminder")
            }

            Section("支持") {
                pendingAction("如何添加小组件", systemImage: "square.grid.2x2", identifier: "settings.widgetTutorial")
                pendingAction("帮助与说明", systemImage: "questionmark.circle", identifier: "settings.help")
                pendingAction("隐私说明", systemImage: "hand.raised", identifier: "settings.privacy")
                pendingAction("开源许可", systemImage: "info.circle", identifier: "settings.licenses")
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pendingAction(_ title: String, systemImage: String, identifier: String) -> some View {
        Button {
            // 对应功能任务接入后再开放，T03 不展示空白子页面。
        } label: {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.secondary)
        }
        .disabled(true)
        .accessibilityIdentifier(identifier)
    }
}
