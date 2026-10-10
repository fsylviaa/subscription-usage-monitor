import SwiftUI

struct RootView: View {
    @StateObject private var connection: CodexConnectionFlow
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private enum Tab: Hashable { case quota, settings }
    @State private var selection: Tab = .quota

    init(connection: CodexConnectionFlow = CodexConnectionFlow.live()) {
        _connection = StateObject(wrappedValue: connection)
    }

    private var connectionDetents: Set<PresentationDetent> {
        if dynamicTypeSize.isAccessibilitySize { return [.large] }
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
                          showDashboardFeedback: connection.quotaFeedbackLocation == .dashboard && !connection.quotaFeedbackHidden,
                          connect: { connection.begin() },
                          retry: { connection.retryInitialQuota(for: $0) },
                          closeFeedback: { connection.hideQuotaFeedback() })
            }
            .tag(Tab.quota).toolbar(.hidden, for: .tabBar)

            NavigationStack {
                SettingsView(canConnect: connection.canConnect, connect: { connection.begin() })
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
        .tint(DashboardStyle.text)
        .task {
            connection.setActive(scenePhase == .active)
            await connection.loadAccounts()
        }
        .onChange(of: scenePhase) { _, phase in connection.setActive(phase == .active) }
        .sheet(isPresented: $connection.isPresented, onDismiss: { connection.cancel() }) {
            CodexConnectionView(flow: connection)
                .presentationDetents(connectionDetents)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(DashboardStyle.card)
                .interactiveDismissDisabled(connection.state == .saving)
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
