import XCTest
import Security
@testable import SubscriptionUsage

/// T112: balance accounts (D-82) in the shared account store, with an isolated
/// Keychain service and file. Synthetic keys only.
@MainActor
final class APIBalanceStoreTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_791_590_400)

    private struct Harness {
        let store: AccountStore
        let bindings: CodexAccountBindingStore
        let vault: CredentialVault
        let fileURL: URL
        let widget: WidgetSnapshotStore
    }

    private func harness() -> Harness {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T112-\(UUID().uuidString)")
        let service = "com.iceflying.SubscriptionUsage.tests.T112.\(UUID().uuidString)"
        let vault = CredentialVault(service: service)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
            SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: "\(service).credentials"] as CFDictionary)
        }
        let widget = WidgetSnapshotStore(fileURL: directory.appendingPathComponent("widget.json"))
        let fileURL = directory.appendingPathComponent("accounts.json")
        let store = AccountStore(fileURL: fileURL, widgetStore: widget)
        return Harness(store: store, bindings: CodexAccountBindingStore(accountStore: store, vault: vault),
                       vault: vault, fileURL: fileURL, widget: widget)
    }

    static func key(_ tail: String = "a1b2") -> APIKeyCredential {
        APIKeyCredential(pasted: "sk-or-v1-synthetic0000000000\(tail)")!
    }

    static func usd(_ total: String, at date: Date) -> APIBalanceSnapshot {
        APIBalanceSnapshot(amounts: [BalanceAmount(currency: "USD", total: Decimal(string: total)!)], observedAt: date)
    }

    private func login(_ h: Harness, provider: ProviderID = .openRouter, key: APIKeyCredential = key(),
                       balance: APIBalanceSnapshot? = nil) async throws -> ConnectedAccount {
        try await h.bindings.save(balance: APIBalanceVerifiedLogin(provider: provider, credential: key,
            balance: balance ?? Self.usd("12.34", at: time)))
    }

    private func codex(_ h: Harness) async throws -> ConnectedAccount {
        let account = ConnectedAccount(verifiedEmail: "codex@example.invalid",
            scope: .init(remoteAccountID: "acc-1", kind: .personal), credentialRef: UUID())
        try await h.store.append(account)
        return account
    }

    func testSavedBalanceAccountReadsBackWithKeyOnlyInKeychain() async throws {
        let h = harness()
        let saved = try await login(h)
        XCTAssertEqual(saved.platform, .openRouter)
        XCTAssertEqual(saved.identityText, "sk-…a1b2")
        XCTAssertEqual(saved.quotaState, .available)
        let loaded = try await h.store.load()
        let reread = try XCTUnwrap(loaded.first)
        XCTAssertEqual(reread, saved)
        XCTAssertEqual(reread.balance?.amounts.first?.total, Decimal(string: "12.34"))
        let stored = try await h.vault.load(for: .credential(saved.credentialRef))
        XCTAssertEqual(stored, Self.key().payload)
        let file = try String(contentsOf: h.fileURL, encoding: .utf8)
        XCTAssertFalse(file.contains("synthetic"), "the key must never enter the account file")
        let widget = try String(contentsOf: try h.widget.resolvedURL(), encoding: .utf8)
        XCTAssertFalse(widget.contains("synthetic"))
        XCTAssertFalse(widget.contains("keyfp"))
        XCTAssertEqual(try h.widget.read()?.account?.balance, [BalanceAmount(currency: "USD", total: Decimal(string: "12.34")!)])
    }

    func testDecimalAndMultipleCurrenciesStayExact() async throws {
        let h = harness()
        let balance = APIBalanceSnapshot(amounts: [
            BalanceAmount(currency: "CNY", total: try BalanceAmount.decimal("1234.567890123456789"),
                          toppedUp: try BalanceAmount.decimal("1000.000000000000001"), granted: try BalanceAmount.decimal("0")),
            BalanceAmount(currency: "USD", total: try BalanceAmount.decimal("0.01"))], observedAt: time)
        _ = try await login(h, provider: .deepSeek, balance: balance)
        let loaded = try await AccountStore(fileURL: h.fileURL).load()
        let reread = try XCTUnwrap(loaded.first)
        XCTAssertEqual(reread.balance, balance)
        XCTAssertEqual(BalanceAmount.text(reread.balance!.amounts[0].total), "1234.567890123456789")
        XCTAssertEqual(BalanceAmount.text(reread.balance!.amounts[0].toppedUp!), "1000.000000000000001")
        XCTAssertEqual(reread.balance?.amounts[1].granted, nil, "missing part stays unknown, not 0")
        // Widget carries totals only.
        XCTAssertEqual(try h.widget.read()?.account?.balance?.map(\.toppedUp), [nil, nil])
    }

    func testSameKeyUpdatesInPlaceAndDifferentKeyAppends() async throws {
        let h = harness()
        let first = try await codex(h)
        let original = try await login(h)
        let other = try await login(h, key: Self.key("c3d4"))
        let again = try await login(h, balance: Self.usd("20.00", at: time.addingTimeInterval(60)))
        let accounts = try await h.store.load()
        XCTAssertEqual(accounts.map(\.id), [first.id, original.id, other.id], "position kept, no duplicate")
        XCTAssertEqual(again.id, original.id)
        XCTAssertEqual(again.generation, original.generation + 1)
        XCTAssertEqual(accounts[1].balance?.amounts.first?.total, Decimal(string: "20.00"))
        XCTAssertNotEqual(accounts[1].credentialRef, original.credentialRef)
        let oldKey = try await h.vault.load(for: .credential(original.credentialRef))
        XCTAssertNil(oldKey, "retired credential is cleaned up")
        XCTAssertEqual(accounts[2].identityText, "sk-…c3d4")
        XCTAssertNotEqual(accounts[2].remoteUserID, accounts[1].remoteUserID)
        // The same key on the other platform is a different account.
        let deepSeek = try await login(h, provider: .deepSeek)
        let afterDeepSeek = try await h.store.load()
        XCTAssertEqual(afterDeepSeek.count, 4)
        XCTAssertEqual(afterDeepSeek.last?.id, deepSeek.id)
    }

    func testDeletionRemovesKeyAndCache() async throws {
        let h = harness()
        let saved = try await login(h)
        try await h.bindings.removeAccount(saved.id)
        let remaining = try await h.store.load()
        XCTAssertTrue(remaining.isEmpty)
        let stored = try await h.vault.load(for: .credential(saved.credentialRef))
        XCTAssertNil(stored)
        XCTAssertNil(try h.widget.read()?.account)
    }

    func testFailureKeepsTrustedBalanceAndOldResultsNeverOverwriteNewer() async throws {
        let h = harness()
        let saved = try await login(h)
        try await h.store.saveQuotaFailure(.refresh, for: saved)
        let loaded = try await h.store.load()
        let failed = try XCTUnwrap(loaded.first)
        XCTAssertEqual(failed.balance, saved.balance, "old value and its success time are kept")
        let failure = try await h.store.quotaFailure(for: saved.id)
        XCTAssertEqual(failure, .refresh)
        XCTAssertEqual(try h.widget.read()?.account?.failure, .refresh)
        XCTAssertEqual(try h.widget.read()?.account?.quotaObservedAt, time)

        let newer = try await h.store.saveBalance(Self.usd("5.00", at: time.addingTimeInterval(120)), for: failed)
        let cleared = try await h.store.quotaFailure(for: saved.id)
        XCTAssertNil(cleared)
        do {
            _ = try await h.store.saveBalance(Self.usd("99.00", at: time.addingTimeInterval(60)), for: newer)
            XCTFail("older result must be rejected")
        } catch { XCTAssertEqual(error as? AccountStore.StoreError, .staleQuotaContext) }
        let current = try await h.store.load().first?.balance?.amounts.first?.total
        XCTAssertEqual(current, Decimal(string: "5.00"))
    }

    func testLegacyFileWithoutBalanceStillLoads() async throws {
        let h = harness()
        let id = UUID(), ref = UUID()
        let legacy = """
        {"schemaVersion":1,"accounts":[{"id":"\(id)","provider":"openai","product":"codexSubscription",\
        "verifiedEmail":"old@example.invalid","scope":{"remoteAccountID":"acc","kind":"personal"},\
        "credentialRef":"\(ref)","generation":0,"quotaState":"notFetched"}]}
        """
        try FileManager.default.createDirectory(at: h.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(legacy.utf8).write(to: h.fileURL)
        let accounts = try await h.store.load()
        XCTAssertEqual(accounts.map(\.id), [id])
        XCTAssertNil(accounts[0].balance)
        _ = try await login(h)
        let both = try await h.store.load()
        XCTAssertEqual(both.map(\.platform), [.codex, .openRouter])
    }

    func testInvalidCombinationsAreRejected() async throws {
        let h = harness()
        var codex = ConnectedAccount(verifiedEmail: "c@example.invalid",
            scope: .init(remoteAccountID: "a", kind: .personal), credentialRef: UUID())
        codex.balance = Self.usd("1", at: time)
        do { try await h.store.append(codex); XCTFail() } catch {
            XCTAssertEqual(error as? AccountStore.StoreError, .invalidQuotaSnapshot)
        }
        var bad = ConnectedAccount(provider: .openRouter, product: .deepSeekBalance, remoteUserID: "keyfp:x", displayName: "sk-…0000",
            scope: .init(remoteAccountID: "keyfp:x", kind: .personal), credentialRef: UUID(), quotaState: .notFetched)
        do { try await h.store.append(bad); XCTFail() } catch {
            XCTAssertEqual(error as? AccountStore.StoreError, .invalidQuotaSnapshot)
        }
        bad = ConnectedAccount(provider: .openRouter, product: .openRouterCredits, remoteUserID: "keyfp:x", displayName: "sk-…0000",
            scope: .init(remoteAccountID: "keyfp:x", kind: .personal), credentialRef: UUID(), quotaState: .available)
        do { try await h.store.append(bad); XCTFail("available without a balance") } catch {
            XCTAssertEqual(error as? AccountStore.StoreError, .invalidQuotaSnapshot)
        }
        bad.balance = APIBalanceSnapshot(amounts: [BalanceAmount(currency: "usd", total: 1)], observedAt: time)
        do { try await h.store.append(bad); XCTFail("invalid currency") } catch {
            XCTAssertEqual(error as? AccountStore.StoreError, .invalidQuotaSnapshot)
        }
    }

    func testPastedKeyIsTrimmedMaskedAndRedacted() throws {
        let key = try XCTUnwrap(APIKeyCredential(pasted: "  sk-abcdefgh1234\n"))
        XCTAssertEqual(key.key, "sk-abcdefgh1234")
        XCTAssertEqual(key.masked, "sk-…1234")
        XCTAssertEqual(APIKeyCredential(pasted: "abcdefgh9876")?.masked, "…9876")
        XCTAssertNil(APIKeyCredential(pasted: "sk-abc def ghij"))
        XCTAssertNil(APIKeyCredential(pasted: "short"))
        XCTAssertFalse("\(key)".contains("abcdefgh"))
        XCTAssertFalse(String(reflecting: key).contains("abcdefgh"))
        XCTAssertEqual(key.fingerprint(for: .openRouter), key.fingerprint(for: .openRouter))
        XCTAssertNotEqual(key.fingerprint(for: .openRouter), key.fingerprint(for: .deepSeek))
        XCTAssertEqual(try APIKeyCredential(payload: key.payload), key)
        XCTAssertThrowsError(try BalanceAmount.decimal("1e3"))
        XCTAssertThrowsError(try BalanceAmount.decimal("NaN"))
        XCTAssertThrowsError(try BalanceAmount.decimal("1,000.00"))
    }
}
