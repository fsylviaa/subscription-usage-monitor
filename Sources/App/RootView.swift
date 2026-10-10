import SwiftUI
import UIKit

struct RootView: View {
    @AppStorage private var appearance: String
    @Environment(\.colorScheme) private var systemColorScheme
    @StateObject private var connection: CodexConnectionFlow
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private enum Tab: Hashable { case quota, settings }
    @State private var selection: Tab = .quota
    @State private var connectionDetent: PresentationDetent = .height(250)
    @State private var appearanceTransition = AppearanceTransition()

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
                          updatingID: connection.quotaUpdatingID, updatingIDs: connection.quotaUpdatingIDs,
                          canRefreshAll: connection.canRefreshAll, refreshAll: { connection.refreshAllQuota() }, quotaFailure: connection.quotaFailure,
                          quotaFailureID: connection.quotaFailureID,
                          failedAccountIDs: Set(connection.quotaFailures.keys),
                          showDashboardFeedback: connection.quotaFeedbackLocation == .dashboard && !connection.quotaFeedbackHidden,
                          connect: { connection.showPlatformPicker() },
                          retry: { connection.retryDashboardQuota(for: $0) },
                          closeFeedback: { connection.hideQuotaFeedback() },
                          canCancelUpdate: connection.manualQuotaInProgress, cancelUpdate: { connection.cancelQuotaUpdate() },
                          deleteAccount: { connection.deleteAccount($0) }, canManage: connection.canManageAccounts,
                          canRefresh: connection.quotaUpdatingID == nil, refreshAccount: { connection.refreshQuota(for: $0) },
                          canReorder: connection.canReorderAccounts, savingOrder: connection.reorderingAccounts,
                          move: { connection.moveAccounts(from: $0, to: $1) })
            }
            .tag(Tab.quota).toolbar(.hidden, for: .tabBar)

            NavigationStack {
                SettingsView(demoEnabled: connection.demoEnabled, canManage: connection.canManageAccounts,
                             setDemoMode: { connection.setDemoMode($0) },
                             darkAppearance: appearance == "dark" || (appearance == "system" && systemColorScheme == .dark),
                             setDarkAppearance: { dark in
                                 appearanceTransition.perform {
                                     appearance = dark ? "dark" : "light"
                                 }
                             })
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
        .background(AppearanceWindowReader(transition: appearanceTransition))
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

/// Fade the rendered page as a whole: SwiftUI color animation alone leaves native
/// navigation, form and menu surfaces switching their traits immediately.
@MainActor
private final class AppearanceTransition {
    weak var window: UIWindow?
    private var overlay: UIView?

    func perform(_ update: () -> Void) {
        guard let window, let snapshot = window.snapshotView(afterScreenUpdates: false) else {
            update()
            return
        }
        // A second tap starts from the currently visible blend, without jumping
        // back to the previous theme or blocking the underlying controls.
        overlay?.removeFromSuperview()
        snapshot.frame = window.bounds
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        snapshot.isUserInteractionEnabled = false
        snapshot.accessibilityElementsHidden = true
        window.addSubview(snapshot)
        overlay = snapshot
        update()

        // Let preferredColorScheme update the real page underneath the snapshot.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, self.overlay === snapshot else { return }
            window?.layoutIfNeeded()
            UIView.animate(withDuration: 0.65, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                snapshot.alpha = 0
            } completion: { [weak self] _ in
                snapshot.removeFromSuperview()
                if self?.overlay === snapshot { self?.overlay = nil }
            }
        }
    }
}

private struct AppearanceWindowReader: UIViewRepresentable {
    let transition: AppearanceTransition

    func makeUIView(context: Context) -> WindowProbe {
        let view = WindowProbe()
        view.transition = transition
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: WindowProbe, context: Context) {}

    final class WindowProbe: UIView {
        weak var transition: AppearanceTransition?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            transition?.window = window
        }
    }
}
