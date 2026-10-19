import SwiftUI
import UIKit
import WidgetKit

struct RootView: View {
    @AppStorage private var appearance: String
    @AppStorage private var cardStyle: String
    @Environment(\.colorScheme) private var systemColorScheme
    @StateObject private var connection: CodexConnectionFlow
    @StateObject private var reminders: ResetReminderSettings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let onBackground: () -> Void
    private let reminderScheduler: ResetReminderScheduler?
    private let publishesWidgetAppearance: Bool
    @ObservedObject private var notificationNavigation: ResetReminderNavigation
    @State private var pendingNotification: ResetReminderOpenEvent?
    @State private var pendingWidgetRoute: WidgetQuotaRoute?
    @State private var pendingWidgetAdd = false
    @State private var detailTarget: CodexDetailTarget?
    @State private var reminderAccountsLoaded = false
    private enum Tab: Hashable { case quota, settings }
    @State private var selection: Tab = .quota
    private enum TutorialSource: String, Identifiable {
        case quota, settings
        var id: String { rawValue }
    }
    @State private var tutorialSource: TutorialSource?
    @State private var connectionDetent: PresentationDetent = .height(250)
    // Grows with the platform grid; taller than the screen is clamped to full height by the system.
    @State private var platformPickerHeight: CGFloat = 250
    @State private var appearanceTransition = AppearanceTransition()
    @State private var supportBottomInset: CGFloat = 60
    @State private var footerTop: CGFloat?

    init(connection: CodexConnectionFlow = CodexConnectionFlow.live(), preferences: UserDefaults = .standard, onBackground: @escaping () -> Void = {}, reminders: ResetReminderSettings? = nil, reminderScheduler: ResetReminderScheduler? = nil, notificationNavigation: ResetReminderNavigation = .shared) {
        self.notificationNavigation = notificationNavigation
        self.onBackground = onBackground
        self.reminderScheduler = reminderScheduler
        self.publishesWidgetAppearance = preferences === UserDefaults.standard
            && NSClassFromString("XCTestCase") == nil
            && !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--t") || $0 == "--management-ui" })
        _cardStyle = AppStorage(wrappedValue: QuotaCardStyle.defaultStyle.rawValue, QuotaCardStylePreferences.key, store: preferences)
        _appearance = AppStorage(wrappedValue: "system", "appearance", store: preferences)
        _connection = StateObject(wrappedValue: connection)
        _reminders = StateObject(wrappedValue: reminders ?? ResetReminderSettings(
            defaults: reminderScheduler == nil ? preferences : (SharedResetReminderRuntime.preferences ?? preferences)))
    }

    private var connectionDetents: Set<PresentationDetent> {
        if dynamicTypeSize.isAccessibilitySize { return [.large] }
        if connection.state == .choosingPlatform { return [.height(platformPickerHeight), .large] }
        if case .code = connection.state { return [.large] }
        if case .quota = connection.state { return [.height(310), .large] }
        return [.medium, .large]
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                QuotaView(accounts: connection.accounts, footerTop: footerTop, loading: connection.loadingAccounts,
                          loadFailed: connection.accountLoadFailed, canConnect: connection.canConnect,
                          updatingID: connection.quotaUpdatingID, updatingIDs: connection.visibleQuotaUpdatingIDs,
                          canRefreshAll: connection.canRefreshAll, refreshAll: { connection.refreshAllQuota() }, quotaFailure: connection.quotaFailure,
                          quotaFailureID: connection.quotaFailureID,
                          failedAccountIDs: Set(connection.quotaFailures.keys),
                          showDashboardFeedback: connection.quotaFeedbackLocation == .dashboard && !connection.quotaFeedbackHidden,
                          connect: { connection.showPlatformPicker() },
                          retry: { connection.retryDashboardQuota(for: $0) },
                          closeFeedback: { connection.hideQuotaFeedback() },
                          deleteAccount: { connection.deleteAccount($0) }, canManage: connection.canManageAccounts,
                          canRefresh: connection.canManageAccounts, refreshAccount: { connection.refreshQuota(for: $0) },
                          openDetails: { detailTarget = CodexDetailTarget($0) },
                          canReorder: connection.canReorderAccounts, savingOrder: connection.reorderingAccounts,
                          move: { connection.moveAccounts(from: $0, to: $1) })
            }
            .tag(Tab.quota).toolbar(.hidden, for: .tabBar)

            NavigationStack {
                SettingsView(supportBottomInset: supportBottomInset, demoEnabled: connection.demoEnabled, canManage: connection.canManageAccounts,
                             setDemoMode: { connection.setDemoMode($0) },
                             darkAppearance: appearance == "dark" || (appearance == "system" && systemColorScheme == .dark),
                             setDarkAppearance: { dark in
                                 appearanceTransition.perform {
                                     appearance = dark ? "dark" : "light"
                                 }
                             }, cardStyle: QuotaCardStyle.resolve(cardStyle),
                             setCardStyle: { cardStyle = $0.rawValue }, reminders: reminders, openNotificationSettings: {
                                 guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
                                 UIApplication.shared.open(url)
                             }, openWidgetTutorial: { tutorialSource = .settings })
            }
            .tag(Tab.settings).toolbar(.hidden, for: .tabBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if selection == .quota {
                    Button { tutorialSource = .quota } label: {
                        IconLabel("如何添加小组件", icon: .widgets, size: 19, relativeTo: .subheadline)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("quota.widgetTutorial")
                    .padding(.horizontal, 16)
                }
                HStack(spacing: 0) {
                    tab("额度", icon: .quota, value: .quota, id: "quota")
                    tab("设置", icon: .settings, value: .settings, id: "settings")
                }
                .padding(.top, 6).padding(.bottom, 4)
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { supportBottomInset = $0 }
            .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minY }) { footerTop = $0 }
            .foregroundStyle(clay && selection == .quota ? AnyShapeStyle(ClayPalette.ink(dark: dark)) : AnyShapeStyle(HierarchicalShapeStyle.primary))
            // 马卡龙粘土 continues the quota page ground under the bar (D-83).
            .background((clay && selection == .quota ? ClayPalette.pageBottom(dark: dark) : DashboardStyle.background)
                .ignoresSafeArea(edges: .bottom))
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
        .environment(\.quotaCardStyle, QuotaCardStyle.resolve(cardStyle))
        .onChange(of: cardStyle, initial: true) { _, value in
            #if DEBUG
            if QuotaCardStylePreferences.publishValidation(filename: "T78-style", value: QuotaCardStyle.resolve(value).rawValue) {
                Task { await CodexConnectionUITestSupport.recordStage3Configurations() }
                return
            }
            #endif
            guard publishesWidgetAppearance else { return }
            QuotaCardStylePreferences.publish(QuotaCardStyle.resolve(value), to: QuotaCardStylePreferences.sharedDefaults(),
                                              reload: QuotaCardStylePreferences.requestWidgetUpdate)
        }
        .onChange(of: appearance, initial: true) { _, value in
            #if DEBUG
            if QuotaCardStylePreferences.publishValidation(filename: "T37-appearance", value: value) { return }
            #endif
            guard publishesWidgetAppearance else { return }
            WidgetAppearance.publish(value, to: WidgetAppearance.defaults()) {
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetAppearance.kind)
            }
        }
        .onOpenURL { url in
            #if DEBUG
            if CodexConnectionUITestSupport.injectNotificationURLIfRequested(url) { return }
            #endif
            guard let route = WidgetQuotaRoute(url: url) else { return }
            tutorialSource = nil
            if let event = pendingNotification { notificationNavigation.consume(event.id) }
            pendingNotification = nil
            selection = .quota
            pendingWidgetRoute = route
            openPendingAccountRoute()
        }
        .onChange(of: notificationNavigation.pending, initial: true) { _, event in
            guard let event else { return }
            tutorialSource = nil
            selection = .quota
            pendingWidgetRoute = nil
            pendingNotification = event
            openPendingAccountRoute()
        }
        .onChange(of: connection.canConnect) { _, _ in
            openPendingAccountRoute()
            openPendingWidgetAdd()
        }
        .onChange(of: connection.loadingAccounts) { _, _ in openPendingAccountRoute() }
        .onChange(of: connection.cachedAccountsLoaded) { _, _ in openPendingAccountRoute() }
        .onChange(of: connection.isPresented) { _, presented in
            if !presented { openPendingAccountRoute() }
        }
        .task { await reminders.refreshAuthorization() }
        .task(id: reminderInput) {
            guard let reminderScheduler else { return }
            guard let input = reminderInput else { reminderScheduler.suspend(); return }
            await reminderScheduler.update(accounts: input.accounts,
                wantsReminders: input.wantsReminders, authorization: input.authorization)
        }
        .task {
            connection.sceneActivityChanged(scenePhase == .active)
            await connection.loadAccounts()
            reminderAccountsLoaded = true
            openPendingAccountRoute()
            openPendingWidgetAdd()
        }
        .onChange(of: scenePhase) { _, phase in
            connection.sceneActivityChanged(phase == .active)
            if phase == .active { Task { await reminders.refreshAuthorization() } }
            if phase == .background {
                WidgetPublicationRequests.shared.enteredBackground()
                onBackground()
            }
        }
        .onChange(of: connection.accounts) { _, accounts in
            if let detailTarget, detailTarget.resolve(in: accounts) == nil { self.detailTarget = nil }
        }
        .sheet(item: $tutorialSource, onDismiss: { openPendingAccountRoute() }) { _ in
            WidgetTutorialView(close: { tutorialSource = nil })
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
                .presentationBackground(DashboardStyle.background)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        }
        .sheet(item: $detailTarget, onDismiss: { openPendingWidgetAdd() }) { target in
            if let account = target.resolve(in: connection.accounts) {
                CodexDetailPanel(account: account,
                    updating: connection.visibleQuotaUpdatingIDs.contains(account.id),
                    failure: connection.quotaFeedbackHidden ? nil : connection.quotaFailures[account.id],
                    canManage: connection.canManageAccounts,
                    refresh: { connection.refreshQuota(for: account.id) },
                    closeFeedback: { connection.hideQuotaFeedback() },
                    delete: { connection.deleteAccount(account.id) },
                    close: { detailTarget = nil })
                    .environment(\.quotaCardStyle, QuotaCardStyle.resolve(cardStyle))
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(28)
                    .presentationBackground(DashboardStyle.background)
                    .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
            }
        }
        .sheet(isPresented: $connection.isPresented, onDismiss: { connection.cancel() }) {
            CodexConnectionView(flow: connection, platformPickerHeight: { height in
                guard height != platformPickerHeight else { return }
                platformPickerHeight = height
                if connection.state == .choosingPlatform { connectionDetent = initialConnectionDetent }
            })
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

    private struct ReminderInput: Equatable {
        let accounts: [ConnectedAccount]
        let wantsReminders: Bool
        let authorization: ResetReminderAuthorizationStatus
    }

    private var reminderInput: ReminderInput? {
        // Closing the switch can invalidate pending requests even while account
        // reads fail. Initial/temporary loading never masquerades as no accounts.
        guard reminders.wantsReminders else {
            return ReminderInput(accounts: [], wantsReminders: false, authorization: .unknown)
        }
        guard !reminders.isRefreshing, reminders.authorizationStatus != .unknown else { return nil }
        guard reminders.authorizationStatus.permitsReminders else {
            return ReminderInput(accounts: [], wantsReminders: true, authorization: reminders.authorizationStatus)
        }
        guard reminderAccountsLoaded || !connection.accounts.isEmpty,
              !connection.loadingAccounts, !connection.accountLoadFailed else { return nil }
        return ReminderInput(accounts: connection.accounts, wantsReminders: true,
            authorization: reminders.authorizationStatus)
    }

    private func openPendingAccountRoute() {
        // A cold-start URL or notification can precede cache restoration. A
        // failed read must never resolve a valid old target to a guessed account.
        guard pendingWidgetRoute != nil || pendingNotification != nil, connection.cachedAccountsLoaded,
              !connection.loadingAccounts, !connection.accountLoadFailed,
              !connection.isPresented, tutorialSource == nil else { return }
        let route = pendingWidgetRoute
        let notification = pendingNotification
        pendingWidgetRoute = nil
        pendingNotification = nil
        if let notification { notificationNavigation.consume(notification.id) }
        let replacingDetail = detailTarget != nil
        detailTarget = nil
        pendingWidgetAdd = false
        if let notification {
            detailTarget = notification.target?.detailTarget(in: connection.accounts)
            if detailTarget == nil && connection.accounts.filter({ $0.deletionPending != true }).isEmpty {
                pendingWidgetAdd = true
            }
        } else if let route {
            switch route {
            case .addAccount:
                pendingWidgetAdd = true
            case .quota:
                detailTarget = route.detailTarget(in: connection.accounts)
                if detailTarget == nil && connection.accounts.filter({ $0.deletionPending != true }).isEmpty {
                    pendingWidgetAdd = true
                }
            }
        }
        if !replacingDetail || !pendingWidgetAdd { openPendingWidgetAdd() }
        // Scene activation owns the refresh. Routing has no query side effect.
    }

    private func openPendingWidgetAdd() {
        guard pendingWidgetAdd, connection.canConnect else { return }
        connection.showPlatformPicker()
        if connection.isPresented { pendingWidgetAdd = false }
    }

    private var initialConnectionDetent: PresentationDetent {
        if dynamicTypeSize.isAccessibilitySize { return .large }
        switch connection.state {
        case .choosingPlatform: return .height(platformPickerHeight)
        case .code: return .large
        case .quota: return .height(310)
        default: return .medium
        }
    }

    private var clay: Bool { QuotaCardStyle.resolve(cardStyle) == .clay }
    private var dark: Bool {
        appearance == "dark" || (appearance == "system" && systemColorScheme == .dark)
    }

    /// 马卡龙粘土: strawberry for the selected tab, soft lavender grey otherwise (D-83).
    private func tabColor(selected: Bool) -> Color {
        if clay { return selected ? ClayPalette.rose : ClayPalette.idle(dark: dark) }
        return selected ? DashboardStyle.text : DashboardStyle.secondary
    }

    private func tab(_ title: String, icon: AppIcon, value: Tab, id: String) -> some View {
        Button { selection = value } label: {
            VStack(spacing: 3) {
                AppIconView(icon, size: 37)
                    .shadow(color: clay && selection == value ? ClayPalette.rose.opacity(0.35) : .clear, radius: 3, y: 2)
                Text(title).font(clay ? .system(.body, design: .rounded).weight(selection == value ? .bold : .medium) : .body.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tabColor(selected: selection == value))
        .opacity(selection == value || clay ? 1 : 0.7)
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


extension WidgetQuotaRoute {
    func detailTarget(in accounts: [ConnectedAccount]) -> CodexDetailTarget? {
        guard case let .quota(id?, key?) = self,
              let account = accounts.first(where: { $0.id == id && $0.deletionPending != true }),
              key == Self.identityKey(account.identityText,
                                      isDemo: account.isDemo, platform: account.platform)
        else { return nil }
        return CodexDetailTarget(account)
    }
}
