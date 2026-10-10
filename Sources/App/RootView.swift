import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                QuotaView()
            }
            .tabItem {
                Label("额度", systemImage: "chart.bar")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
        }
    }
}
