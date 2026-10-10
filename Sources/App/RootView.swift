import SwiftUI

struct RootView: View {
    @StateObject private var connection: CodexConnectionFlow
    @Environment(\.scenePhase) private var scenePhase

    init(connection: CodexConnectionFlow = CodexConnectionFlow.live()) {
        _connection = StateObject(wrappedValue: connection)
    }

    private var connectionDetents: Set<PresentationDetent> {
        if case .code = connection.state { return [.large] }
        return [.medium]
    }

    var body: some View {
        TabView {
            NavigationStack {
                QuotaView(accounts: connection.accounts, loading: connection.loadingAccounts,
                          loadFailed: connection.accountLoadFailed, canConnect: connection.canConnect,
                          connect: { connection.begin() })
            }
            .tabItem {
                Label("额度", systemImage: "chart.bar")
            }

            NavigationStack {
                SettingsView(canConnect: connection.canConnect, connect: { connection.begin() })
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
        }
        .task {
            connection.setActive(scenePhase == .active)
            await connection.loadAccounts()
        }
        .onChange(of: scenePhase) { _, phase in connection.setActive(phase == .active) }
        .sheet(isPresented: $connection.isPresented, onDismiss: { connection.cancel() }) {
            CodexConnectionView(flow: connection)
                .presentationDetents(connectionDetents)
                .interactiveDismissDisabled(connection.state == .saving)
        }
    }
}
