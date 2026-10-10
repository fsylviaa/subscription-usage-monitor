import SwiftUI

struct CodexConnectionView: View {
    @ObservedObject var flow: CodexConnectionFlow
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                switch flow.state {
                case .idle, .checking, .requesting, .verifying, .saving:
                    ProgressView(flow.state == .verifying || flow.state == .saving ? "正在完成登录…" : "连接中…")
                        .accessibilityIdentifier("connection.progress")
                case let .failure(message):
                    ContentUnavailableView {
                        Label(message, systemImage: "exclamationmark.circle")
                            .accessibilityIdentifier("connection.failure")
                    } actions: {
                        Button("重试", action: { flow.begin() })
                            .buttonStyle(.borderedProminent)
                            .foregroundStyle(Color(.systemBackground))
                            .accessibilityIdentifier("connection.retry")
                    }
                case let .code(authorization):
                    ScrollView {
                        VStack(spacing: 24) {
                            Image(systemName: "key.horizontal")
                                .font(.largeTitle)
                                .foregroundStyle(.tint)
                            Text("在官网输入一次性代码")
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                            Text(authorization.userCode)
                                .font(.title.monospaced().bold())
                                .multilineTextAlignment(.center)
                                .privacySensitive()
                                .accessibilityIdentifier("connection.code")
                            Button(flow.copied ? "已复制" : "复制代码", systemImage: "doc.on.doc", action: flow.copy)
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("connection.copy")
                            Button("打开官网") {
                                Task { await flow.openWebsite() }
                            }
                            .buttonStyle(.borderedProminent)
                            .foregroundStyle(Color(.systemBackground))
                            .controlSize(.large)
                            .accessibilityIdentifier("connection.open")
                            if flow.browserFailed {
                                Text("登录未完成，请重试")
                                    .foregroundStyle(.secondary)
                            }
                            Text("使用已有账户登录，完成后返回 App。")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }

                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("连接 Codex")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: flow.cancel)
                        .accessibilityIdentifier("connection.cancel")
                        .disabled(flow.state == .saving)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { flow.expireIfNeeded() }
            }
        }
    }
}
