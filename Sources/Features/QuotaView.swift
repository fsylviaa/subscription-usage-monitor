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
    var canReorder = false
    var savingOrder = false
    var move: (IndexSet, Int) -> Void = { _, _ in }
    @ScaledMetric(relativeTo: .headline) private var titleSize = 18

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("订阅额度").font(.system(size: titleSize, weight: .semibold))
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("quota.title")
                Spacer(minLength: 12)
                Button { if let id = quotaFailureID { retry(id) } } label: {
                    DesignIcon(name: "Refresh").frame(width: 44, height: 44)
                }
                // T13 permits retrying a failed first fetch. Regular refresh is T25/T26.
                .disabled(quotaFailureID == nil || updatingID != nil)
                .accessibilityLabel("刷新").accessibilityIdentifier("quota.refresh")
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
                            if updatingID != nil {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("正在更新").font(.subheadline)
                                    Spacer()
                                }
                                .padding(12).background(DashboardStyle.elevated, in: RoundedRectangle(cornerRadius: 14))
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("quota.updating")
                            } else if let quotaFailure, let id = quotaFailureID {
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
                    ReorderableQuotaList(accounts: accounts, canMove: canReorder, saving: savingOrder, move: move) { account in
                        QuotaAccountCard(account: account, updating: updatingID == account.id,
                                         failed: failedAccountIDs.contains(account.id) || quotaFailureID == account.id,
                                         canManage: canManage, canRefresh: canRefresh,
                                         refresh: { refreshAccount(account.id) }, delete: { deleting = account })
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

    static func dateText(_ date: Date) -> String {
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
    @State private var expanded = false
    @ScaledMetric(relativeTo: .headline) private var titleSize = 17
    @ScaledMetric(relativeTo: .caption2) private var emailSize = 11

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                DesignIcon(name: "Codex", size: 24.48)
                    .frame(width: 34, height: 34)
                    .background(DashboardStyle.elevated, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 1) {
                    if account.quotaSnapshot != nil {
                        Button {
                            expanded.toggle()
                        } label: {
                            planTitle
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("quota.details")
                        .accessibilityValue(expanded ? "已展开" : "已收起")
                    } else {
                        planTitle
                    }
                    if account.isDemo { Text("演示").font(.caption2).foregroundStyle(DashboardStyle.secondary) }
                    Text(account.verifiedEmail ?? account.remoteUserID ?? "Codex 账户")
                        .font(.system(size: emailSize)).foregroundStyle(DashboardStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true).privacySensitive()
                        .accessibilityIdentifier("quota.accountIdentity")
                }
                Spacer(minLength: 0)
                Menu {
                    Button("刷新额度", systemImage: "arrow.clockwise", action: refresh).disabled(!canRefresh)
                    Button("删除账户", systemImage: "trash", role: .destructive, action: delete)
                } label: {
                    Image(systemName: "ellipsis").font(.body.weight(.semibold)).frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .disabled(!canManage)
                .accessibilityLabel("账户操作").accessibilityIdentifier("quota.menu")
            }
            if let snapshot = account.quotaSnapshot {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(spacing: 10) {
                        QuotaWindowView(value: snapshot.weekly, title: "每周", id: "weekly", now: context.date)
                        QuotaWindowView(value: snapshot.fiveHours, title: "5 小时", id: "fiveHours", now: context.date)
                    }
                }
                if expanded {
                    VStack(alignment: .leading, spacing: 8) {
                        Rectangle().fill(Color("DesignLine")).frame(height: 0.5)
                        Text("更新于 \(QuotaView.dateText(snapshot.observedAt))")
                            .font(.caption).foregroundStyle(DashboardStyle.secondary)
                            .accessibilityIdentifier("quota.updatedAt")
                    }
                }
            } else if account.quotaState == .notFetched {
                Text(updating ? "正在获取额度" : (failed ? "获取失败" : "尚未获取额度"))
                    .font(.caption).foregroundStyle(DashboardStyle.secondary)
                    .accessibilityIdentifier(updating || failed ? "quota.accountStatus" : "quota.notFetched")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardStyle.card, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quota.card")
    }

    private var planTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(account.subscription.map { "Codex · \($0.planType)" } ?? "Codex")
                .font(.system(size: titleSize, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("quota.plan")
            if account.quotaSnapshot != nil {
                DesignIcon(name: expanded ? "Up" : "Down", size: 14)
            }
        }
    }
}

private struct QuotaWindowView: View {
    let value: QuotaWindowSnapshot
    let title: String
    let id: String
    let now: Date
    @ScaledMetric(relativeTo: .caption) private var labelSize = 12
    @ScaledMetric(relativeTo: .caption2) private var resetSize = 11
    @ScaledMetric(relativeTo: .headline) private var amountSize = 18

    var body: some View {
        VStack(spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) { reset; Spacer(minLength: 6); amount }
                VStack(alignment: .leading, spacing: 6) {
                    reset
                    HStack { Spacer(); amount }
                }
            }
            if case let .limited(percentage) = value.amount {
                GeometryReader { geometry in
                    Capsule().fill(DashboardStyle.track)
                        .overlay(alignment: .leading) {
                            Capsule().fill(DashboardStyle.text)
                                .frame(width: geometry.size.width * percentage.used / 100)
                        }
                }
                .frame(height: 6)
                .accessibilityElement().accessibilityLabel("\(title)额度条")
                .accessibilityValue("已用 \(valueUsedText)，\(QuotaView.amountText(value.amount))")
                .accessibilityIdentifier("quota.\(id).bar")
            }
        }
    }

    private var reset: some View {
        HStack(spacing: 5) {
            Text(title).font(.system(size: labelSize, weight: .medium)).fixedSize()
            DesignIcon(name: "Clock", size: 11)
            Text(QuotaView.resetText(value.resetsAt, now: now))
                .font(.system(size: resetSize)).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(value.resetsAt.map { "预计重置于 \(QuotaView.dateText($0))" } ?? "未提供重置时间")
                .accessibilityIdentifier("quota.\(id).reset")
        }
        .foregroundStyle(DashboardStyle.secondary)
    }

    private var amount: some View {
        Group {
            if case let .limited(percentage) = value.amount {
                (Text("剩余 ").font(.system(size: resetSize)).foregroundColor(DashboardStyle.secondary)
                 + Text("\(percentage.remaining.formatted(.number.precision(.fractionLength(0...2))))%")
                    .font(.system(size: amountSize, weight: .semibold)))
            } else {
                Text(QuotaView.amountText(value.amount)).font(.system(size: labelSize, weight: .medium))
            }
        }
        .fixedSize().monospacedDigit().accessibilityIdentifier("quota.\(id).remaining")
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
    @ViewBuilder let content: (ConnectedAccount) -> Content

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICollectionView {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(215))
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 12
        section.contentInsets = .init(top: 12, leading: 16, bottom: 24, trailing: 16)
        let view = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout(section: section))
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "quota")
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        view.accessibilityIdentifier = "quota.list"
        let gesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.press(_:)))
        gesture.minimumPressDuration = 0.4
        view.addGestureRecognizer(gesture)
        context.coordinator.collection = view
        return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard !coordinator.dragging, !saving else { return }
        if coordinator.displayed != accounts {
            coordinator.displayed = accounts
            view.reloadData()
        } else {
            for index in view.indexPathsForVisibleItems {
                view.cellForItem(at: index)?.contentConfiguration = UIHostingConfiguration {
                    content(accounts[index.item])
                }.margins(.all, 0)
            }
        }
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
        var parent: ReorderableQuotaList
        var displayed: [ConnectedAccount]
        var dragging = false
        weak var collection: UICollectionView?
        init(_ parent: ReorderableQuotaList) { self.parent = parent; displayed = parent.accounts }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { displayed.count }
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "quota", for: indexPath)
            let account = displayed[indexPath.item]
            cell.contentConfiguration = UIHostingConfiguration { parent.content(account) }.margins(.all, 0)
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
                dragging = view.beginInteractiveMovementForItem(at: index)
                if dragging { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            case .changed:
                if dragging { view.updateInteractiveMovementTargetPosition(gesture.location(in: view)) }
            case .ended:
                if dragging { view.endInteractiveMovement() }
                dragging = false
                reconcileAfterMovement()
            default:
                if dragging { view.cancelInteractiveMovement() }
                dragging = false
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
