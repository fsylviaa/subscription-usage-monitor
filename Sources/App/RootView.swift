import SwiftUI

struct RootView: View {
    @StateObject private var connection: CodexConnectionFlow

    init(connection: CodexConnectionFlow = CodexConnectionFlow()) {
        _connection = StateObject(wrappedValue: connection)
    }

    private var connectionDetents: Set<PresentationDetent> {
        if case .code = connection.state { return [.large] }
        return [.medium]
    }

    var body: some View {
        TabView {
            NavigationStack {
                QuotaView(connect: { connection.begin() })
            }
            .tabItem {
                Label("额度", systemImage: "chart.bar")
            }

            NavigationStack {
                SettingsView(connect: { connection.begin() })
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
        }
        .sheet(isPresented: $connection.isPresented, onDismiss: { connection.cancel() }) {
            CodexConnectionView(flow: connection)
                .presentationDetents(connectionDetents)
        }
    }
}
