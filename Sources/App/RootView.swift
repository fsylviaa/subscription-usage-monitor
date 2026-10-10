import SwiftUI

struct RootView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.system(size: 44, weight: .light))
                .accessibilityHidden(true)

            Text("订阅用量")
                .font(.largeTitle.bold())
                .accessibilityIdentifier("shell.title")

            Text("Codex 订阅额度")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
