import SwiftUI

struct QuotaView: View {
    var accounts: [ConnectedAccount] = []
    var loading = false
    var loadFailed = false
    var canConnect = true
    var connect: () -> Void = {}
    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else if loadFailed {
                ContentUnavailableView("刷新失败", systemImage: "exclamationmark.circle")
            } else if !accounts.isEmpty {
                List(accounts) { account in
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Codex").font(.headline)
                        Text(account.verifiedEmail ?? account.remoteUserID ?? "Codex 账户")
                            .privacySensitive()
                            .accessibilityIdentifier("quota.accountIdentity")
                        Text("尚未获取额度").foregroundStyle(.secondary)
                            .accessibilityIdentifier("quota.notFetched")
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
}
