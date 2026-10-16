import Foundation
import SwiftUI
import WidgetKit

/// Only this key is written. Quota, credentials, appearance and instance account
/// selection continue to use their existing independent storage.
enum QuotaCardStylePreferences {
    static let key = "card.style"

    static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: WidgetSnapshotStore.appGroupIdentifier)
    }

    static func read(from defaults: UserDefaults?) -> QuotaCardStyle {
        QuotaCardStyle.resolve(defaults?.string(forKey: key))
    }

    static func effectiveValue() -> QuotaCardStyle {
        #if DEBUG
        if let value = validationValue(filename: "T78-style") { return QuotaCardStyle.resolve(value) }
        #endif
        return read(from: sharedDefaults())
    }

    #if DEBUG
    static func validationValue(filename: String) -> String? {
        let store = WidgetSnapshotStore.displayStore()
        guard let url = try? store.resolvedURL(), url != (try? WidgetSnapshotStore.appGroupStore().resolvedURL()) else { return nil }
        return try? String(contentsOf: url.deletingLastPathComponent().appendingPathComponent(filename), encoding: .utf8)
    }
    /// Only the explicit synthetic display directory is eligible. Production
    /// preferences and system Intent.account are outside this namespace.
    static func publishValidation(filename: String, value: String) -> Bool {
        let store = WidgetSnapshotStore.displayStore()
        guard let url = try? store.resolvedURL(), url != (try? WidgetSnapshotStore.appGroupStore().resolvedURL()) else { return false }
        do {
            let file = url.deletingLastPathComponent().appendingPathComponent(filename)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? String(contentsOf: file, encoding: .utf8)) != value {
                try Data(value.utf8).write(to: file, options: .atomic)
                WidgetSnapshotStore.traceValidation("display.preference", detail: "\(filename)=\(value)")
                requestWidgetUpdate()
            }
        } catch { print("T78 isolated preference publication failed") }
        return true
    }
    #endif

    static func save(_ style: QuotaCardStyle, to preferences: UserDefaults,
                     shared: UserDefaults?, reload: () -> Void) {
        if preferences.string(forKey: key) != style.rawValue {
            preferences.set(style.rawValue, forKey: key)
        }
        publish(style, to: shared, reload: reload)
    }

    static func publish(_ style: QuotaCardStyle, to shared: UserDefaults?, reload: () -> Void) {
        guard let shared, shared.string(forKey: key) != style.rawValue else { return }
        shared.set(style.rawValue, forKey: key)
        reload()
    }

    static func requestWidgetUpdate() {
        #if DEBUG
        if validationValue(filename: "T78-style") != nil {
            let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("T78-stage3-reloads.json")
            var records = (try? JSONDecoder().decode([[String:String]].self, from: Data(contentsOf: file))) ?? []
            records.append(["apiRequestUTC":Date().ISO8601Format(), "style":effectiveValue().rawValue, "appearance":WidgetAppearance.effectiveValue()])
            try? JSONEncoder().encode(records).write(to:file,options:.atomic)
        }
        #endif
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetAppearance.kind)
    }
}

private struct QuotaCardStyleEnvironmentKey: EnvironmentKey {
    static let defaultValue = QuotaCardStyle.defaultStyle
}

extension EnvironmentValues {
    var quotaCardStyle: QuotaCardStyle {
        get { self[QuotaCardStyleEnvironmentKey.self] }
        set { self[QuotaCardStyleEnvironmentKey.self] = newValue }
    }
}
