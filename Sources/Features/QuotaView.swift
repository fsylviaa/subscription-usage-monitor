import SwiftUI
import UIKit

/// Tokens and vectors from the project's read-only Figma source.
enum DashboardStyle {
    static let background = Color("DesignBg")
    static let card = Color("DesignCard")
    static let elevated = Color("DesignElevated")
    static let text = Color("DesignText")
    static let secondary = Color("DesignSecondary")
    static let track = Color("DesignTrack")
    static let accent = Color("DesignAccent")
    static let accentText = Color("DesignAccentText")
}

struct DesignIcon: View {
    let name: String
    var size: CGFloat = 20
    var body: some View {
        Image("Design" + name).resizable().scaledToFit()
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct QuotaView: View {
    var accounts: [ConnectedAccount] = []
    var loading = false
    var loadFailed = false
    var canConnect = true
    var updatingID: UUID?
    var updatingIDs: Set<UUID> = []
    var canRefreshAll = false
    var refreshAll: () -> Void = {}
    var quotaFailure: String?
    var quotaFailureID: UUID?
    var failedAccountIDs: Set<UUID> = []
    var showDashboardFeedback = true
    var connect: () -> Void = {}
    var retry: (UUID) -> Void = { _ in }
    var closeFeedback: () -> Void = {}
    var deleteAccount: (UUID) -> Void = { _ in }
    var canManage = true
    var canRefresh = false
    var refreshAccount: (UUID) -> Void = { _ in }
    @State private var deleting: ConnectedAccount?
    var openDetails: (ConnectedAccount) -> Void = { _ in }
    var canReorder = false
    var savingOrder = false
    var move: (IndexSet, Int) -> Void = { _, _ in }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var titleSize = 18

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("订阅额度").font(.system(size: dynamicTypeSize.isAccessibilitySize ? min(titleSize, 28) : titleSize, weight: .semibold))
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("quota.title")
                    #if DEBUG
                    .accessibilityValue(AppBackgroundRuntime.shared.debugSummary)
                    #endif
                Spacer(minLength: 12)
                Button(action: connect) {
                    DesignIcon(name: "Link").frame(width: 44, height: 44)
                }
                .disabled(!canConnect).accessibilityLabel("连接账号")
                .accessibilityIdentifier("quota.toolbarConnect")
            }
            .buttonStyle(.plain)
            .padding(.leading, 16).padding(.trailing, 12).frame(minHeight: 48)

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("正在加载账户")
                    .accessibilityIdentifier("quota.loading")
            } else if loadFailed {
                ContentUnavailableView("刷新失败", systemImage: "exclamationmark.circle")
            } else if accounts.isEmpty {
                ContentUnavailableView {
                    Label("未连接账户", systemImage: "link").accessibilityIdentifier("quota.empty")
                } actions: {
                    Button("连接账号", action: connect)
                        .buttonStyle(DashboardButtonStyle())
                        .accessibilityIdentifier("quota.connect")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                        if showDashboardFeedback {
                            if updatingID == nil, let quotaFailure, let id = quotaFailureID {
                                HStack(spacing: 12) {
                                    Text(quotaFailure).font(.subheadline)
                                        .accessibilityIdentifier("quota.failure")
                                    Spacer(minLength: 0)
                                    Button("重试") { retry(id) }
                                        .font(.subheadline.weight(.semibold))
                                        .accessibilityIdentifier("quota.retry")
                                    Button(action: closeFeedback) {
                                        DesignIcon(name: "Close", size: 16).frame(width: 44, height: 44)
                                    }
                                    .accessibilityLabel("关闭提示").accessibilityIdentifier("quota.closeFeedback")
                                }
                                .buttonStyle(.plain).padding(.leading, 12)
                                .background(DashboardStyle.elevated, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    ReorderableQuotaList(accounts: accounts, canMove: canReorder, saving: savingOrder, move: move,
                                         canRefresh: canRefreshAll, refresh: refreshAll) { account in
                        QuotaAccountCard(account: account, updating: updatingIDs.contains(account.id),
                                         failed: failedAccountIDs.contains(account.id) || quotaFailureID == account.id,
                                         canManage: canManage, canRefresh: canRefresh,
                                         refresh: { refreshAccount(account.id) }, delete: { deleting = account },
                                         openDetails: { openDetails(account) })
                    }
                }

            }
        }
        .foregroundStyle(DashboardStyle.text)
        .background(DashboardStyle.background)
        .toolbar(.hidden, for: .navigationBar)
        .alert("删除账户？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除账户", role: .destructive) {
                if let account = deleting { deleteAccount(account.id) }
                deleting = nil
            }
        } message: { Text("仅断开本 App 的连接，不会取消订阅。") }
    }

    static func amountText(_ amount: QuotaAmount) -> String {
        switch amount {
        case .unknown: "未知"
        case .unlimited: "不限量"
        case let .limited(value): "剩余 \(value.remaining.formatted(.number.precision(.fractionLength(0...2))))%"
        }
    }

    nonisolated static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.month().day().hour().minute())
    }

    static func resetText(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let date else { return "未提供重置时间" }
        guard date > now else { return "已到预计时间" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        if date.timeIntervalSince(now) >= 86_400, days > 0 {
            return "\(days) 天后 \(date.formatted(.dateTime.hour().minute()))"
        }
        let minutes = max(1, Int(ceil(date.timeIntervalSince(now) / 60)))
        if minutes < 60 { return "\(minutes) 分钟后" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) 小时后" : "\(hours) 小时 \(rest) 分后"
    }
}

private struct QuotaAccountCard: View {
    let account: ConnectedAccount
    let updating: Bool
    let failed: Bool
    var canManage = true
    var canRefresh = false
    var refresh: () -> Void = {}
    var delete: () -> Void = {}
    var openDetails: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var titleSize = 17
    @ScaledMetric(relativeTo: .caption2) private var emailSize = 11
    // Larger base sizes with gentler scaling keep the account header secondary
    // to the quota number, while still growing through every accessibility size.
    @ScaledMetric(relativeTo: .largeTitle) private var accessibilityTitleSize = 22
    @ScaledMetric(relativeTo: .title) private var accessibilityMetadataSize = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        platformIcon
                        Spacer()
                        accountMenu
                    }
                    planControl
                    identity
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    platformIcon
                    VStack(alignment: .leading, spacing: 1) {
                        planControl
                        identity
                    }
                    Spacer(minLength: 0)
                    accountMenu
                }
            }
            if let snapshot = account.quotaSnapshot {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(spacing: 10) {
                        QuotaWindowView(value: snapshot.weekly, title: "每周", id: "weekly", now: context.date)
                        if snapshot.fiveHours.shouldDisplay {
                            QuotaWindowView(value: snapshot.fiveHours, title: "5 小时", id: "fiveHours", now: context.date)
                        }
                    }
                }
            } else if account.quotaState == .notFetched {
                Text(failed ? "获取失败" : "尚未获取额度")
                    .font(metadataFont).foregroundStyle(DashboardStyle.secondary)
                    .accessibilityIdentifier(failed ? "quota.accountStatus" : "quota.notFetched")
            }
        }
        // Keep the content at its natural height while UIKit interpolates the row.
        // A transient smaller proposal must not compress the header and quota rows.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardStyle.card, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quota.card")
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture(perform: openDetails)
        // UIKit animates the self-sizing cell and following rows. Do not also
        // interpolate SwiftUI text positions through its intermediate proposals.
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }

    private var platformIcon: some View {
        DesignIcon(name: "Codex", size: 24.48)
            .frame(width: 34, height: 34)
            .background(DashboardStyle.elevated, in: RoundedRectangle(cornerRadius: 12))
    }

    private var planControl: some View {
        HStack(spacing: 6) {
            Button(action: openDetails) { planTitle }
                .buttonStyle(.plain)
                .accessibilityHint("查看账户详情")
                .accessibilityIdentifier("quota.details")
            // Reserve the same small slot when idle so refresh never reflows
            // the plan, chevron or identity. System progress animates independently
            // of the card's disabled layout animations.
            ZStack {
                if updating {
                    ProgressView().controlSize(.mini)
                        .dynamicTypeSize(.medium)
                        .accessibilityLabel("正在刷新")
                        .accessibilityIdentifier("quota.refreshProgress")
                }
            }
            .frame(width: 14, height: 14)
        }
    }

    @ViewBuilder private var identity: some View {
        if account.isDemo {
            Text("演示")
                .font(dynamicTypeSize.isAccessibilitySize ? .system(size: accessibilityMetadataSize) : .caption2)
                .foregroundStyle(DashboardStyle.secondary)
        }
        Text(account.verifiedEmail ?? account.remoteUserID ?? "Codex 账户")
            .font(.system(size: dynamicTypeSize.isAccessibilitySize ? accessibilityMetadataSize : emailSize))
            .foregroundStyle(DashboardStyle.secondary)
            .fixedSize(horizontal: false, vertical: true).privacySensitive()
            .accessibilityIdentifier("quota.accountIdentity")
    }

    private var metadataFont: Font {
        dynamicTypeSize.isAccessibilitySize ? .system(size: accessibilityMetadataSize) : .caption
    }

    private var accountMenu: some View {
        Menu {
            Button("刷新额度", systemImage: "arrow.clockwise", action: refresh).disabled(!canRefresh)
            Button("删除账户", systemImage: "trash", role: .destructive, action: delete)
        } label: {
            Image(systemName: "ellipsis")
                .font(dynamicTypeSize.isAccessibilitySize ? .system(size: 20, weight: .semibold) : .body.weight(.semibold))
                .frame(width: dynamicTypeSize.isAccessibilitySize ? 44 : 36,
                       height: dynamicTypeSize.isAccessibilitySize ? 44 : 36)
                .contentShape(Rectangle())
        }
        .disabled(!canManage)
        .accessibilityLabel("账户操作").accessibilityIdentifier("quota.menu")
    }

    private var planTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(account.subscription.map { "Codex · \($0.planType)" } ?? "Codex")
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? accessibilityTitleSize : titleSize, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("quota.plan")
            if account.quotaSnapshot != nil {
                DesignIcon(name: "Down", size: 14)
            }
        }
    }
}

struct QuotaWindowView: View {
    let value: QuotaWindowSnapshot
    let title: String
    let id: String
    let now: Date
    var detail = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var labelSize = 12
    @ScaledMetric(relativeTo: .caption2) private var resetSize = 11
    @ScaledMetric(relativeTo: .headline) private var amountSize = 18
    @ScaledMetric(relativeTo: .title) private var accessibilityMetadataSize = 14

    // Enlarge the dashboard's window as a whole, retaining its visual ratios.
    private var scale: CGFloat { detail ? 1.25 : 1 }

    private var secondarySize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? accessibilityMetadataSize : resetSize
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8 * scale) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        windowTitle
                        Spacer(minLength: 12 * scale)
                        amount
                    }
                    VStack(alignment: .leading, spacing: 4 * scale) { windowTitle; amount }
                }
                if !detail { progressBar }
                HStack(alignment: .firstTextBaseline, spacing: 6 * scale) {
                    DesignIcon(name: "Clock", size: 14 * scale)
                    resetTime
                }
                .foregroundStyle(DashboardStyle.secondary)
                if detail { progressBar }
            }
        } else {
            VStack(spacing: 4 * scale) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5 * scale) { reset; Spacer(minLength: 6 * scale); amount }
                    VStack(alignment: .leading, spacing: 6 * scale) {
                        reset
                        HStack { Spacer(); amount }
                    }
                }
                progressBar
            }
        }
    }

    @ViewBuilder private var progressBar: some View {
        if case let .limited(percentage) = value.amount {
            GeometryReader { geometry in
                Capsule().fill(DashboardStyle.track)
                    .overlay(alignment: .leading) {
                        Capsule().fill(DashboardStyle.text)
                            .frame(width: geometry.size.width * percentage.used / 100)
                    }
            }
            .frame(height: 6 * scale)
            .accessibilityElement().accessibilityLabel("\(title)额度条")
            .accessibilityValue("已用 \(valueUsedText)，\(QuotaView.amountText(value.amount))")
            .accessibilityIdentifier("\(detail ? "detail" : "quota").\(id).bar")
        }
    }

    private var windowTitle: some View {
        Text(title).font(.system(size: labelSize * scale, weight: .medium)).fixedSize()
            .foregroundStyle(DashboardStyle.secondary)
    }

    private var resetTime: some View {
        Text(QuotaView.resetText(value.resetsAt, now: now))
            .font(.system(size: secondarySize * scale)).fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(value.resetsAt.map { "预计重置于 \(QuotaView.dateText($0))" } ?? "未提供重置时间")
            .accessibilityValue(QuotaView.resetText(value.resetsAt, now: now))
            .accessibilityIdentifier("\(detail ? "detail" : "quota").\(id).reset")
    }

    private var reset: some View {
        HStack(spacing: 5 * scale) {
            windowTitle
            DesignIcon(name: "Clock", size: 11 * scale)
            resetTime
        }
        .foregroundStyle(DashboardStyle.secondary)
    }

    private var amount: some View {
        Group {
            if case let .limited(percentage) = value.amount {
                (Text("剩余 ").font(.system(size: secondarySize * scale)).foregroundColor(DashboardStyle.secondary)
                 + Text("\(percentage.remaining.formatted(.number.precision(.fractionLength(0...2))))%")
                    .font(.system(size: amountSize * scale, weight: .semibold)))
            } else {
                Text(QuotaView.amountText(value.amount)).font(.system(size: labelSize * scale, weight: .medium))
            }
        }
        .fixedSize().monospacedDigit().accessibilityIdentifier("\(detail ? "detail" : "quota").\(id).remaining")
    }
    private var valueUsedText: String {
        guard case let .limited(percentage) = value.amount else { return "未知" }
        return percentage.used.formatted(.number.precision(.fractionLength(0...2))) + "%"
    }
}

struct DashboardButtonStyle: ButtonStyle {
    var secondary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold))
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(secondary ? DashboardStyle.text : DashboardStyle.accentText)
            .background(secondary ? DashboardStyle.elevated : DashboardStyle.accent,
                        in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// UIKit's interactive movement supplies long-press lifting, animated gaps and
/// edge auto-scrolling without a visible reorder accessory or a second edit mode.
private struct ReorderableQuotaList<Content: View>: UIViewRepresentable {
    let accounts: [ConnectedAccount]
    let canMove: Bool
    let saving: Bool
    let move: (IndexSet, Int) -> Void
    let canRefresh: Bool
    let refresh: () -> Void
    @ViewBuilder let content: (ConnectedAccount) -> Content

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICollectionView {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(215))
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 12
        section.contentInsets = .init(top: 12, leading: 16, bottom: 24, trailing: 16)
        let view = UICollectionView(frame: .zero, collectionViewLayout: QuotaReorderLayout(section: section))
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.selfSizingInvalidation = .enabledIncludingConstraints
        view.register(QuotaCollectionCell.self, forCellWithReuseIdentifier: "quota")
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        view.accessibilityIdentifier = "quota.list"
        let gesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.press(_:)))
        gesture.minimumPressDuration = 0.4
        view.addGestureRecognizer(gesture)
        context.coordinator.collection = view
        context.coordinator.pull.attach(to: view)
        view.panGestureRecognizer.addTarget(context.coordinator, action: #selector(Coordinator.panEnded(_:)))
        return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if !canRefresh || saving { coordinator.pull.cancelGesture() }
        guard !coordinator.dragging, !saving else { return }
        if coordinator.displayed != accounts {
            coordinator.displayed = accounts
            view.reloadData()
        } else {
            for index in view.indexPathsForVisibleItems {
                (view.cellForItem(at: index) as? QuotaCollectionCell)?.configure(UIHostingConfiguration {
                    content(accounts[index.item]).id(accounts[index.item].id).frame(maxHeight: .infinity, alignment: .top)
                }.margins(.all, 0))
            }
        }
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
        var parent: ReorderableQuotaList
        var displayed: [ConnectedAccount]
        var dragging = false
        weak var collection: UICollectionView?
        let pull = QuotaPullRefreshGesture()
        init(_ parent: ReorderableQuotaList) { self.parent = parent; displayed = parent.accounts }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            pull.begin(enabled: parent.canRefresh && !dragging && !parent.saving)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            pull.update(enabled: parent.canRefresh && !dragging && !parent.saving)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            let state = scrollView.panGestureRecognizer.state
            let refresh = pull.end(enabled: parent.canRefresh && !dragging && !parent.saving,
                                   cancelled: state == .cancelled || state == .failed)
            if refresh { parent.refresh() }
        }

        @objc func panEnded(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .cancelled || gesture.state == .failed { pull.cancelGesture() }
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { displayed.count }
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "quota", for: indexPath)
            let account = displayed[indexPath.item]
            (cell as? QuotaCollectionCell)?.configure(UIHostingConfiguration {
                parent.content(account).id(account.id).frame(maxHeight: .infinity, alignment: .top)
            }.margins(.all, 0))
            cell.backgroundColor = .clear
            return cell
        }
        func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool { parent.canMove }
        func collectionView(_ collectionView: UICollectionView, moveItemAt source: IndexPath, to destination: IndexPath) {
            guard source != destination else { return }
            let account = displayed.remove(at: source.item)
            displayed.insert(account, at: destination.item)
            parent.move(IndexSet(integer: source.item), destination.item > source.item ? destination.item + 1 : destination.item)
        }
        @objc func press(_ gesture: UILongPressGestureRecognizer) {
            guard let view = collection else { return }
            switch gesture.state {
            case .began:
                guard parent.canMove, let index = view.indexPathForItem(at: gesture.location(in: view)) else { return }
                pull.cancelGesture()
                (view.collectionViewLayout as? QuotaReorderLayout)?.beginMovement(at: index)
                dragging = view.beginInteractiveMovementForItem(at: index)
                if !dragging { (view.collectionViewLayout as? QuotaReorderLayout)?.finishMovement() }
                if dragging { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            case .changed:
                if dragging { view.updateInteractiveMovementTargetPosition(gesture.location(in: view)) }
            case .ended:
                if dragging { view.endInteractiveMovement() }
                dragging = false
                (view.collectionViewLayout as? QuotaReorderLayout)?.finishMovement()
                reconcileAfterMovement()
            default:
                if dragging { view.cancelInteractiveMovement() }
                dragging = false
                (view.collectionViewLayout as? QuotaReorderLayout)?.finishMovement()
                reconcileAfterMovement()
            }
        }

        private func reconcileAfterMovement() {
            // An immediate failed save may publish while the lift animation is
            // still ending. Reconcile once it releases the collection's snapshot.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, !dragging, !parent.saving, displayed != parent.accounts else { return }
                displayed = parent.accounts
                collection?.reloadData()
            }
        }
    }
}


/// Observes the existing scroll gesture without adding a recognizer or holding
/// the content inset open. The list therefore keeps its native rubber banding.
@MainActor
final class QuotaPullRefreshGesture {
    static let threshold: CGFloat = 72
    let indicator = QuotaPullIndicator()
    private weak var scrollView: UIScrollView?
    private var tracking = false
    private var didHaptic = false
    private var returning = false
    private let feedback = UIImpactFeedbackGenerator(style: .heavy)
    var onThreshold: (() -> Void)?

    func attach(to view: UIScrollView) {
        scrollView = view
        indicator.isUserInteractionEnabled = false
        indicator.isHidden = true
        indicator.isAccessibilityElement = true
        indicator.accessibilityIdentifier = "quota.pullIndicator"
        indicator.accessibilityLabel = "下拉刷新"
        view.addSubview(indicator)
    }

    func begin(enabled: Bool) {
        tracking = enabled
        returning = false
        didHaptic = false
        if enabled { feedback.prepare() }
        update(enabled: enabled)
    }

    private var distance: CGFloat {
        guard let scrollView else { return 0 }
        return max(0, -(scrollView.contentOffset.y + scrollView.adjustedContentInset.top))
    }

    func update(enabled: Bool) {
        if tracking && !enabled { cancelGesture() }
        let distance = distance
        if tracking && distance > Self.threshold && !didHaptic {
            didHaptic = true
            if let onThreshold { onThreshold() }
            else { feedback.impactOccurred() }
        }
        if distance <= 0 { returning = false }
        indicator.isHidden = !(tracking || returning) || distance < 4
        guard !indicator.isHidden, let scrollView else { return }
        let progress = min(1, distance / Self.threshold)
        let diameter = 22 * (0.3 + 0.7 * progress)
        // Content coordinates: the indicator stays centered in the pulled gap.
        indicator.frame = CGRect(x: scrollView.bounds.midX - diameter / 2,
                                 y: -scrollView.adjustedContentInset.top - distance / 2 - diameter / 2,
                                 width: diameter, height: diameter)
        indicator.alpha = min(1, distance / 20)
        indicator.accessibilityValue = tracking && distance > Self.threshold ? "松手刷新" : "继续下拉"
        indicator.setNeedsDisplay()
    }

    func end(enabled: Bool, cancelled: Bool = false) -> Bool {
        let shouldRefresh = tracking && enabled && !cancelled && distance > Self.threshold
        returning = tracking && !cancelled
        tracking = false
        update(enabled: enabled)
        return shouldRefresh
    }

    func cancelGesture() {
        tracking = false
        // After a valid release the existing bounce retracts the indicator,
        // even when the refresh immediately disables further gestures.
        if !returning { indicator.isHidden = true }
    }
}

/// Static spokes, visually matching the card spinner, with no rotation animation.
final class QuotaPullIndicator: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let radius = min(bounds.width, bounds.height) / 2
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.setLineCap(.round)
        context.setLineWidth(radius * 0.22)
        for index in 0..<8 {
            context.saveGState()
            context.rotate(by: CGFloat(index) * .pi / 4)
            context.setStrokeColor(UIColor.secondaryLabel.withAlphaComponent(0.35 + Double(index) * 0.08).cgColor)
            context.move(to: CGPoint(x: 0, y: -radius * 0.48))
            context.addLine(to: CGPoint(x: 0, y: -radius * 0.84))
            context.strokePath()
            context.restoreGState()
        }
    }
}

/// The hosted view keeps its intrinsic height and is pinned only to the top.
/// Pinning it to both vertical edges lets intermediate cell sizes compress or
/// recenter SwiftUI content while UICollectionView animates a self-sizing row.
private final class QuotaCollectionCell: UICollectionViewCell {
    private var hostedContent: (UIView & UIContentView)?

    func configure(_ configuration: any UIContentConfiguration) {
        contentView.clipsToBounds = true
        contentView.layer.cornerRadius = 24
        if let hostedContent {
            hostedContent.configuration = configuration
        } else {
            let hosted = configuration.makeContentView()
            hosted.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(hosted)
            NSLayoutConstraint.activate([
                hosted.topAnchor.constraint(equalTo: contentView.topAnchor),
                hosted.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hosted.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
            ])
            hostedContent = hosted
        }
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        guard let hostedContent,
              let result = layoutAttributes.copy() as? UICollectionViewLayoutAttributes else { return layoutAttributes }
        let size = hostedContent.systemLayoutSizeFitting(
            CGSize(width: layoutAttributes.size.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        let scale = traitCollection.displayScale
        result.size.height = ceil(size.height * scale) / scale
        return result
    }
}

/// Keep crossing boundaries in content coordinates for the whole gesture. Using
/// the newly displaced cell frames makes unequal-height cards swap back and forth.
struct QuotaReorderPosition {
    let source: Int
    let centers: [CGFloat]
    private(set) var destination: Int
    private let margin: CGFloat = 6

    init(source: Int, centers: [CGFloat]) {
        self.source = source
        self.centers = centers
        self.destination = source
    }

    mutating func update(y: CGFloat) -> Int {
        guard y.isFinite, centers.indices.contains(source) else { return destination }
        while destination < centers.count - 1 {
            let boundary = centers[destination < source ? destination : destination + 1]
            guard y > boundary + margin else { break }
            destination += 1
        }
        while destination > 0 {
            let boundary = centers[destination > source ? destination : destination - 1]
            guard y < boundary - margin else { break }
            destination -= 1
        }
        return destination
    }
}

final class QuotaReorderLayout: UICollectionViewCompositionalLayout {
    private(set) var movement: QuotaReorderPosition?

    func beginMovement(at index: IndexPath) {
        guard let collectionView, index.section == 0 else { return }
        let count = collectionView.numberOfItems(inSection: 0)
        let centers = (0..<count).compactMap {
            layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.center.y
        }
        guard centers.count == count, centers.indices.contains(index.item) else { return }
        movement = QuotaReorderPosition(source: index.item, centers: centers)
    }

    func finishMovement() { movement = nil }

    override func targetIndexPath(forInteractivelyMovingItem previousIndexPath: IndexPath,
                                  withPosition position: CGPoint) -> IndexPath {
        guard movement != nil else { return previousIndexPath }
        let destination = movement!.update(y: position.y)
        return IndexPath(item: destination, section: previousIndexPath.section)
    }
}

/// A sheet follows one identity, never a copied row or an array position.
struct CodexDetailTarget: Identifiable, Equatable {
    let id: UUID
    private let email: String?
    private let remoteUserID: String?

    init?(_ account: ConnectedAccount) {
        guard account.provider == .openAI, account.product == .codexSubscription,
              account.deletionPending != true else { return nil }
        id = account.id
        email = account.verifiedEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        remoteUserID = account.remoteUserID
    }

    func resolve(in accounts: [ConnectedAccount]) -> ConnectedAccount? {
        accounts.first {
            $0.id == id && $0.deletionPending != true && $0.provider == .openAI
                && $0.product == .codexSubscription
                && $0.verifiedEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == email
                && $0.remoteUserID == remoteUserID
        }
    }
}

/// Display only the established, account-bound observation contract. Other
/// supplemental usage fields have no verified persisted contract in this release.
struct CodexDetailContent {
    struct Row: Equatable, Identifiable {
        let id: String
        let title: String
        let value: String
    }
    let snapshot: CodexQuotaSnapshot?
    let rows: [Row]

    init(account: ConnectedAccount) {
        let candidate = account.quotaSnapshot
        snapshot = candidate.flatMap {
            guard account.quotaState == .available, $0.accountID == account.id,
                  $0.provider == account.provider, $0.product == account.product,
                  $0.scope == account.scope, $0.generation == account.generation,
                  $0.observedAt.timeIntervalSince1970.isFinite,
                  $0.observedAt.timeIntervalSince1970 > 0 else { return nil }
            return $0
        }
        var values: [Row] = [Row(id: "identity", title: "账号",
            value: account.verifiedEmail ?? account.remoteUserID ?? "Codex 账户")]
        if let subscription = account.subscription, subscription.isValid {
            values.append(Row(id: "plan", title: "套餐", value: subscription.planType))
        }
        let count = account.subscription.flatMap { subscription -> Int64? in
            guard subscription.isValid, let count = subscription.resetCardCount, count >= 0 else { return nil }
            return count
        } ?? 0
        values.append(Row(id: "resetCards", title: "重置额度", value: String(count)))
        if let snapshot {
            values.append(Row(id: "updatedAt", title: "更新时间", value: QuotaView.dateText(snapshot.observedAt)))
        }
        rows = values
    }
}

struct CodexDetailPanel: View {
    let account: ConnectedAccount
    var updating = false
    var failure: String?
    var canManage = true
    var refresh: () -> Void = {}
    var closeFeedback: () -> Void = {}
    var delete: () -> Void = {}
    var close: () -> Void = {}
    @State private var confirmingDeletion = false
    private var content: CodexDetailContent { CodexDetailContent(account: account) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: close) {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .accessibilityLabel("关闭详情").accessibilityIdentifier("detail.close")
                Spacer(minLength: 0)
                Button(action: refresh) {
                    ZStack {
                        if updating { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.clockwise") }
                    }.frame(width: 44, height: 44)
                }
                .disabled(!canManage || updating)
                .accessibilityLabel(updating ? "正在刷新" : "刷新当前账户")
                .accessibilityIdentifier("detail.refresh")
                Menu {
                    Button("刷新额度", systemImage: "arrow.clockwise", action: refresh).disabled(updating)
                    Button("删除账户", systemImage: "trash", role: .destructive) { confirmingDeletion = true }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }
                .disabled(!canManage)
                .accessibilityLabel("账户操作").accessibilityIdentifier("detail.menu")
            }
            .overlay { Text("Codex").font(.system(size: 20, weight: .semibold)).accessibilityAddTraits(.isHeader).allowsHitTesting(false) }
            .font(.system(size: 20))
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            .buttonStyle(.plain).padding(.horizontal, 12).padding(.top, 10)
            if let failure {
                HStack(spacing: 12) {
                    Text(failure).font(.subheadline).accessibilityIdentifier("detail.failure")
                    Spacer(minLength: 0)
                    Button("重试", action: refresh).disabled(!canManage || updating)
                        .accessibilityIdentifier("detail.retry")
                    Button(action: closeFeedback) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("关闭提示")
                }
                .buttonStyle(.plain).padding(.leading, 12)
                .background(DashboardStyle.elevated, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if account.isDemo {
                        Text("演示").font(.caption).foregroundStyle(DashboardStyle.secondary)
                    }
                    if let snapshot = content.snapshot {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            VStack(alignment: .leading, spacing: 16) {
                                if snapshot.fiveHours.shouldDisplay {
                                    detailWindow(snapshot.fiveHours, title: "5 小时", id: "fiveHours", now: context.date)
                                }
                                detailWindow(snapshot.weekly, title: "每周", id: "weekly", now: context.date)
                            }
                        }
                    } else if account.quotaState != .notApplicable {
                        Text(failure == nil ? "尚未获取额度" : "获取失败")
                            .foregroundStyle(DashboardStyle.secondary)
                            .accessibilityIdentifier("detail.status")
                    }
                    if !content.rows.isEmpty {
                        Text("详情").font(.subheadline).foregroundStyle(DashboardStyle.secondary).padding(.leading, 16)
                        VStack(spacing: 0) {
                            ForEach(content.rows) { row in
                                if row.id != content.rows.first?.id { Divider() }
                                ViewThatFits(in: .horizontal) {
                                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                                        Text(row.title).foregroundStyle(DashboardStyle.secondary)
                                        Spacer(minLength: 0)
                                        Text(row.value).multilineTextAlignment(.trailing)
                                    }
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(row.title).foregroundStyle(DashboardStyle.secondary)
                                        Text(row.value)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.subheadline).padding(.vertical, 16)
                                .fixedSize(horizontal: false, vertical: true)
                                .privacySensitive(row.id == "identity")
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(row.id == "identity" ? row.value : "\(row.title)，\(row.value)")
                                .accessibilityIdentifier(row.id == "updatedAt" ? "quota.updatedAt" : "detail.\(row.id)")
                            }
                        }
                        .padding(.horizontal, 16)
                        .background(DashboardStyle.card, in: RoundedRectangle(cornerRadius: 22))
                    }
                }
                .padding(16).padding(.bottom, 20)
            }
            .clipped()
        }
        .foregroundStyle(DashboardStyle.text)
        .background(DashboardStyle.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.panel")
        .alert("删除账户？", isPresented: $confirmingDeletion) {
            Button("取消", role: .cancel) { }
            Button("删除账户", role: .destructive, action: delete)
        } message: { Text("仅断开本 App 的连接，不会取消订阅。") }
    }

    private func detailWindow(_ value: QuotaWindowSnapshot, title: String, id: String, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            QuotaWindowView(value: value, title: title, id: id, now: now, detail: true)
        }
        .padding(.horizontal, 20).padding(.vertical, 17.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardStyle.card, in: RoundedRectangle(cornerRadius: 30))
    }
}
