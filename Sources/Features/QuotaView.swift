import SwiftUI

struct QuotaView: View {
    var accounts: [ConnectedAccount] = []
    var loading = false
    var loadFailed = false
    var canConnect = true
    var updatingID: UUID?
    var quotaFailure: String?
    var quotaFailureID: UUID?
    var connect: () -> Void = {}
    var retry: (UUID) -> Void = { _ in }
    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else if loadFailed {
                ContentUnavailableView("刷新失败", systemImage: "exclamationmark.circle")
            } else if !accounts.isEmpty {
                List(accounts) { account in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(account.subscription.map { "Codex · \($0.planType)" } ?? "Codex")
                            .font(.headline)
                            .accessibilityIdentifier("quota.plan")
                        Text(account.verifiedEmail ?? account.remoteUserID ?? "Codex 账户")
                            .privacySensitive()
                            .accessibilityIdentifier("quota.accountIdentity")
                        if let snapshot = account.quotaSnapshot {
                            quotaWindow(snapshot.weekly, title: "周额度", id: "weekly")
                            quotaWindow(snapshot.fiveHours, title: "5 小时额度", id: "fiveHours")
                            Text("更新于 \(Self.dateText(snapshot.observedAt))")
                                .font(.footnote).foregroundStyle(.secondary)
                                .accessibilityIdentifier("quota.updatedAt")
                        } else if account.quotaState == .notFetched && updatingID != account.id && quotaFailureID != account.id {
                            Text("尚未获取额度").foregroundStyle(.secondary)
                                .accessibilityIdentifier("quota.notFetched")
                        }
                        if updatingID == account.id {
                            ProgressView("正在更新")
                                .accessibilityIdentifier("quota.updating")
                        } else if quotaFailureID == account.id, let quotaFailure {
                            Text(quotaFailure).font(.footnote).foregroundStyle(.secondary)
                                .accessibilityIdentifier("quota.failure")
                            if account.quotaState == .notFetched {
                                Button("重试") { retry(account.id) }
                                    .buttonStyle(.bordered)
                                    .accessibilityIdentifier("quota.retry")
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            } else {
                ContentUnavailableView {
                    Label("未连接账户", systemImage: "link")
                        .accessibilityIdentifier("quota.empty")
                } actions: {
                    Button {
                        connect()
                    } label: {
                        Text("连接 Codex")
                            .foregroundStyle(Color(.systemBackground))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("quota.connect")
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("订阅额度")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("刷新", systemImage: "arrow.clockwise") {
                    // 无账户时没有查询对象；实际刷新在 T26 接入。
                }
                .disabled(true)
                .accessibilityIdentifier("quota.refresh")

                Button("连接 Codex", systemImage: "link") {
                    connect()
                }
                .accessibilityIdentifier("quota.toolbarConnect")
                .disabled(!canConnect)
            }
        }
    }

    private func quotaWindow(_ value: QuotaWindowSnapshot, title: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(Self.amountText(value.amount)).fontWeight(.semibold)
                    .accessibilityIdentifier("quota.\(id).remaining")
            }
            Text(value.resetsAt.map { "预计重置于 \(Self.dateText($0))" } ?? "未提供重置时间")
                .font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("quota.\(id).reset")
        }
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

}
