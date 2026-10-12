import Foundation
import XCTest
@testable import SubscriptionUsage

/// Every input is synthetic and the planner has no notification-center dependency.
final class ResetReminderPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_700_000)
    private let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    func testTwoAccountsProduceTheirFourIndependentWindowsAndExactTimes() throws {
        let first = try account(id: firstID, email: "first@example.invalid")
        let second = try account(id: secondID, email: "second@example.invalid", offset: 600)
        let result = plan([first, second])
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(Set(result.map(\.identifier)).count, 4)
        for account in [first, second] {
            let snapshot = try XCTUnwrap(account.quotaSnapshot)
            for window in [snapshot.weekly, snapshot.fiveHours] {
                let request = try XCTUnwrap(result.first { $0.accountID == account.id && $0.window == window.window })
                XCTAssertEqual(request.resetsAt, window.resetsAt)
                XCTAssertEqual(request.title, "Codex · \(try XCTUnwrap(account.verifiedEmail))")
                XCTAssertTrue(request.identifier.hasPrefix("quota-reset.v1."))
            }
        }
    }

    func testContentIdentifiesWindowAndOnlyClaimsExpectedReset() throws {
        let result = plan([try account()])
        XCTAssertEqual(result.map(\.body), ["周额度预计重置，打开查看", "5 小时额度预计重置，打开查看"])
        for request in result {
            XCTAssertFalse(request.body.contains("已恢复"))
            XCTAssertFalse(request.body.contains("满额"))
            XCTAssertFalse(request.body.contains("100%"))
        }
    }

    func testOffPreferenceNeverPlansEvenWhenSystemAllows() throws {
        XCTAssertTrue(ResetReminderPlan.requests(accounts: [try account()], wantsReminders: false,
                                                 authorization: .authorized, now: now).isEmpty)
    }

    func testEveryNonPermittedAuthorizationBlocksPlanning() throws {
        for status: ResetReminderAuthorizationStatus in [.unknown, .notDetermined, .denied] {
            XCTAssertTrue(ResetReminderPlan.requests(accounts: [try account()], wantsReminders: true,
                                                     authorization: status, now: now).isEmpty)
        }
    }

    func testEveryPermittedAuthorizationPlansWithoutRequestingPermission() throws {
        for status: ResetReminderAuthorizationStatus in [.authorized, .provisional, .ephemeral] {
            XCTAssertEqual(ResetReminderPlan.requests(accounts: [try account()], wantsReminders: true,
                                                      authorization: status, now: now).count, 2)
        }
    }

    func testDemoPendingDeletionMissingAndNotApplicableSnapshotsAreExcluded() throws {
        var demo = try account(); demo.source = .demo
        var deleted = try account(); deleted.deletionPending = true
        var missing = try account(); missing.quotaSnapshot = nil
        var unfetched = try account(); unfetched.quotaState = .notFetched
        var inapplicable = try account(); inapplicable.quotaState = .notApplicable
        for input in [demo, deleted, missing, unfetched, inapplicable] {
            XCTAssertTrue(plan([input]).isEmpty)
        }
    }

    func testSnapshotAccountScopeAndGenerationMustMatchCurrentBinding() throws {
        let original = try account()
        let otherScope = AccountScope(remoteAccountID: "different-scope", kind: .workspace)
        for input in [replacing(original, accountID: secondID),
                      replacing(original, scope: otherScope),
                      replacing(original, generation: original.generation + 1)] {
            XCTAssertTrue(plan([input]).isEmpty)
        }
    }

    func testChangedInvalidOrOlderSubscriptionDoesNotReuseOldQuota() throws {
        let original = try account()
        var invalid = original
        invalid.subscription = .init(planType: "", observedAt: now)
        var older = original
        older.subscription = .init(planType: "plus", observedAt: now.addingTimeInterval(-120))
        XCTAssertTrue(plan([replacing(original, planType: "pro")]).isEmpty)
        XCTAssertTrue(plan([invalid]).isEmpty)
        XCTAssertTrue(plan([older]).isEmpty)
    }

    func testLegacyTrustedSnapshotWithoutSeparateSubscriptionStillPlans() throws {
        var original = try account()
        original.subscription = nil
        XCTAssertEqual(plan([original]).count, 2)
    }

    func testMissingResetOmitsOnlyThatWindow() throws {
        let original = try account()
        let input = replacing(original, weekly: try window(.weekly, reset: nil))
        XCTAssertEqual(plan([input]).map(\.window), [.fiveHours])
    }

    func testNonfiniteAndOutOfRangeResetTimesAreNeverPlanned() throws {
        let original = try account()
        for seconds: Double in [.nan, .infinity, -.infinity, -1, 0, 253_402_300_800] {
            let input = replacing(original, weekly: try window(.weekly, reset: Date(timeIntervalSince1970: seconds)))
            XCTAssertEqual(plan([input]).map(\.window), [.fiveHours], "Invalid reset: \(seconds)")
        }
    }

    func testPastAndExactCurrentTimeNeverScheduleCatchUp() throws {
        let original = try account()
        for reset in [now.addingTimeInterval(-1), now] {
            let input = replacing(original, weekly: try window(.weekly, reset: reset))
            XCTAssertEqual(plan([input]).map(\.window), [.fiveHours])
        }
    }

    func testResetAtOrBeforeObservationIsRejectedEvenIfFutureToClock() throws {
        let original = try account()
        let observation = now.addingTimeInterval(100)
        var input = replacing(original, observedAt: observation,
            weekly: try window(.weekly, reset: observation, observed: observation),
            fiveHours: try window(.fiveHours, reset: observation.addingTimeInterval(-1), observed: observation))
        input.subscription = .init(planType: "plus", observedAt: observation)
        XCTAssertTrue(plan([input]).isEmpty)
    }

    func testIncorrectWindowTypeOrObservationCannotBorrowAnotherWindowsTime() throws {
        let original = try account()
        let wrongType = replacing(original, weekly: try window(.fiveHours, reset: now.addingTimeInterval(300)))
        let wrongObservation = replacing(original, weekly: try window(.weekly, reset: now.addingTimeInterval(300), observed: now))
        XCTAssertEqual(plan([wrongType]).map(\.window), [.fiveHours])
        XCTAssertEqual(plan([wrongObservation]).map(\.window), [.fiveHours])
    }

    func testNonfiniteObservationAndClockDoNotProduceRequests() throws {
        let original = try account()
        for seconds: Double in [.nan, .infinity, -.infinity] {
            XCTAssertTrue(plan([replacing(original, observedAt: Date(timeIntervalSince1970: seconds))]).isEmpty)
            XCTAssertTrue(ResetReminderPlan.requests(accounts: [original], wantsReminders: true,
                authorization: .authorized, now: Date(timeIntervalSince1970: seconds)).isEmpty)
        }
    }

    func testUnknownAmountCannotScheduleButValidOtherWindowStillCan() throws {
        let original = try account()
        let input = replacing(original, weekly: try window(.weekly, reset: now.addingTimeInterval(300), amount: .unknown))
        XCTAssertEqual(plan([input]).map(\.window), [.fiveHours])
        let bothUnknown = replacing(input, fiveHours: try window(.fiveHours, reset: now.addingTimeInterval(300), amount: .unknown))
        XCTAssertTrue(plan([bothUnknown]).isEmpty)
    }

    func testKnownUnlimitedWindowWithReportedFutureResetUsesThatExactTime() throws {
        let original = try account()
        let reset = now.addingTimeInterval(123)
        let input = replacing(original, weekly: try window(.weekly, reset: reset, amount: .unlimited))
        XCTAssertEqual(plan([input]).first?.resetsAt, reset)
        XCTAssertEqual(plan([input]).count, 2)
    }

    func testIdentityFallsBackToVerifiedUserThenScopeAndRejectsEmptyIdentity() throws {
        var input = try account()
        input.verifiedEmail = nil
        XCTAssertEqual(plan([input]).first?.title, "Codex · verified-user")
        input.remoteUserID = nil
        XCTAssertEqual(plan([input]).first?.title, "Codex · verified-scope")
        input.scope = .init(remoteAccountID: "", kind: .personal)
        input = replacing(input, scope: input.scope)
        XCTAssertTrue(plan([input]).isEmpty)
    }

    func testControlCharactersDoNotEnterNotificationIdentity() throws {
        var input = try account()
        input.verifiedEmail = "first\nsecond@example.invalid"
        XCTAssertEqual(plan([input]).first?.title, "Codex · verified-user")
    }

    func testSortingAndSuccessfulSameIdentityGenerationChangeKeepIdentifiers() throws {
        let first = try account(id: firstID)
        let second = try account(id: secondID, offset: 100)
        XCTAssertEqual(Set(plan([first, second]).map(\.identifier)), Set(plan([second, first]).map(\.identifier)))
        var reconnected = first
        reconnected.generation += 1
        reconnected = replacing(reconnected, generation: reconnected.generation)
        XCTAssertEqual(plan([first]).map(\.identifier), plan([reconnected]).map(\.identifier))
    }

    func testDifferentReportedResetChangesOnlyThatRequestIdentity() throws {
        let original = try account()
        let changed = replacing(original, weekly: try window(.weekly, reset: now.addingTimeInterval(900)))
        let before = plan([original]); let after = plan([changed])
        XCTAssertNotEqual(before[0].identifier, after[0].identifier)
        XCTAssertEqual(before[1], after[1])
    }

    func testTimeCrossingOnlyDropsExpiredRequestWithoutMutatingQuotaOrSuccessTime() throws {
        let original = try account()
        let saved = try JSONEncoder().encode(original)
        XCTAssertEqual(plan([original]).count, 2)
        let afterFiveHours = ResetReminderPlan.requests(accounts: [original], wantsReminders: true,
            authorization: .authorized, now: now.addingTimeInterval(300))
        XCTAssertEqual(afterFiveHours.map(\.window), [.weekly])
        XCTAssertTrue(ResetReminderPlan.requests(accounts: [original], wantsReminders: true,
            authorization: .authorized, now: now.addingTimeInterval(600)).isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(ConnectedAccount.self, from: saved), original)
        XCTAssertEqual(original.quotaSnapshot?.weekly.amount.remainingPercent, 70)
        XCTAssertEqual(original.quotaSnapshot?.observedAt, now.addingTimeInterval(-60))
    }

    private func plan(_ accounts: [ConnectedAccount]) -> [ResetReminderRequest] {
        ResetReminderPlan.requests(accounts: accounts, wantsReminders: true, authorization: .authorized, now: now)
    }

    private func account(id: UUID? = nil, email: String = "first@example.invalid", offset: TimeInterval = 0) throws -> ConnectedAccount {
        var result = ConnectedAccount(id: id ?? firstID, remoteUserID: "verified-user", verifiedEmail: email,
            scope: .init(remoteAccountID: "verified-scope", kind: .personal), credentialRef: UUID(),
            generation: 7, quotaState: .available)
        let observed = now.addingTimeInterval(-60)
        result.subscription = .init(planType: "plus", observedAt: observed)
        result.quotaSnapshot = .init(accountID: result.id, provider: result.provider, product: result.product,
            scope: result.scope, generation: result.generation, planType: "plus", observedAt: observed,
            weekly: try window(.weekly, reset: now.addingTimeInterval(600 + offset)),
            fiveHours: try window(.fiveHours, reset: now.addingTimeInterval(300 + offset)))
        return result
    }

    private func window(_ type: QuotaWindow, reset: Date?, observed: Date? = nil, amount: QuotaAmount? = nil) throws -> QuotaWindowSnapshot {
        .init(window: type, amount: try amount ?? .limited(QuotaPercentage(used: 30)),
              resetsAt: reset, observedAt: observed ?? now.addingTimeInterval(-60))
    }

    private func replacing(_ account: ConnectedAccount, accountID: UUID? = nil, scope: AccountScope? = nil,
                           generation: UInt64? = nil, planType: String? = nil, observedAt: Date? = nil,
                           weekly: QuotaWindowSnapshot? = nil, fiveHours: QuotaWindowSnapshot? = nil) -> ConnectedAccount {
        var result = account
        let original = account.quotaSnapshot!
        result.quotaSnapshot = .init(accountID: accountID ?? original.accountID, provider: original.provider,
            product: original.product, scope: scope ?? original.scope, generation: generation ?? original.generation,
            planType: planType ?? original.planType, observedAt: observedAt ?? original.observedAt,
            weekly: weekly ?? original.weekly, fiveHours: fiveHours ?? original.fiveHours)
        return result
    }
}
