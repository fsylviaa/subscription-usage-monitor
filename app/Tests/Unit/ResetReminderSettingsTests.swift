import Foundation
import XCTest
@testable import SubscriptionUsage

final class ResetReminderSettingsTests: XCTestCase {
    @MainActor
    func testNewPreferenceIsOffAndInitializationDoesNotReadOrRequestPermission() throws {
        let (model, service, _) = try fixture()
        XCTAssertFalse(model.wantsReminders)
        XCTAssertFalse(model.isEnabled)
        XCTAssertEqual(model.authorizationStatus, .unknown)
        XCTAssertFalse(model.showsSystemSettings)
        XCTAssertEqual(service.readCount, 0)
        XCTAssertEqual(service.requestCount, 0)
    }

    @MainActor
    func testSavedIntentAndForegroundReadsNeverRequestPermission() async throws {
        let (model, service, _) = try fixture(saved: true)
        XCTAssertTrue(model.wantsReminders)
        XCTAssertFalse(model.isEnabled)
        await model.refreshAuthorization()
        await model.refreshAuthorization()
        XCTAssertFalse(model.isEnabled)
        XCTAssertEqual(model.authorizationStatus, .notDetermined)
        XCTAssertEqual(service.requestCount, 0)
    }

    @MainActor
    func testExplicitEnableRequestsOnceThenConfirmsActualPermissionAndPersists() async throws {
        let (model, service, defaults) = try fixture()
        await model.setEnabled(true)
        XCTAssertEqual(service.requestCount, 1)
        XCTAssertEqual(service.readCount, 2)
        XCTAssertTrue(model.isEnabled)
        XCTAssertTrue(defaults.bool(forKey: ResetReminderSettings.preferenceKey))
        let reopened = ResetReminderSettings(defaults: defaults, authorizationService: service)
        XCTAssertTrue(reopened.wantsReminders)
        XCTAssertFalse(reopened.isEnabled, "重开后未读取系统权限时不能声称已开启")
        await reopened.refreshAuthorization()
        XCTAssertTrue(reopened.isEnabled)
        XCTAssertEqual(service.requestCount, 1)
    }

    @MainActor
    func testDenialKeepsIntentAndSettingsEntryWithoutRequestingAgain() async throws {
        let (model, service, defaults) = try fixture()
        service.requestedStatus = .denied
        await model.setEnabled(true)
        for _ in 0..<3 {
            await model.refreshAuthorization()
            await model.setEnabled(true)
        }
        XCTAssertFalse(model.isEnabled)
        XCTAssertTrue(model.wantsReminders)
        XCTAssertTrue(defaults.bool(forKey: ResetReminderSettings.preferenceKey))
        XCTAssertTrue(model.showsSystemSettings)
        XCTAssertEqual(service.requestCount, 1)
    }

    @MainActor
    func testSystemSettingsRoundTripReflectsPermissionAndPreservesIntent() async throws {
        let (model, service, _) = try fixture(saved: true, status: .denied)
        await model.refreshAuthorization()
        XCTAssertFalse(model.isEnabled)
        XCTAssertTrue(model.showsSystemSettings)
        service.status = .authorized
        await model.refreshAuthorization()
        XCTAssertTrue(model.isEnabled)
        XCTAssertFalse(model.showsSystemSettings)
        service.status = .denied
        await model.refreshAuthorization()
        XCTAssertFalse(model.isEnabled)
        XCTAssertTrue(model.showsSystemSettings)
        XCTAssertTrue(model.wantsReminders)
        XCTAssertEqual(service.requestCount, 0)
    }

    @MainActor
    func testExistingPermissionAloneDoesNotTurnOnReminders() async throws {
        let (model, service, _) = try fixture(status: .authorized)
        await model.refreshAuthorization()
        XCTAssertFalse(model.isEnabled)
        await model.setEnabled(true)
        XCTAssertTrue(model.isEnabled)
        XCTAssertEqual(service.requestCount, 0)
    }

    @MainActor
    func testAllPermittedStatusesEnableWithoutAnotherRequest() async throws {
        for status: ResetReminderAuthorizationStatus in [.authorized, .provisional, .ephemeral] {
            let (model, service, _) = try fixture(saved: true, status: status)
            await model.refreshAuthorization()
            XCTAssertTrue(model.isEnabled, "许可状态：\(status)")
            await model.setEnabled(true)
            XCTAssertTrue(model.isEnabled)
            XCTAssertEqual(service.requestCount, 0)
        }
    }

    @MainActor
    func testUnknownPermissionNeverEnablesOrRequests() async throws {
        let (model, service, _) = try fixture(saved: true, status: .unknown)
        await model.refreshAuthorization()
        await model.setEnabled(true)
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(model.showsSystemSettings)
        XCTAssertEqual(service.requestCount, 0)
    }

    @MainActor
    func testDisableClearsIntentAndRemainsOffAcrossRestartAndPermissionChanges() async throws {
        let (model, service, defaults) = try fixture(saved: true, status: .authorized)
        await model.refreshAuthorization()
        XCTAssertTrue(model.isEnabled)
        await model.setEnabled(false)
        XCTAssertFalse(model.wantsReminders)
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(defaults.bool(forKey: ResetReminderSettings.preferenceKey))
        let reopened = ResetReminderSettings(defaults: defaults, authorizationService: service)
        for status: ResetReminderAuthorizationStatus in [.denied, .authorized] {
            service.status = status
            await reopened.refreshAuthorization()
            XCTAssertFalse(reopened.isEnabled)
            XCTAssertFalse(reopened.showsSystemSettings)
        }
        XCTAssertEqual(service.requestCount, 0)
    }

    @MainActor
    func testRequestCompletionDoesNotFabricateAuthorization() async throws {
        let (model, service, _) = try fixture()
        service.requestedStatus = .notDetermined
        await model.setEnabled(true)
        XCTAssertFalse(model.isEnabled)
        XCTAssertEqual(model.authorizationStatus, .notDetermined)
        XCTAssertEqual(service.readCount, 2)
    }

    @MainActor
    func testReadFailureClearsPreviouslyConfirmedPermissionWithoutRequesting() async throws {
        let (model, service, _) = try fixture(saved: true, status: .authorized)
        await model.refreshAuthorization()
        XCTAssertTrue(model.isEnabled)
        service.readError = TestError.failed
        await model.refreshAuthorization()
        XCTAssertFalse(model.isEnabled)
        XCTAssertEqual(model.authorizationStatus, .unknown)
        XCTAssertTrue(model.hasError)
        XCTAssertFalse(model.isRefreshing)
        await model.setEnabled(true)
        XCTAssertEqual(service.requestCount, 0)
        service.readError = nil
        await model.refreshAuthorization()
        XCTAssertTrue(model.isEnabled)
        XCTAssertFalse(model.hasError)
    }

    @MainActor
    func testRequestFailureKeepsReminderOffAndCanRecoverFromActualSettings() async throws {
        let (model, service, _) = try fixture()
        service.requestError = TestError.failed
        await model.setEnabled(true)
        XCTAssertFalse(model.isEnabled)
        XCTAssertTrue(model.wantsReminders)
        XCTAssertEqual(model.authorizationStatus, .unknown)
        XCTAssertTrue(model.hasError)
        XCTAssertFalse(model.isRequestingAuthorization)
        service.status = .authorized
        await model.refreshAuthorization()
        XCTAssertTrue(model.isEnabled)
        XCTAssertFalse(model.hasError)
        XCTAssertEqual(service.requestCount, 1)
    }

    @MainActor
    func testRefreshingDoesNotPresentOldPermissionAsCurrentlyConfirmed() async throws {
        let (model, service, _) = try fixture(saved: true, status: .authorized)
        await model.refreshAuthorization()
        XCTAssertTrue(model.isEnabled)
        service.suspendReads = true
        let refresh = Task { await model.refreshAuthorization() }
        await service.waitForReads(2)
        XCTAssertTrue(model.isRefreshing)
        XCTAssertFalse(model.isEnabled)
        service.finishRead(2, status: .denied)
        await refresh.value
        XCTAssertFalse(model.isRefreshing)
        XCTAssertFalse(model.isEnabled)
        XCTAssertTrue(model.showsSystemSettings)
    }

    @MainActor
    func testOlderPermissionReadCannotOverwriteMoreRecentResult() async throws {
        let (model, service, _) = try fixture(saved: true)
        service.suspendReads = true
        let oldRead = Task { await model.refreshAuthorization() }
        await service.waitForReads(1)
        let newRead = Task { await model.refreshAuthorization() }
        await service.waitForReads(2)
        service.finishRead(2, status: .denied)
        await newRead.value
        service.finishRead(1, status: .authorized)
        await oldRead.value
        XCTAssertEqual(model.authorizationStatus, .denied)
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertTrue(model.showsSystemSettings)
    }

    @MainActor
    func testOlderReadFailureCannotEraseNewPermission() async throws {
        let (model, service, _) = try fixture(saved: true)
        service.suspendReads = true
        let oldRead = Task { await model.refreshAuthorization() }
        await service.waitForReads(1)
        let newRead = Task { await model.refreshAuthorization() }
        await service.waitForReads(2)
        service.finishRead(2, status: .authorized)
        await newRead.value
        service.failRead(1)
        await oldRead.value
        XCTAssertTrue(model.isEnabled)
        XCTAssertFalse(model.hasError)
    }

    @MainActor
    func testRepeatedEnableDuringRequestIsCoalesced() async throws {
        let (model, service, _) = try fixture()
        service.suspendRequests = true
        let first = Task { await model.setEnabled(true) }
        await service.waitForRequests(1)
        let secondStarted = TaskStartSignal()
        let second = Task {
            secondStarted.signal()
            await model.setEnabled(true)
        }
        await secondStarted.wait()
        XCTAssertTrue(model.isRequestingAuthorization)
        XCTAssertFalse(model.isEnabled)
        XCTAssertEqual(service.requestCount, 1)
        XCTAssertEqual(service.readCount, 1)
        service.finishRequest(status: .authorized)
        await first.value
        await second.value
        XCTAssertEqual(service.requestCount, 1)
        XCTAssertTrue(model.isEnabled)
        XCTAssertFalse(model.isRequestingAuthorization)
    }

    @MainActor
    func testDisableDuringInitialReadPreventsPermissionPrompt() async throws {
        let (model, service, defaults) = try fixture()
        service.suspendReads = true
        let enable = Task { await model.setEnabled(true) }
        await service.waitForReads(1)
        await model.setEnabled(false)
        service.finishRead(1, status: .notDetermined)
        await enable.value
        XCTAssertEqual(service.requestCount, 0)
        XCTAssertFalse(model.wantsReminders)
        XCTAssertFalse(defaults.bool(forKey: ResetReminderSettings.preferenceKey))
    }

    @MainActor
    func testDisableDuringSystemRequestWinsOverLateGrant() async throws {
        let (model, service, defaults) = try fixture()
        service.suspendRequests = true
        let enable = Task { await model.setEnabled(true) }
        await service.waitForRequests(1)
        await model.setEnabled(false)
        service.finishRequest(status: .authorized)
        await enable.value
        XCTAssertEqual(model.authorizationStatus, .authorized)
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(model.wantsReminders)
        XCTAssertFalse(defaults.bool(forKey: ResetReminderSettings.preferenceKey))
    }

    @MainActor
    func testOffThenOnDuringSystemRequestKeepsLatestIntentAndOnlyOnePrompt() async throws {
        let (model, service, _) = try fixture()
        service.suspendRequests = true
        let first = Task { await model.setEnabled(true) }
        await service.waitForRequests(1)
        await model.setEnabled(false)
        let secondStarted = TaskStartSignal()
        let second = Task {
            secondStarted.signal()
            await model.setEnabled(true)
        }
        await secondStarted.wait()
        XCTAssertTrue(model.wantsReminders)
        XCTAssertEqual(service.requestCount, 1)
        service.finishRequest(status: .authorized)
        await first.value
        await second.value
        XCTAssertTrue(model.wantsReminders)
        XCTAssertTrue(model.isEnabled)
        XCTAssertEqual(service.requestCount, 1)
    }

    @MainActor
    func testForegroundDuringSystemPromptReadsFinalPermissionWithoutReprompt() async throws {
        let (model, service, _) = try fixture()
        service.suspendRequests = true
        let enable = Task { await model.setEnabled(true) }
        await service.waitForRequests(1)
        let foregroundStarted = TaskStartSignal()
        let foreground = Task {
            foregroundStarted.signal()
            await model.refreshAuthorization()
        }
        await foregroundStarted.wait()
        XCTAssertEqual(service.readCount, 1)
        service.finishRequest(status: .denied)
        await enable.value
        await foreground.value
        XCTAssertFalse(model.isEnabled)
        XCTAssertTrue(model.showsSystemSettings)
        XCTAssertEqual(service.requestCount, 1)
        XCTAssertEqual(service.readCount, 3)
    }

    @MainActor
    private func fixture(saved: Bool? = nil, status: ResetReminderAuthorizationStatus = .notDetermined)
    throws -> (ResetReminderSettings, AuthorizationServiceDouble, UserDefaults) {
        let suite = "T38-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        if let saved { defaults.set(saved, forKey: ResetReminderSettings.preferenceKey) }
        let service = AuthorizationServiceDouble(status: status)
        return (ResetReminderSettings(defaults: defaults, authorizationService: service), service, defaults)
    }
}

private enum TestError: Error { case failed }

@MainActor
private final class TaskStartSignal {
    private var signalled = false
    private var continuation: CheckedContinuation<Void, Never>?

    func signal() {
        signalled = true
        continuation?.resume()
        continuation = nil
    }

    func wait() async {
        guard !signalled else { return }
        await withCheckedContinuation { continuation = $0 }
    }
}

@MainActor
private final class AuthorizationServiceDouble: ResetReminderAuthorizationServing {
    var status: ResetReminderAuthorizationStatus
    var requestedStatus: ResetReminderAuthorizationStatus = .authorized
    var readError: Error?
    var requestError: Error?
    var suspendReads = false
    var suspendRequests = false
    private(set) var readCount = 0
    private(set) var requestCount = 0
    private var reads: [Int: CheckedContinuation<ResetReminderAuthorizationStatus, Error>] = [:]
    private var request: CheckedContinuation<Void, Error>?
    private var readWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var requestWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(status: ResetReminderAuthorizationStatus) { self.status = status }

    func authorizationStatus() async throws -> ResetReminderAuthorizationStatus {
        readCount += 1
        if suspendReads {
            return try await withCheckedThrowingContinuation { continuation in
                reads[readCount] = continuation
                resumeReadWaiters()
            }
        }
        resumeReadWaiters()
        if let readError { throw readError }
        return status
    }

    func requestAuthorization() async throws {
        requestCount += 1
        if suspendRequests {
            try await withCheckedThrowingContinuation { continuation in
                request = continuation
                resumeRequestWaiters()
            }
            return
        }
        resumeRequestWaiters()
        if let requestError { throw requestError }
        status = requestedStatus
    }

    func waitForReads(_ count: Int) async {
        guard readCount < count else { return }
        await withCheckedContinuation { readWaiters.append((count, $0)) }
    }

    func waitForRequests(_ count: Int) async {
        guard requestCount < count else { return }
        await withCheckedContinuation { requestWaiters.append((count, $0)) }
    }

    func finishRead(_ index: Int, status: ResetReminderAuthorizationStatus) {
        reads.removeValue(forKey: index)?.resume(returning: status)
    }

    func failRead(_ index: Int) {
        reads.removeValue(forKey: index)?.resume(throwing: TestError.failed)
    }

    func finishRequest(status: ResetReminderAuthorizationStatus) {
        self.status = status
        let pending = request
        request = nil
        pending?.resume()
    }

    private func resumeReadWaiters() {
        let ready = readWaiters.filter { $0.0 <= readCount }
        readWaiters.removeAll { $0.0 <= readCount }
        for (_, continuation) in ready { continuation.resume() }
    }

    private func resumeRequestWaiters() {
        let ready = requestWaiters.filter { $0.0 <= requestCount }
        requestWaiters.removeAll { $0.0 <= requestCount }
        for (_, continuation) in ready { continuation.resume() }
    }
}
