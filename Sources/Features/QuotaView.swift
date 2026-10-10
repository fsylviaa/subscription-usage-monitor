import SwiftUI

struct QuotaView: View {
    var body: some View {
        ContentUnavailableView {
            Label("未连接账户", systemImage: "link")
                .accessibilityIdentifier("quota.empty")
        } actions: {
            Button {
                // T07 接入网络检查与真实登录后开放。
            } label: {
                Text("连接 Codex")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(true)
            .accessibilityIdentifier("quota.connect")
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
                    // T07 接入网络检查与真实登录后开放。
                }
                .disabled(true)
                .accessibilityIdentifier("quota.toolbarConnect")
            }
        }
    }
}
