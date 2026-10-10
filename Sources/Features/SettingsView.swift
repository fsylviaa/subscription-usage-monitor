import SwiftUI

struct SettingsView: View {
    var demoEnabled = false
    var canManage = true
    var setDemoMode: (Bool) -> Void = { _ in }
    var darkAppearance = false
    var setDarkAppearance: (Bool) -> Void = { _ in }
    var body: some View {
        Form {
            Section("通用") {
                Toggle("深色模式", isOn: Binding(get: { darkAppearance }, set: setDarkAppearance))
                    .accessibilityIdentifier("settings.darkAppearance")
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
