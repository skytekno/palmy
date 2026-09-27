import Combine
import Foundation

/// Shared by SwiftUI and deterministic lifecycle tests. Credentials never leave memory.
@MainActor public final class AppModel: ObservableObject {
    @Published public private(set) var identity: Identity?
    @Published public private(set) var pendingIdentity: Identity?
    @Published public var profile = Profile(display_name: "", email: "")
    @Published public private(set) var summary: Summary?
    @Published public private(set) var wallets: [Wallet] = []
    @Published public private(set) var entries: [FinanceEntry] = []
    @Published public private(set) var cursor: String?
    @Published public private(set) var busy = false
    @Published public private(set) var message = ""
    @Published public private(set) var isError = false
    @Published public private(set) var savedWallet = 0
    @Published public private(set) var savedEntry = 0

    private let apiFactory: @Sendable () throws -> any PalmyService
    private var token: String?
    private var profileVersion = 1
    private var generation = UUID()
    // Internal task handles let tests await controlled completions, including superseded work.
    private(set) var operation: Task<Void, Never>?
    private(set) var revocation: Task<Void, Never>?
    private struct WriteRetry<Value: Equatable> {
        let input: Value
        let key: String
        var committed = false
    }
    private var walletRetry: WriteRetry<String>?
    private var entryRetry: WriteRetry<TransactionInput>?

    public init(apiFactory: @escaping @Sendable () throws -> any PalmyService) { self.apiFactory = apiFactory }

    public func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; message = ""; isError = false
        // A new attempt also supersedes delayed logout feedback while identity is still nil.
        generation = UUID()
        let expected = generation
        operation = Task { [weak self] in
            guard let self else { return }
            do { try ensureCurrent(expected); try await action() }
            catch is CancellationError { /* Lock already owns the visible state. */ }
            catch { if generation == expected { message = error.localizedDescription; isError = true } }
            if generation == expected { busy = false }
        }
    }

    private func ensureCurrent(_ expected: UUID) throws {
        try Task.checkCancellation()
        guard generation == expected else { throw CancellationError() }
    }

    public func prepare() {
        guard !busy, identity == nil else { return }
        do { pendingIdentity = try Identity.create() } catch { message = error.localizedDescription; isError = true }
    }
    public func cancelPrepare() { guard !busy else { return }; pendingIdentity = nil }

    public func create() {
        guard let pending = pendingIdentity else { return }
        run {
            let expected = self.generation
            do { try await self.apiFactory().register(pending, profile: self.profile) }
            catch let error as APIError where error.status == 409 { /* Lost registration response: prove possession next. */ }
            try self.ensureCurrent(expected)
            try await self.open(pending)
            self.pendingIdentity = nil
        }
    }

    public func recover(_ recovery: String) { run { try await self.open(Identity(recovery: recovery)) } }

    private func open(_ candidate: Identity) async throws {
        let expected = generation
        let api = try apiFactory()
        let session = try await api.authenticate(candidate)
        do {
            try ensureCurrent(expected)
            let stored = try await api.profile(token: session.access_token)
            try ensureCurrent(expected)
            let decrypted = try candidate.open(stored.profile)
            let dashboard = try await loadDashboard(api: api, token: session.access_token)
            try ensureCurrent(expected)
            // Publish authentication/profile/finance together, only after every read succeeds.
            token = session.access_token; identity = candidate; profile = decrypted; profileVersion = stored.version
            publish(dashboard)
        } catch {
            revoke(session.access_token, using: api)
            if generation == expected { clearAuthenticatedState() }
            throw error
        }
    }

    private struct Dashboard { let summary: Summary; let wallets: [Wallet]; let page: EntryPage }
    private func loadDashboard(api: any PalmyService, token: String) async throws -> Dashboard {
        async let summary = api.summary(token: token)
        async let wallets = api.wallets(token: token)
        async let page = api.entries(token: token)
        return try await Dashboard(summary: summary, wallets: wallets, page: page)
    }
    private func publish(_ dashboard: Dashboard) {
        summary = dashboard.summary; wallets = dashboard.wallets; entries = dashboard.page.data; cursor = dashboard.page.next_cursor
        // Only a fresh snapshot releases confirmed writes for a genuinely new submission.
        if walletRetry?.committed == true { walletRetry = nil }
        if entryRetry?.committed == true { entryRetry = nil }
    }

    public func refresh() async throws {
        guard let token else { return }
        let expected = generation
        let dashboard = try await loadDashboard(api: apiFactory(), token: token)
        try ensureCurrent(expected)
        publish(dashboard)
    }

    public func more() {
        guard let cursor, let token else { return }
        run {
            let expected = self.generation
            let page = try await self.apiFactory().entries(token: token, before: cursor)
            try self.ensureCurrent(expected)
            self.entries += page.data; self.cursor = page.next_cursor
        }
    }

    public func wallet(_ name: String) {
        guard !busy, let token else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if walletRetry?.input != name { walletRetry = WriteRetry(input: name, key: UUID().uuidString.lowercased()) }
        guard let key = walletRetry?.key else { return }
        run {
            let expected = self.generation
            try await self.apiFactory().createWallet(name: name, token: token, key: key)
            try self.ensureCurrent(expected)
            if self.walletRetry?.committed == false { self.savedWallet += 1 }
            self.walletRetry?.committed = true
            do { try await self.refresh(); self.message = "Dompet tersimpan." }
            catch { try self.ensureCurrent(expected); self.message = "Dompet tersimpan. Gagal memuat daftar terbaru; gunakan Muat ulang."; self.isError = true }
        }
    }

    public func post(_ input: TransactionInput) {
        guard !busy, let token else { return }
        if entryRetry?.input != input { entryRetry = WriteRetry(input: input, key: UUID().uuidString.lowercased()) }
        guard let key = entryRetry?.key else { return }
        run {
            let expected = self.generation
            try await self.apiFactory().post(input, token: token, key: key)
            try self.ensureCurrent(expected)
            if self.entryRetry?.committed == false { self.savedEntry += 1 }
            self.entryRetry?.committed = true
            do { try await self.refresh(); self.message = "Transaksi tersimpan." }
            catch { try self.ensureCurrent(expected); self.message = "Transaksi tersimpan. Gagal memuat saldo terbaru; gunakan Muat ulang."; self.isError = true }
        }
    }

    public func saveProfile() {
        guard let identity, let token else { return }
        run {
            let expected = self.generation
            let stored = try await self.apiFactory().saveProfile(self.profile, identity: identity, version: self.profileVersion, token: token)
            try self.ensureCurrent(expected)
            self.profileVersion = stored.version; self.message = "Profil terenkripsi tersimpan."
        }
    }

    public func reloadProfile() {
        guard let identity, let token else { return }
        run {
            let expected = self.generation
            let stored = try await self.apiFactory().profile(token: token)
            try self.ensureCurrent(expected)
            self.profile = try identity.open(stored.profile); self.profileVersion = stored.version; self.message = "Profil terbaru dimuat."
        }
    }

    /// Idle onboarding may survive a trip to a password manager; any active/private session may not.
    public func didEnterBackground() { if identity != nil || busy { lock() } }

    private func clearAuthenticatedState() {
        identity = nil; token = nil; profile = Profile(display_name: "", email: "")
        summary = nil; wallets = []; entries = []; cursor = nil
        walletRetry = nil; entryRetry = nil
        profileVersion = 1; savedWallet = 0; savedEntry = 0
    }

    public func lock() {
        let previous = token; let api = try? apiFactory()
        operation?.cancel(); generation = UUID()
        clearAuthenticatedState(); pendingIdentity = nil
        busy = false; message = "Aplikasi terkunci. Gunakan kunci pemulihan untuk membuka kembali."; isError = false
        if let previous, let api { revoke(previous, using: api, lockedGeneration: generation) }
    }

    private func revoke(_ token: String, using api: any PalmyService, lockedGeneration: UUID? = nil) {
        // Independent of the cancelled operation: best-effort cleanup still reaches transport.
        revocation = Task {
            do { try await api.revoke(token: token) }
            catch {
                if let lockedGeneration, self.generation == lockedGeneration && self.identity == nil {
                    self.message = "Terkunci di perangkat. Pencabutan sesi gagal; sesi server kedaluwarsa dalam 1 jam."
                }
            }
        }
    }
}
