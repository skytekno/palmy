import Combine
import Foundation
import XCTest
@testable import PalmyCore

/// These tests exercise the same AppModel observed by SwiftUI. Controlled continuations
/// intentionally ignore cancellation, reproducing transports that complete after a lock.
@MainActor final class AppModelTests: XCTestCase {
    private func fixture() async throws -> (AppModel, ControlledService, Identity) {
        let service = ControlledService()
        let identity = try Identity.create()
        await service.seed(identity, name: "Pemilik pertama")
        return (AppModel(apiFactory: { service }), service, identity)
    }
    private func login(_ model: AppModel, _ identity: Identity) async {
        model.recover(identity.recovery)
        await model.operation?.value
        XCTAssertEqual(model.identity?.accountID, identity.accountID)
        XCTAssertFalse(model.busy)
    }
    private func assertLocked(_ model: AppModel, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(model.identity, file: file, line: line)
        XCTAssertNil(model.summary, file: file, line: line)
        XCTAssertTrue(model.wallets.isEmpty, file: file, line: line)
        XCTAssertTrue(model.entries.isEmpty, file: file, line: line)
        XCTAssertEqual(model.profile, Profile(display_name: "", email: ""), file: file, line: line)
        XCTAssertEqual(model.savedWallet, 0, file: file, line: line)
        XCTAssertEqual(model.savedEntry, 0, file: file, line: line)
        XCTAssertFalse(model.busy, file: file, line: line)
    }

    func testIdleOnboardingSurvivesPasswordManagerTripWithoutNetwork() async throws {
        let (model, service, _) = try await fixture()
        model.profile = Profile(display_name: "Draft", email: "draft@example.invalid")
        model.prepare()
        let candidate = try XCTUnwrap(model.pendingIdentity)
        model.didEnterBackground()
        XCTAssertEqual(model.pendingIdentity?.accountID, candidate.accountID)
        XCTAssertEqual(model.profile.display_name, "Draft")
        let counts = await service.counts()
        XCTAssertEqual(counts.registrations, 0)
        XCTAssertEqual(counts.authentications, 0)
        model.cancelPrepare()
        XCTAssertNil(model.pendingIdentity)
    }

    func testBackgroundBeforeQueuedRecoveryPreventsAuthentication() async throws {
        let (model, service, identity) = try await fixture()
        model.recover(identity.recovery)
        let operation = model.operation
        model.didEnterBackground()
        assertLocked(model)
        await operation?.value
        let counts = await service.counts()
        XCTAssertEqual(counts.authentications, 0)
        assertLocked(model)
    }

    func testBackgroundDuringRegistrationDoesNotStartSignInAfterLateResponse() async throws {
        let (model, service, _) = try await fixture()
        model.profile = Profile(display_name: "Draft", email: "draft@example.invalid")
        model.prepare()
        let candidate = try XCTUnwrap(model.pendingIdentity)
        let gate = await service.hold(.registration(candidate.accountID))
        model.create()
        let operation = model.operation
        await fulfillment(of: [gate.entered], timeout: 3)
        model.didEnterBackground()
        assertLocked(model)
        XCTAssertNil(model.pendingIdentity)
        await gate.resume()
        await operation?.value
        let counts = await service.counts()
        XCTAssertEqual(counts.registrations, 1)
        XCTAssertEqual(counts.authentications, 0)
        assertLocked(model)
    }

    func testBackgroundDuringRecoveryRejectsLateSessionAndRevokesIt() async throws {
        let (model, service, identity) = try await fixture()
        let gate = await service.hold(.authentication(identity.accountID))
        model.recover(identity.recovery)
        let operation = model.operation
        await fulfillment(of: [gate.entered], timeout: 3)
        model.didEnterBackground()
        assertLocked(model)
        await gate.resume()
        await operation?.value
        await model.revocation?.value
        let counts = await service.counts()
        XCTAssertEqual(counts.profiles, 0)
        XCTAssertEqual(counts.revoked.count, 1)
        assertLocked(model)
    }

    func testLateOldAuthenticationCannotReplaceNewLogin() async throws {
        let (model, service, oldIdentity) = try await fixture()
        let newIdentity = try Identity.create()
        await service.seed(newIdentity, name: "Pemilik baru")
        let gate = await service.hold(.authentication(oldIdentity.accountID))
        model.recover(oldIdentity.recovery)
        let oldOperation = model.operation
        await fulfillment(of: [gate.entered], timeout: 3)
        model.lock()
        await login(model, newIdentity)
        await gate.resume()
        await oldOperation?.value
        await model.revocation?.value
        XCTAssertEqual(model.identity?.accountID, newIdentity.accountID)
        XCTAssertEqual(model.profile.display_name, "Pemilik baru")
        let counts = await service.counts()
        let oldToken = await service.token(for: oldIdentity.accountID)
        let newToken = await service.token(for: newIdentity.accountID)
        XCTAssertEqual(counts.revoked, [oldToken])
        XCTAssertFalse(counts.revoked.contains(newToken))
    }

    func testLateOldProfileFailureCannotClearNewLogin() async throws {
        let (model, service, oldIdentity) = try await fixture()
        let newIdentity = try Identity.create()
        await service.seed(newIdentity, name: "Pemilik baru")
        let gate = await service.hold(.profile(oldIdentity.accountID))
        model.recover(oldIdentity.recovery)
        let oldOperation = model.operation
        await fulfillment(of: [gate.entered], timeout: 3)
        model.lock()
        await login(model, newIdentity)
        await gate.resume(throwing: APIError(status: 503, message: "Old response must stay invisible"))
        await oldOperation?.value
        await model.revocation?.value
        XCTAssertEqual(model.identity?.accountID, newIdentity.accountID)
        XCTAssertEqual(model.profile.display_name, "Pemilik baru")
        XCTAssertNotNil(model.summary)
        XCTAssertFalse(model.isError)
        XCTAssertFalse(model.message.contains("Old response"))
    }

    func testLockIsImmediateAndLateRevocationCannotChangeNewSession() async throws {
        let (model, service, oldIdentity) = try await fixture()
        await login(model, oldIdentity)
        let oldToken = await service.token(for: oldIdentity.accountID)
        let gate = await service.hold(.revocation(oldToken))
        model.lock()
        let revocation = model.revocation
        assertLocked(model) // No await: local clearing is synchronous even when revocation is stuck.
        await fulfillment(of: [gate.entered], timeout: 3)
        let newIdentity = try Identity.create()
        await service.seed(newIdentity, name: "Pemilik baru")
        await login(model, newIdentity)
        await gate.resume(throwing: URLError(.notConnectedToInternet))
        await revocation?.value
        XCTAssertEqual(model.identity?.accountID, newIdentity.accountID)
        XCTAssertEqual(model.profile.display_name, "Pemilik baru")
        XCTAssertTrue(model.message.isEmpty)
        let calls = await service.revokeCalls
        XCTAssertEqual(calls, [oldToken])
    }

    func testFailedRevocationLeavesLockedStateAndExplainsExpiry() async throws {
        let (model, service, identity) = try await fixture()
        await login(model, identity)
        let gate = await service.hold(.revocation(await service.token(for: identity.accountID)))
        model.lock()
        assertLocked(model)
        await fulfillment(of: [gate.entered], timeout: 3)
        await gate.resume(throwing: URLError(.notConnectedToInternet))
        await model.revocation?.value
        assertLocked(model)
        XCTAssertTrue(model.message.contains("1 jam"))
    }

    func testLateRevocationWarningCannotContaminateInFlightNewLogin() async throws {
        let (model, service, oldIdentity) = try await fixture()
        await login(model, oldIdentity)
        let revokeGate = await service.hold(.revocation(await service.token(for: oldIdentity.accountID)))
        model.lock()
        let revocation = model.revocation
        await fulfillment(of: [revokeGate.entered], timeout: 3)
        let nextIdentity = try Identity.create()
        await service.seed(nextIdentity, name: "Pemilik berikutnya")
        let loginGate = await service.hold(.authentication(nextIdentity.accountID))
        model.recover(nextIdentity.recovery)
        await fulfillment(of: [loginGate.entered], timeout: 3)
        await revokeGate.resume(throwing: URLError(.notConnectedToInternet))
        await revocation?.value
        XCTAssertTrue(model.busy)
        XCTAssertTrue(model.message.isEmpty)
        await loginGate.resume()
        await model.operation?.value
        XCTAssertEqual(model.identity?.accountID, nextIdentity.accountID)
        XCTAssertTrue(model.message.isEmpty)
    }

    func testFailedInitialDashboardNeverPublishesUnlockedIdentityOrProfile() async throws {
        let (model, service, identity) = try await fixture()
        await service.failSummaries(true)
        var publishedIdentityCount = 0
        let observation = model.$identity.sink { if $0 != nil { publishedIdentityCount += 1 } }
        model.recover(identity.recovery)
        await model.operation?.value
        await model.revocation?.value
        assertLocked(model)
        XCTAssertEqual(publishedIdentityCount, 0)
        XCTAssertTrue(model.isError)
        withExtendedLifetime(observation) {}
    }

    func testCommittedExpenseThenFailedRefreshSignalsFormResetAndNeverRepostsOnReload() async throws {
        let (model, service, identity) = try await fixture()
        await login(model, identity)
        await service.failSummaries(true)
        model.post(input())
        await model.operation?.value
        XCTAssertEqual(model.savedEntry, 1) // SwiftUI observes this counter to clear the submitted form.
        XCTAssertTrue(model.message.contains("Transaksi tersimpan"))
        XCTAssertTrue(model.message.contains("Muat ulang"))
        let initial = await service.counts()
        XCTAssertEqual(initial.committedEntries, 1)
        XCTAssertEqual(initial.postKeys.count, 1)
        model.post(input()) // A stale form resubmission before any successful refresh must replay.
        await model.operation?.value
        let repeated = await service.counts()
        XCTAssertEqual(repeated.committedEntries, 1)
        XCTAssertEqual(repeated.postKeys.count, 2)
        XCTAssertEqual(Set(repeated.postKeys).count, 1)
        XCTAssertEqual(model.savedEntry, 1)
        await service.failSummaries(false)
        model.run { try await model.refresh() }
        await model.operation?.value
        let reloaded = await service.counts()
        XCTAssertEqual(reloaded.committedEntries, 1)
        XCTAssertEqual(reloaded.postKeys.count, 2)
        XCTAssertEqual(model.summary?.expense, "1234.56")
        model.post(input()) // After a fresh snapshot, identical content can be a new expense.
        await model.operation?.value
        let newWrite = await service.counts()
        XCTAssertEqual(newWrite.committedEntries, 2)
        XCTAssertEqual(Set(newWrite.postKeys).count, 2)
        XCTAssertEqual(model.savedEntry, 2)
    }

    func testLostPostResponseRetainsKeyDespiteSecondTapWhileBusy() async throws {
        let (model, service, identity) = try await fixture()
        await login(model, identity)
        let gate = await service.hold(.post)
        model.post(input())
        let first = model.operation
        await fulfillment(of: [gate.entered], timeout: 3)
        model.post(input(amount: "99.00")) // Suppressed duplicate tap must not replace retry identity.
        await gate.resume(throwing: URLError(.networkConnectionLost))
        await first?.value
        XCTAssertEqual(model.savedEntry, 0)
        XCTAssertTrue(model.isError)
        model.post(input())
        await model.operation?.value
        let counts = await service.counts()
        XCTAssertEqual(counts.committedEntries, 1)
        XCTAssertEqual(counts.postKeys.count, 2)
        XCTAssertEqual(Set(counts.postKeys).count, 1)
        XCTAssertEqual(model.savedEntry, 1)
    }

    func testWalletCommitRefreshFailureAndLostResponseRetryAreDistinct() async throws {
        let (model, service, identity) = try await fixture()
        await login(model, identity)
        let gate = await service.hold(.wallet)
        model.wallet(" Dana ")
        let first = model.operation
        await fulfillment(of: [gate.entered], timeout: 3)
        await gate.resume(throwing: URLError(.networkConnectionLost))
        await first?.value
        XCTAssertEqual(model.savedWallet, 0)
        await service.failSummaries(true)
        model.wallet("Dana")
        await model.operation?.value
        XCTAssertEqual(model.savedWallet, 1)
        XCTAssertTrue(model.message.contains("Dompet tersimpan"))
        let counts = await service.counts()
        XCTAssertEqual(counts.committedWallets, 1)
        XCTAssertEqual(Set(counts.walletKeys).count, 1)
        model.wallet(" Dana ")
        await model.operation?.value
        let repeated = await service.counts()
        XCTAssertEqual(repeated.committedWallets, 1)
        XCTAssertEqual(repeated.walletKeys.count, 3)
        XCTAssertEqual(Set(repeated.walletKeys).count, 1)
        XCTAssertEqual(model.savedWallet, 1)
        await service.failSummaries(false)
        model.run { try await model.refresh() }
        await model.operation?.value
        XCTAssertEqual(model.wallets.filter { $0.name == "Dana" }.count, 1)
        model.wallet("Dana")
        await model.operation?.value
        let newWrite = await service.counts()
        XCTAssertEqual(newWrite.committedWallets, 2)
        XCTAssertEqual(Set(newWrite.walletKeys).count, 2)
        XCTAssertEqual(model.savedWallet, 2)
    }

    private func input(amount: String = "1234.56") -> TransactionInput {
        TransactionInput(wallet_id: "33333333-3333-4333-8333-333333333333", kind: "expense", amount: amount, category: "Uji", description: "Synthetic", effective_on: "2026-09-27")
    }
}

private actor Suspension {
    nonisolated let entered = XCTestExpectation(description: "Controlled transport reached suspension")
    private var continuation: CheckedContinuation<Void, Error>?
    func wait() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            entered.fulfill()
        }
    }
    func resume(throwing error: Error? = nil) {
        guard let continuation else { return }
        self.continuation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }
}

private enum RequestPoint: Hashable, Sendable {
    case registration(String), authentication(String), profile(String), revocation(String), post, wallet
}

private actor ControlledService: PalmyService {
    struct Counts: Sendable {
        let registrations: Int; let authentications: Int; let profiles: Int
        let revoked: [String]; let committedEntries: Int; let committedWallets: Int
        let postKeys: [String]; let walletKeys: [String]
    }
    private var accounts: [String: (Identity, Profile)] = [:]
    private var sessions: [String: String] = [:]
    private var latestTokens: [String: String] = [:]
    private var gates: [RequestPoint: Suspension] = [:]
    private var registrationCount = 0
    private var authenticationCount = 0
    private var profileCount = 0
    private var revoked: [String] = []
    private(set) var revokeCalls: [String] = []
    private var postKeys: [String] = []
    private var walletKeys: [String] = []
    private var posted: [String: TransactionInput] = [:]
    private var createdWallets: [String: String] = [:]
    private var summaryFailure = false

    func seed(_ identity: Identity, name: String) { accounts[identity.accountID] = (identity, Profile(display_name: name, email: "synthetic@example.invalid")) }
    func hold(_ point: RequestPoint) -> Suspension { let gate = Suspension(); gates[point] = gate; return gate }
    private func pause(_ point: RequestPoint) async throws { if let gate = gates.removeValue(forKey: point) { try await gate.wait() } }
    func token(for account: String) -> String { latestTokens[account] ?? "missing-synthetic-session" }
    func failSummaries(_ value: Bool) { summaryFailure = value }
    func counts() -> Counts { Counts(registrations: registrationCount, authentications: authenticationCount, profiles: profileCount, revoked: revoked, committedEntries: posted.count, committedWallets: createdWallets.count, postKeys: postKeys, walletKeys: walletKeys) }

    func register(_ identity: Identity, profile: Profile) async throws {
        registrationCount += 1; accounts[identity.accountID] = (identity, profile)
        try await pause(.registration(identity.accountID))
    }
    func authenticate(_ identity: Identity) async throws -> Session {
        authenticationCount += 1
        let token = "synthetic-session-\(authenticationCount)"
        sessions[token] = identity.accountID; latestTokens[identity.accountID] = token
        try await pause(.authentication(identity.accountID))
        return Session(access_token: token, expires_at: "2026-09-27T23:00:00Z")
    }
    func profile(token: String) async throws -> ProfileResponse {
        profileCount += 1
        guard let owner = sessions[token], let (identity, profile) = accounts[owner] else { throw APIError(status: 401, message: "Unknown synthetic session") }
        try await pause(.profile(owner))
        return ProfileResponse(account_id: owner, profile: try identity.seal(profile), version: 1)
    }
    func saveProfile(_ profile: Profile, identity: Identity, version: Int, token: String) async throws -> ProfileResponse {
        accounts[identity.accountID] = (identity, profile)
        return ProfileResponse(account_id: identity.accountID, profile: try identity.seal(profile), version: version + 1)
    }
    func summary(token: String) async throws -> Summary {
        if summaryFailure { throw APIError(status: 503, message: "Synthetic summary unavailable") }
        return Summary(balance: posted.isEmpty ? "2000.00" : "765.44", income: "2000.00", expense: posted.isEmpty ? "0.00" : "1234.56", currency: "IDR")
    }
    func wallets(token: String) async throws -> [Wallet] {
        [Wallet(id: "33333333-3333-4333-8333-333333333333", name: "Awal", balance: "2000.00", currency: "IDR")] + createdWallets.map { Wallet(id: $0.key, name: $0.value, balance: "0.00", currency: "IDR") }
    }
    func entries(token: String, before: String?) async throws -> EntryPage {
        EntryPage(data: posted.map { FinanceEntry(id: $0.key, wallet_id: $0.value.wallet_id, kind: $0.value.kind, amount: $0.value.amount, category: $0.value.category, description: $0.value.description, effective_on: $0.value.effective_on, created_at: "2026-09-27T00:00:00Z") }, next_cursor: nil)
    }
    func createWallet(name: String, token: String, key: String) async throws {
        walletKeys.append(key); createdWallets[key] = name
        try await pause(.wallet)
    }
    func post(_ input: TransactionInput, token: String, key: String) async throws {
        postKeys.append(key)
        if let previous = posted[key], previous != input { throw APIError(status: 409, message: "Conflicting synthetic key") }
        posted[key] = input
        try await pause(.post)
    }
    func revoke(token: String) async throws {
        revokeCalls.append(token)
        try await pause(.revocation(token))
        revoked.append(token); sessions.removeValue(forKey: token)
    }
}
