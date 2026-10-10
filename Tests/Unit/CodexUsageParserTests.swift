import Foundation
import XCTest
@testable import SubscriptionUsage

/// T11 uses synthetic responses and accounts only: no transport, Keychain or account store.
@MainActor
final class CodexUsageParserTests: XCTestCase {
    private let observedAt = Date(timeIntervalSince1970: 1_791_590_400)
    private let fiveHourReset: Int64 = 1_791_608_400
    private let weeklyReset: Int64 = 1_792_195_200

    func testTwoNormalWindowsKeepIndependentRemainingResetAndObservation() throws {
        let result = try parse(response(
            primary: window(seconds: 18_000, used: "80", reset: fiveHourReset),
            secondary: window(seconds: 604_800, used: "30", reset: weeklyReset)
        ))

        XCTAssertEqual(result.weekly.amount.usedPercent, 30)
        XCTAssertEqual(result.weekly.amount.remainingPercent, 70)
        XCTAssertEqual(result.fiveHours.amount.usedPercent, 80)
        XCTAssertEqual(result.fiveHours.amount.remainingPercent, 20)
        XCTAssertEqual(result.weekly.window, .weekly)
        XCTAssertEqual(result.fiveHours.window, .fiveHours)
        XCTAssertEqual(result.weekly.resetsAt, Date(timeIntervalSince1970: Double(weeklyReset)))
        XCTAssertEqual(result.fiveHours.resetsAt, Date(timeIntervalSince1970: Double(fiveHourReset)))
        XCTAssertEqual(result.observedAt, observedAt)
        XCTAssertEqual(result.weekly.observedAt, observedAt)
        XCTAssertEqual(result.fiveHours.observedAt, observedAt)
        XCTAssertEqual(result.weekly.unit, .percent)
        XCTAssertEqual(result.fiveHours.unit, .percent)
        XCTAssertEqual(result.weekly.amount.progress, QuotaProgress(usedFraction: 0.3, remainingFraction: 0.7))
        XCTAssertEqual(result.fiveHours.amount.progress, QuotaProgress(usedFraction: 0.8, remainingFraction: 0.2))
        XCTAssertTrue(result.hasKnownQuota)
        print("T11 | 两个窗口：周已用 30%、5 小时已用 80% → 周剩余 \(try XCTUnwrap(result.weekly.amount.remainingPercent))%、5 小时剩余 \(try XCTUnwrap(result.fiveHours.amount.remainingPercent))%；各自重置时间与观测时间保留")
    }

    func testRealZeroFullAndFractionalUsageAreNotMissingOrRounded() throws {
        for (used, remaining) in [(0.0, 100.0), (100, 0), (12.5, 87.5), (99.75, 0.25)] {
            let result = try parse(response(primary: window(seconds: 18_000, used: String(used))))
            XCTAssertEqual(result.fiveHours.amount.usedPercent, used)
            XCTAssertEqual(result.fiveHours.amount.remainingPercent, remaining)
            XCTAssertEqual(result.fiveHours.amount.progress?.usedFraction, used / 100)
            XCTAssertEqual(result.fiveHours.amount.progress?.remainingFraction, remaining / 100)
            XCTAssertTrue(result.hasKnownQuota)
        }
        let zero = try parse(response(primary: window(seconds: 18_000, used: "0")))
        let full = try parse(response(primary: window(seconds: 18_000, used: "100")))
        print("T11 | 真实边界：已用 0% / 100% → 剩余 \(try XCTUnwrap(zero.fiveHours.amount.remainingPercent))% / \(try XCTUnwrap(full.fiveHours.amount.remainingPercent))%；小数保留")
    }

    func testMissingWindowPercentageAndResetRemainIndependentlyUnknown() throws {
        let onlyWeek = try parse(response(primary: window(seconds: 604_800, used: "30", reset: weeklyReset)))
        XCTAssertEqual(onlyWeek.weekly.amount.remainingPercent, 70)
        XCTAssertEqual(onlyWeek.weekly.resetsAt, Date(timeIntervalSince1970: Double(weeklyReset)))
        XCTAssertEqual(onlyWeek.fiveHours.amount, .unknown)
        XCTAssertNil(onlyWeek.fiveHours.resetsAt)

        let missingPercentage = try parse(response(primary: """
        {"limit_window_seconds":18000,"reset_at":\(fiveHourReset)}
        """))
        XCTAssertEqual(missingPercentage.fiveHours.amount, .unknown)
        XCTAssertNil(missingPercentage.fiveHours.amount.progress)
        XCTAssertEqual(missingPercentage.fiveHours.resetsAt, Date(timeIntervalSince1970: Double(fiveHourReset)))
        XCTAssertFalse(missingPercentage.hasKnownQuota)

        let missingReset = try parse(response(primary: window(seconds: 18_000, used: "80")))
        XCTAssertEqual(missingReset.fiveHours.amount.remainingPercent, 20)
        XCTAssertNil(missingReset.fiveHours.resetsAt)
        XCTAssertFalse(missingReset.fiveHours.isAwaitingUpdate(at: observedAt.addingTimeInterval(10_000_000)))
        print("T11 | 字段缺失：仅周额度 → 周剩余 \(try XCTUnwrap(onlyWeek.weekly.amount.remainingPercent))%、5 小时未知；缺比例保留重置时间，缺时间保留剩余 \(try XCTUnwrap(missingReset.fiveHours.amount.remainingPercent))%")
    }

    func testExplicitNullsHaveTheSameUnknownMeaningAsAbsentFields() throws {
        for input in ["{}", #"{"rate_limit":null,"plan_type":null}"#,
                      response(primary: "null", secondary: "null"),
                      response(primary: #"{"limit_window_seconds":null,"used_percent":80,"reset_at":null}"#)] {
            let result = try parse(input)
            XCTAssertEqual(result.weekly.amount, .unknown)
            XCTAssertEqual(result.fiveHours.amount, .unknown)
            XCTAssertNil(result.weekly.resetsAt)
            XCTAssertNil(result.fiveHours.resetsAt)
            XCTAssertFalse(result.hasKnownQuota)
        }
        let result = try parse(response(primary: #"{"limit_window_seconds":18000,"used_percent":null,"reset_at":null}"#))
        XCTAssertEqual(result.fiveHours.amount, .unknown)
        XCTAssertNil(result.fiveHours.resetsAt)
        XCTAssertNil(result.fiveHours.amount.remainingPercent)
    }

    func testWindowMeaningFollowsDurationWhenOrderIsSwappedOrOnlyOnePositionExists() throws {
        let weekly = window(seconds: 604_800, used: "30", reset: weeklyReset)
        let fiveHours = window(seconds: 18_000, used: "80", reset: fiveHourReset)
        let original = try parse(response(primary: fiveHours, secondary: weekly))
        let swapped = try parse(response(primary: weekly, secondary: fiveHours))
        XCTAssertEqual(swapped, original)
        let primaryWeekOnly = try parse(response(primary: weekly))
        XCTAssertEqual(primaryWeekOnly.weekly, original.weekly)
        XCTAssertEqual(primaryWeekOnly.fiveHours.amount, .unknown)
        let secondaryFiveHoursOnly = try parse(response(secondary: fiveHours))
        XCTAssertEqual(secondaryFiveHoursOnly.fiveHours, original.fiveHours)
        XCTAssertEqual(secondaryFiveHoursOnly.weekly.amount, .unknown)
        print("T11 | 窗口交换或单独返回：按真实时长识别 → 周剩余 \(try XCTUnwrap(swapped.weekly.amount.remainingPercent))%、5 小时剩余 \(try XCTUnwrap(swapped.fiveHours.amount.remainingPercent))%，位置不影响结果")
    }

    func testNearbyAndUnrelatedDurationsCannotImpersonateMVPWindows() throws {
        for duration in [18_001, 604_801, 3_600, 86_400] {
            let extra = window(seconds: duration, used: "1", reset: fiveHourReset)
            let result = try parse(response(primary: extra, secondary: window(seconds: 604_800, used: "30")))
            XCTAssertEqual(result.fiveHours.amount, .unknown, "时长 \(duration) 不得冒充 5 小时")
            XCTAssertNil(result.fiveHours.resetsAt)
            XCTAssertEqual(result.weekly.amount.remainingPercent, 70)
        }
        let missingDuration = try parse(response(primary: #"{"used_percent":80,"reset_at":1791608400}"#))
        XCTAssertFalse(missingDuration.hasKnownQuota)
        XCTAssertNil(missingDuration.fiveHours.resetsAt)
        XCTAssertNil(missingDuration.weekly.resetsAt)
        let bothNearby = try parse(response(primary: window(seconds: 18_001, used: "80"), secondary: window(seconds: 604_801, used: "30")))
        XCTAssertFalse(bothNearby.hasKnownQuota)
    }

    func testCreditsAndAdditionalModelLimitsNeitherReplaceNorCreateSubscriptionQuota() throws {
        let extras = #"""
        "credits":{"balance":999,"has_credits":true,"unlimited":true},
        "additional_rate_limits":[{"limit_name":"extra-model","rate_limit":{"primary_window":{"limit_window_seconds":18000,"used_percent":1},"secondary_window":{"limit_window_seconds":604800,"used_percent":2}}}],
        "code_review_rate_limit":{"primary_window":{"limit_window_seconds":604800,"used_percent":3}},
        "api_balance":999,"unrecognized_field":"ignored"
        """#
        let known = try parse("""
        {"rate_limit":{"allowed":true,"limit_reached":false,"primary_window":\(window(seconds: 18_000, used: "80")),"secondary_window":\(window(seconds: 604_800, used: "30"))},\(extras)}
        """)
        XCTAssertEqual(known.weekly.amount.remainingPercent, 70)
        XCTAssertEqual(known.fiveHours.amount.remainingPercent, 20)
        for main in ["null", #"{"allowed":true,"limit_reached":false}"#, #"{"allowed":false,"limit_reached":true}"#] {
            let result = try parse("{\"rate_limit\":\(main),\(extras)}")
            XCTAssertEqual(result.weekly.amount, .unknown)
            XCTAssertEqual(result.fiveHours.amount, .unknown)
            XCTAssertFalse(result.hasKnownQuota)
        }
        print("T11 | 额外模型额度、余额和 credits 不限量 → 订阅周剩余 \(try XCTUnwrap(known.weekly.amount.remainingPercent))%、5 小时剩余 \(try XCTUnwrap(known.fiveHours.amount.remainingPercent))% 不变；没有订阅窗口时仍未知")
    }

    func testDomainExplicitUnlimitedAndUnknownRemainDistinctWithoutNumericProgress() {
        XCTAssertNotEqual(QuotaAmount.unlimited, QuotaAmount.unknown)
        for amount in [QuotaAmount.unlimited, .unknown] {
            XCTAssertNil(amount.usedPercent)
            XCTAssertNil(amount.remainingPercent)
            XCTAssertNil(amount.progress)
        }
        print("T11 | 领域状态：明确不限量 / 未知 → 两种状态分别保留，均无已用比例、剩余比例或进度条")
    }

    func testPassingTheResetPointOnlyMarksStaleAndNeverRefillsTheMeasuredQuota() throws {
        let result = try parse(response(primary: window(seconds: 18_000, used: "80", reset: fiveHourReset)))
        let reset = try XCTUnwrap(result.fiveHours.resetsAt)
        XCTAssertFalse(result.fiveHours.isAwaitingUpdate(at: reset.addingTimeInterval(-1)))
        XCTAssertTrue(result.fiveHours.isAwaitingUpdate(at: reset))
        XCTAssertTrue(result.fiveHours.isAwaitingUpdate(at: reset.addingTimeInterval(86_400)))
        XCTAssertEqual(result.fiveHours.amount.remainingPercent, 20)
        XCTAssertEqual(result.fiveHours.observedAt, observedAt)
        XCTAssertEqual(result.fiveHours.resetsAt, reset)
        let observedAfterReset = try parse(response(primary: window(seconds: 18_000, used: "80", reset: fiveHourReset)), at: reset.addingTimeInterval(1))
        XCTAssertEqual(observedAfterReset.fiveHours.amount.remainingPercent, 20)
        print("T11 | 已到或超过重置时间 → 仍保留上次真实剩余 \(try XCTUnwrap(result.fiveHours.amount.remainingPercent))%，等待更新，不自动变成满额")
    }

    func testInvalidPercentageTypesAndValuesFailInsteadOfClampingOrGuessing() {
        for value in ["true", "false", "\"30\"", "-0.01", "100.01", "1e999", "{}", "[]"] {
            XCTAssertThrowsError(try parse(response(primary: window(seconds: 18_000, used: value))), "非法比例 \(value) 不应变成可信额度")
        }
        for value in ["-1", "101"] {
            XCTAssertThrowsError(try parse(response(primary: window(seconds: 604_800, used: value)))) { error in
                XCTAssertEqual(error as? QuotaInterpretationError, .invalidPercentage)
            }
        }
    }

    func testDomainPercentageRejectsNonFiniteAndOutOfRangeNumbers() {
        for value in [Double.nan, .infinity, -.infinity, -0.01, 100.01] {
            XCTAssertThrowsError(try QuotaPercentage(used: value)) { error in
                XCTAssertEqual(error as? QuotaInterpretationError, .invalidPercentage)
            }
        }
    }

    func testDuplicateTargetWindowsFailInsteadOfPickingFirstOrLast() {
        for seconds in [18_000, 604_800] {
            for secondUsage in ["20", "80"] {
                XCTAssertThrowsError(try parse(response(primary: window(seconds: seconds, used: "80"), secondary: window(seconds: seconds, used: secondUsage)))) { error in
                    XCTAssertEqual(error as? QuotaInterpretationError, .ambiguousWindow)
                }
            }
        }
    }

    func testInvalidDurationCannotBecomeARecognizedWindow() {
        for seconds in ["0", "-18000"] {
            XCTAssertThrowsError(try parse(response(primary: "{\"limit_window_seconds\":\(seconds),\"used_percent\":80}"))) { error in
                XCTAssertEqual(error as? QuotaInterpretationError, .invalidWindowLength)
            }
        }
        for seconds in ["true", "\"18000\"", "18000.5", "1e999"] {
            XCTAssertThrowsError(try parse(response(primary: "{\"limit_window_seconds\":\(seconds),\"used_percent\":80}")))
        }
    }

    func testInvalidResetTimesFailInsteadOfInferringADate() {
        for reset in ["0", "-1", "253402300800", "1791608400000", "1791608400.5", "true", "\"1791608400\"", "1e999"] {
            XCTAssertThrowsError(try parse(response(primary: "{\"limit_window_seconds\":18000,\"used_percent\":80,\"reset_at\":\(reset)}")), "非法重置时间 \(reset) 不应被自动修正")
        }
    }

    func testTrustedAccountContextAndUnknownPlanArePreservedWithoutInventingALimit() throws {
        var account = syntheticAccount()
        account.generation = 7
        account.scope = AccountScope(remoteAccountID: "synthetic-workspace", kind: .workspace, label: "Synthetic workspace")
        let result = try parse(#"{"plan_type":"future_subscription","account_id":"synthetic-workspace","accountId":"synthetic-workspace"}"#, for: account)
        XCTAssertEqual(result.accountID, account.id)
        XCTAssertEqual(result.provider, account.provider)
        XCTAssertEqual(result.product, account.product)
        XCTAssertEqual(result.scope, account.scope)
        XCTAssertEqual(result.generation, 7)
        XCTAssertEqual(result.planType, "future_subscription")
        XCTAssertFalse(result.hasKnownQuota)
        let absentIdentity = try parse(response(primary: window(seconds: 18_000, used: "80")), for: account)
        XCTAssertEqual(absentIdentity.scope, account.scope)
        XCTAssertEqual(absentIdentity.accountID, account.id)
        XCTAssertNil(absentIdentity.planType)
        XCTAssertEqual(absentIdentity.fiveHours.amount.remainingPercent, 20)
        for plan in ["plus", "pro", "enterprise"] {
            let planOnly = try parse("{\"plan_type\":\"\(plan)\"}")
            XCTAssertFalse(planOnly.hasKnownQuota, "套餐名称不能推断比例或不限量")
        }
    }

    func testConflictingResponseIdentityCannotBeBoundToTheRequestedAccount() {
        for identity in [#""account_id":"other-account""#, #""accountId":"other-account""#,
                         #""account_id":"synthetic-account","accountId":"other-account""#,
                         #""account_id":"other-account","accountId":"synthetic-account""#] {
            XCTAssertThrowsError(try parse("{\(identity),\"rate_limit\":{\"primary_window\":\(window(seconds: 18_000, used: "80"))}}")) { error in
                XCTAssertEqual(error as? QuotaInterpretationError, .accountMismatch)
            }
        }
    }

    func testMalformedKnownFieldsAndInvalidObservationDoNotProduceASnapshot() {
        for input in ["not JSON", "[]", "null", #"{"rate_limit":true}"#,
                      #"{"rate_limit":{"primary_window":[]}}"#,
                      #"{"plan_type":42}"#, #"{"account_id":true}"#] {
            XCTAssertThrowsError(try parse(input))
        }
        for invalidTime in [Double.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try parse("{}", at: Date(timeIntervalSince1970: invalidTime))) { error in
                XCTAssertEqual(error as? QuotaInterpretationError, .invalidObservationTime)
            }
        }
    }

    private func parse(_ json: String, for account: ConnectedAccount? = nil, at date: Date? = nil) throws -> CodexQuotaSnapshot {
        try CodexUsageParser().parse(Data(json.utf8), for: account ?? syntheticAccount(), observedAt: date ?? observedAt)
    }

    private func response(primary: String = "null", secondary: String = "null") -> String {
        "{\"rate_limit\":{\"primary_window\":\(primary),\"secondary_window\":\(secondary)}}"
    }

    private func window(seconds: Int, used: String, reset: Int64? = nil) -> String {
        let resetField = reset.map { ",\"reset_at\":\($0)" } ?? ""
        return "{\"limit_window_seconds\":\(seconds),\"used_percent\":\(used)\(resetField)}"
    }

    private func syntheticAccount() -> ConnectedAccount {
        ConnectedAccount(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            remoteUserID: "synthetic-user",
            verifiedEmail: "quota-test@example.invalid",
            scope: AccountScope(remoteAccountID: "synthetic-account", kind: .personal),
            credentialRef: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        )
    }
}
