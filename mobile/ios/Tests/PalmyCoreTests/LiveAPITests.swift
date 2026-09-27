import XCTest
@testable import PalmyCore

final class LiveAPITests: XCTestCase {
    func testNativeCryptoAndFinanceOverHTTP() async throws {
        guard let address = ProcessInfo.processInfo.environment["PALMY_TEST_API_URL"] else { throw XCTSkip("Set PALMY_TEST_API_URL for disposable local API integration.") }
        let endpoint = address.hasSuffix("/api/v1") ? address : address.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/v1"
        let api = try API(baseURL: XCTUnwrap(URL(string: endpoint)))
        let identity = try Identity.create()
        let profile = Profile(display_name: "Native synthetic", email: "native@example.invalid")
        try await api.register(identity, profile: profile)
        let session = try await api.authenticate(identity)
        let stored = try await api.profile(token: session.access_token)
        XCTAssertEqual(try identity.open(stored.profile), profile)
        let edited = Profile(display_name: "Native edited", email: "edited@example.invalid")
        let saved = try await api.saveProfile(edited, identity: identity, version: stored.version, token: session.access_token)
        XCTAssertEqual(try identity.open(saved.profile), edited)
        XCTAssertEqual(saved.version, stored.version + 1)
        let walletKey = UUID().uuidString.lowercased()
        try await api.createWallet(name: "Native test", token: session.access_token, key: walletKey)
        try await api.createWallet(name: "Native test", token: session.access_token, key: walletKey)
        let wallets = try await api.wallets(token: session.access_token)
        XCTAssertEqual(wallets.count, 1)
        let wallet = try XCTUnwrap(wallets.first)
        let input = TransactionInput(wallet_id: wallet.id, kind: "income", amount: "1234.56", category: "Uji", description: "Synthetic native test", effective_on: "2026-09-27")
        let key = UUID().uuidString.lowercased()
        try await api.post(input, token: session.access_token, key: key)
        try await api.post(input, token: session.access_token, key: key)
        let summary = try await api.summary(token: session.access_token)
        XCTAssertEqual(summary.balance, "1234.56")
        XCTAssertEqual(summary.income, "1234.56")
        let entries = try await api.entries(token: session.access_token)
        XCTAssertEqual(entries.data.count, 1)
        try await api.revoke(token: session.access_token)
        do { _ = try await api.profile(token: session.access_token); XCTFail("Revoked session must fail") } catch let error as APIError { XCTAssertEqual(error.status, 401) }
        let recovered = try Identity(recovery: identity.recovery)
        let second = try await api.authenticate(recovered)
        let recoveredProfile = try await api.profile(token: second.access_token)
        XCTAssertEqual(try recovered.open(recoveredProfile.profile), edited)
        try await api.revoke(token: second.access_token)
    }
}
