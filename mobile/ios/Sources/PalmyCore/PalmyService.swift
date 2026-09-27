import Foundation

/// The app state depends on this boundary; production always uses the real HTTP API.
/// Tests control response ordering here without replacing the state logic or cryptography.
public protocol PalmyService: Sendable {
    func register(_ identity: Identity, profile: Profile) async throws
    func authenticate(_ identity: Identity) async throws -> Session
    func profile(token: String) async throws -> ProfileResponse
    func saveProfile(_ profile: Profile, identity: Identity, version: Int, token: String) async throws -> ProfileResponse
    func wallets(token: String) async throws -> [Wallet]
    func summary(token: String) async throws -> Summary
    func entries(token: String, before: String?) async throws -> EntryPage
    func createWallet(name: String, token: String, key: String) async throws
    func post(_ input: TransactionInput, token: String, key: String) async throws
    func revoke(token: String) async throws
}

extension PalmyService {
    public func entries(token: String) async throws -> EntryPage { try await entries(token: token, before: nil) }
}

extension API: PalmyService {}
