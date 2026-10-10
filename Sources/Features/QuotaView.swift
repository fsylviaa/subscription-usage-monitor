import SwiftUI

struct QuotaView: View {
    var connect: () -> Void = {}
    var body: some View {
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
            }
        }
    }
}
