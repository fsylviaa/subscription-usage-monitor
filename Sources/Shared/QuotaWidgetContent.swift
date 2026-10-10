import Foundation
import SwiftUI

/// The extension consumes only the validated display snapshot, never a login or query service.
enum QuotaWidgetContent: Equatable, Sendable {
    case snapshot(WidgetSnapshot)
    case notPublished
    case unavailable

    static func read(from store: WidgetSnapshotStore) -> Self {
        do {
            guard let snapshot = try store.read() else { return .notPublished }
            return .snapshot(snapshot)
        } catch { return .unavailable }
    }

    var account: WidgetSnapshot.Account? {
        guard case let .snapshot(snapshot) = self else { return nil }
        return snapshot.account
    }

    var message: String? {
        switch self {
        case .notPublished: "尚未获取额度"
        case .unavailable: "刷新失败"
        case let .snapshot(snapshot): snapshot.emptyMessage
        }
    }

    static func amountText(_ amount: WidgetSnapshot.Amount) -> String {
        switch amount {
        case .unknown: "未知"
        case .unlimited: "不限量"
        case let .limited(used): "剩余 \((100 - used).formatted(.number.precision(.fractionLength(0...2))))%"
        }
    }

    static func usedFraction(_ amount: WidgetSnapshot.Amount) -> Double? {
        guard case let .limited(used) = amount else { return nil }
        return used / 100
    }

    /// Absolute times remain truthful even when iOS keeps an older rendered timeline.
    static func resetText(_ date: Date?) -> String {
        guard let date else { return "未提供重置时间" }
        return "重置 \(timestamp(date))"
    }

    static func timestamp(_ date: Date) -> String {
        date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
    }
}

/// Also compiled into the app for isolated rendering tests; no product preview page.
struct SmallQuotaWidgetView: View {
    let content: QuotaWidgetContent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let account = content.account {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.identity)
                        .font(.system(size: 11, weight: .medium))
                        .truncationMode(.middle)
                    HStack(spacing: 4) {
                        Image("DesignCodex").resizable().renderingMode(.template)
                            .frame(width: 11, height: 11).accessibilityHidden(true)
                        Text(account.plan.map { "Codex · \($0)" } ?? "Codex")
                            .font(.system(size: 10))
                        if account.isDemo {
                            Text("演示").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                }
                if account.state == .available {
                    window("每周", value: account.weekly)
                    window("5 小时", value: account.fiveHours)
                    if let date = account.quotaObservedAt {
                        Text("更新 \(QuotaWidgetContent.timestamp(date))")
                            .font(.system(size: 9)).foregroundStyle(Color("DesignSecondary"))
                            .accessibilityLabel("最后成功更新 \(QuotaWidgetContent.timestamp(date))")
                    }
                }
            } else {
                HStack(spacing: 4) {
                    Image("DesignCodex").resizable().renderingMode(.template)
                        .frame(width: 13, height: 13).accessibilityHidden(true)
                    Text("Codex").font(.system(size: 12, weight: .medium))
                }
            }
            if let message = content.message {
                Spacer(minLength: 0)
                Text(message).font(.system(size: 12)).foregroundStyle(Color("DesignSecondary"))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .foregroundStyle(Color("DesignText"))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }

    private func window(_ title: String, value: WidgetSnapshot.Window?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text(title).font(.system(size: 11, weight: .medium)).fixedSize()
                Spacer(minLength: 0)
                Text(QuotaWidgetContent.amountText(value?.amount ?? .unknown))
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    .layoutPriority(1)
            }
            if let fraction = QuotaWidgetContent.usedFraction(value?.amount ?? .unknown) {
                GeometryReader { geometry in
                    Capsule().fill(Color("DesignTrack"))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color("DesignText"))
                                .frame(width: geometry.size.width * fraction)
                        }
                }
                .frame(height: 4)
                .accessibilityLabel("\(title)额度条")
                .accessibilityValue("已用 \((fraction * 100).formatted(.number.precision(.fractionLength(0...2))))%，\(QuotaWidgetContent.amountText(value?.amount ?? .unknown))")
            }
            Text(QuotaWidgetContent.resetText(value?.resetsAt))
                .font(.system(size: 9)).foregroundStyle(Color("DesignSecondary"))
        }
        .accessibilityElement(children: .combine)
    }
}
