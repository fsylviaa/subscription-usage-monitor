import SwiftUI

struct RootView: View {
    @AppStorage private var appearance: String
    @Environment(\.colorScheme) private var systemColorScheme
    @StateObject private var connection: CodexConnectionFlow
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private enum Tab: Hashable { case quota, settings }
    @State private var selection: Tab = .quota
    @State private var connectionDetent: PresentationDetent = .height(250)

    init(connection: CodexConnectionFlow = CodexConnectionFlow.live(), preferences: UserDefaults = .standard) {
        _appearance = AppStorage(wrappedValue: "system", "appearance", store: preferences)
        _connection = StateObject(wrappedValue: connection)
    }

    private var connectionDetents: Set<PresentationDetent> {
        if dynamicTypeSize.isAccessibilitySize { return [.large] }
        if connection.state == .choosingPlatform { return [.height(250), .large] }
        if case .code = connection.state { return [.large] }
        if case .quota = connection.state { return [.height(310), .large] }
        return [.medium, .large]
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                QuotaView(accounts: connection.accounts, loading: connection.loadingAccounts,
                          loadFailed: connection.accountLoadFailed, canConnect: connection.canConnect,
                          updatingID: connection.quotaUpdatingID, quotaFailure: connection.quotaFailure,
                          quotaFailureID: connection.quotaFailureID,
                          failedAccountIDs: Set(connection.quotaFailures.keys),
                          showDashboardFeedback: connection.quotaFeedbackLocation == .dashboard && !connection.quotaFeedbackHidden,
                          connect: { connection.showPlatformPicker() },
                          retry: { connection.retryInitialQuota(for: $0) },
                          closeFeedback: { connection.hideQuotaFeedback() },
                          deleteAccount: { connection.deleteAccount($0) }, canManage: connection.canManageAccounts,
                          canReorder: connection.canReorderAccounts, savingOrder: connection.reorderingAccounts,
                          move: { connection.moveAccounts(from: $0, to: $1) })
            }
            .tag(Tab.quota).toolbar(.hidden, for: .tabBar)

            NavigationStack {
                SettingsView(demoEnabled: connection.demoEnabled, canManage: connection.canManageAccounts,
                             setDemoMode: { connection.setDemoMode($0) },
                             darkAppearance: appearance == "dark" || (appearance == "system" && systemColorScheme == .dark),
                             setDarkAppearance: { appearance = $0 ? "dark" : "light" })
            }
            .tag(Tab.settings).toolbar(.hidden, for: .tabBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 0) {
                tab("额度", icon: "Chart", value: .quota, id: "quota")
                tab("设置", icon: "Settings", value: .settings, id: "settings")
            }
            .padding(.top, 6).padding(.bottom, 4)
            .background(DashboardStyle.background.ignoresSafeArea(edges: .bottom))
        }
        .alert("排序未保存，请重试", isPresented: Binding(get: { connection.accountOrderFailed },
            set: { if !$0 { connection.dismissAccountOrderFailure() } })) {
            Button("好", role: .cancel) { connection.dismissAccountOrderFailure() }
        }
        .alert("操作未完成", isPresented: Binding(get: { connection.accountActionFailure != nil },
            set: { if !$0 { connection.accountActionFailure = nil } })) {
            Button("好", role: .cancel) { connection.accountActionFailure = nil }
        } message: { Text(connection.accountActionFailure ?? "请重试") }
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .tint(DashboardStyle.text)
        .task {
            connection.setActive(scenePhase == .active)
            await connection.loadAccounts()
        }
        .onChange(of: scenePhase) { _, phase in connection.setActive(phase == .active) }
        .sheet(isPresented: $connection.isPresented, onDismiss: { connection.cancel() }) {
            CodexConnectionView(flow: connection)
                .presentationDetents(connectionDetents, selection: $connectionDetent)
                .presentationContentInteraction(.resizes)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(DashboardStyle.card)
                .interactiveDismissDisabled(connection.state == .saving)
                .onChange(of: connection.state, initial: true) { _, _ in
                    connectionDetent = initialConnectionDetent
                }
                .onChange(of: dynamicTypeSize) { _, _ in connectionDetent = initialConnectionDetent }
        }
    }

    private var initialConnectionDetent: PresentationDetent {
        if dynamicTypeSize.isAccessibilitySize { return .large }
        switch connection.state {
        case .choosingPlatform: return .height(250)
        case .code: return .large
        case .quota: return .height(310)
        default: return .medium
        }
    }

    private func tab(_ title: String, icon: String, value: Tab, id: String) -> some View {
        Button { selection = value } label: {
            VStack(spacing: 3) {
                DesignIcon(name: icon, size: 23)
                Text(title).font(.caption2.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selection == value ? DashboardStyle.text : DashboardStyle.secondary)
        .opacity(selection == value ? 1 : 0.7)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selection == value ? .isSelected : [])
        .accessibilityIdentifier("tab.\(id)")
    }
}
