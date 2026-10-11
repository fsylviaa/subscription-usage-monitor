import Foundation
import UserNotifications
import XCTest
@testable import SubscriptionUsage

/// Tests only construct/inspect notification objects. No system center is used.
final class ResetReminderNotificationTests: XCTestCase {
    @MainActor
    func testCalendarRequestUsesExactUTCInstantAndDoesNotRepeat() throws {
        let planned = request(at: 1_800_000_000)
        let native = SystemResetReminderNotificationCenter.makeRequest(planned)
        let trigger = try XCTUnwrap(native.trigger as? UNCalendarNotificationTrigger)
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.timeZone?.secondsFromGMT(), 0)
        XCTAssertEqual(SystemResetReminderNotificationCenter.decode(native), planned)
        XCTAssertNotNil(native.content.sound)
        XCTAssertNil(native.content.badge)
    }

    @MainActor
    func testFractionalResetIsRoundedUpByLessThanOneSecond() throws {
        let planned = request(at: 1_800_000_000.25)
        let actual = try XCTUnwrap(SystemResetReminderNotificationCenter.decode(
            SystemResetReminderNotificationCenter.makeRequest(planned)))
        XCTAssertEqual(actual.resetsAt.timeIntervalSince1970, 1_800_000_001)
        XCTAssertEqual(actual.identifier, planned.identifier)
    }

    @MainActor
    func testReadbackUsesActualTriggerAndContentInsteadOfIntendedMetadata() throws {
        let planned = request(at: 1_800_000_000)
        let original = SystemResetReminderNotificationCenter.makeRequest(planned)
        let content = try XCTUnwrap(original.content.mutableCopy() as? UNMutableNotificationContent)
        content.body = "实际中心返回的内容"
        content.userInfo["resetsAt"] = planned.resetsAt.timeIntervalSince1970
        let changedTime = SystemResetReminderNotificationCenter.makeRequest(request(at: 1_800_001_000))
        let changed = UNNotificationRequest(identifier: original.identifier, content: content, trigger: changedTime.trigger)
        let result = try XCTUnwrap(SystemResetReminderNotificationCenter.decode(changed))
        XCTAssertEqual(result.resetsAt.timeIntervalSince1970, 1_800_001_000)
        XCTAssertEqual(result.body, content.body)
    }

    @MainActor
    func testUnrelatedMalformedAndRepeatingNotificationsAreNotAcceptedAsQuotaEvidence() throws {
        let native = SystemResetReminderNotificationCenter.makeRequest(request(at: 1_800_000_000))
        XCTAssertNil(SystemResetReminderNotificationCenter.decode(UNNotificationRequest(
            identifier: "another-feature", content: native.content, trigger: native.trigger)))
        XCTAssertNil(SystemResetReminderNotificationCenter.decode(UNNotificationRequest(
            identifier: native.identifier, content: UNMutableNotificationContent(), trigger: native.trigger)))
        let trigger = try XCTUnwrap(native.trigger as? UNCalendarNotificationTrigger)
        XCTAssertNil(SystemResetReminderNotificationCenter.decode(UNNotificationRequest(
            identifier: native.identifier, content: native.content,
            trigger: UNCalendarNotificationTrigger(dateMatching: trigger.dateComponents, repeats: true))))
    }

    func testEveryFixtureAndTestHostDisablesSystemScheduling() {
        XCTAssertFalse(ResetReminderRuntime.permitsSystemScheduling(arguments: [], isTestHost: true))
        for argument in ["--management-ui", "--t23-card-fixture", "--t35-widget-fixture",
                         "--t30-background-debug", "--t09-live-ui", "--t39-any-future-fixture"] {
            XCTAssertFalse(ResetReminderRuntime.permitsSystemScheduling(arguments: [argument], isTestHost: false))
        }
        XCTAssertTrue(ResetReminderRuntime.permitsSystemScheduling(arguments: ["SubscriptionUsage"], isTestHost: false))
    }

    private func request(at seconds: TimeInterval) -> ResetReminderRequest {
        ResetReminderRequest(identifier: "quota-reset.v1.unit-test", accountID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            window: .weekly, resetsAt: Date(timeIntervalSince1970: seconds),
            title: "Codex · first@example.invalid", body: "周额度预计重置，打开查看")
    }
}
