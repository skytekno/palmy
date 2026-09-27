import Foundation

public struct Wallet: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let balance: String
    public let currency: String
}
public struct FinanceEntry: Codable, Identifiable, Sendable {
    public let id: String
    public let wallet_id: String
    public let kind: String
    public let amount: String
    public let category: String
    public let description: String
    public let effective_on: String
    public let created_at: String
}
public struct Summary: Codable, Sendable { public let balance: String; public let income: String; public let expense: String; public let currency: String }
public struct ProfileResponse: Codable, Sendable { public let account_id: String; public let profile: Envelope; public let version: Int }
public struct Challenge: Codable, Sendable { public let challenge_id: String; public let nonce: String; public let expires_at: String }
public struct Session: Codable, Sendable { public let access_token: String; public let expires_at: String }
public struct Account: Codable, Sendable { public let account_id: String }
public struct Wrapped<T: Decodable & Sendable>: Decodable, Sendable { public let data: T }
public struct EntryPage: Decodable, Sendable { public let data: [FinanceEntry]; public let next_cursor: String? }
public struct TransactionInput: Codable, Sendable, Equatable {
    public let wallet_id: String; public let kind: String; public let amount: String; public let category: String; public let description: String; public let effective_on: String
    public init(wallet_id: String, kind: String, amount: String, category: String, description: String, effective_on: String) {
        self.wallet_id = wallet_id; self.kind = kind; self.amount = amount; self.category = category; self.description = description; self.effective_on = effective_on
    }
}
private struct Registration: Encodable { let account_id: String; let public_key: String; let profile: Envelope; let signature: String }
private struct ChallengeInput: Encodable { let account_id: String }
private struct SessionInput: Encodable { let account_id: String; let challenge_id: String; let signature: String }
private struct ProfileInput: Encodable { let profile: Envelope; let version: Int }
private struct WalletInput: Encodable { let name: String }
private struct Problem: Decodable { let title: String?; let code: String? }
public struct APIError: Error, LocalizedError {
    public let status: Int; public let message: String
    public init(status: Int, message: String) { self.status = status; self.message = message }
    public var errorDescription: String? { message }
}

public struct API: Sendable {
    public let baseURL: URL
    public init(baseURL: URL) throws {
        #if DEBUG
        let development = baseURL.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(baseURL.host ?? "")
        #else
        let development = false
        #endif
        guard baseURL.scheme == "https" || development, baseURL.user == nil, baseURL.password == nil, baseURL.query == nil, baseURL.fragment == nil else { throw APIError(status: 0, message: "Gunakan URL API HTTPS yang tepercaya.") }
        self.baseURL = baseURL
    }
    private func request(_ path: String, method: String = "GET", body: Data? = nil, token: String? = nil, key: String? = nil) async throws -> Data {
        guard let url = URL(string: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let key { request.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let problem = try? JSONDecoder().decode(Problem.self, from: data)
            throw APIError(status: status, message: problem?.title ?? "Permintaan gagal (\(status)). Coba lagi.")
        }
        return data
    }
    public func register(_ identity: Identity, profile: Profile) async throws {
        let envelope = try identity.seal(profile)
        let body = try JSONEncoder().encode(Registration(account_id: identity.accountID, public_key: identity.publicKey, profile: envelope, signature: identity.registrationSignature(envelope)))
        _ = try await request("/accounts", method: "POST", body: body)
    }
    public func authenticate(_ identity: Identity) async throws -> Session {
        let challengeData = try await request("/auth/challenges", method: "POST", body: JSONEncoder().encode(ChallengeInput(account_id: identity.accountID)))
        let challenge = try JSONDecoder().decode(Wrapped<Challenge>.self, from: challengeData).data
        let body = try JSONEncoder().encode(SessionInput(account_id: identity.accountID, challenge_id: challenge.challenge_id, signature: identity.challengeSignature(id: challenge.challenge_id, nonce: challenge.nonce)))
        return try await JSONDecoder().decode(Wrapped<Session>.self, from: request("/auth/sessions", method: "POST", body: body)).data
    }
    public func profile(token: String) async throws -> ProfileResponse { try await JSONDecoder().decode(Wrapped<ProfileResponse>.self, from: request("/profile", token: token)).data }
    public func saveProfile(_ profile: Profile, identity: Identity, version: Int, token: String) async throws -> ProfileResponse {
        let body = try JSONEncoder().encode(ProfileInput(profile: identity.seal(profile), version: version))
        return try await JSONDecoder().decode(Wrapped<ProfileResponse>.self, from: request("/profile", method: "PUT", body: body, token: token)).data
    }
    public func wallets(token: String) async throws -> [Wallet] { try await JSONDecoder().decode(Wrapped<[Wallet]>.self, from: request("/wallets", token: token)).data }
    public func summary(token: String) async throws -> Summary { try await JSONDecoder().decode(Wrapped<Summary>.self, from: request("/summary", token: token)).data }
    public func entries(token: String, before: String? = nil) async throws -> EntryPage {
        if let before, UUID(uuidString: before) == nil { throw APIError(status: 0, message: "Kursor tidak valid.") }
        return try await JSONDecoder().decode(EntryPage.self, from: request("/transactions?limit=25" + (before.map { "&before=\($0)" } ?? ""), token: token))
    }
    public func createWallet(name: String, token: String, key: String) async throws {
        _ = try await request("/wallets", method: "POST", body: JSONEncoder().encode(WalletInput(name: name)), token: token, key: key)
    }
    public func post(_ input: TransactionInput, token: String, key: String) async throws {
        _ = try await request("/transactions", method: "POST", body: JSONEncoder().encode(input), token: token, key: key)
    }
    public func revoke(token: String) async throws { _ = try await request("/auth/session", method: "DELETE", token: token) }
}

public enum Money {
    public static func validPositive(_ text: String) -> Bool {
        text.range(of: "^(0|[1-9][0-9]{0,15})(\\.[0-9]{1,2})?$", options: .regularExpression) != nil && Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? 0 > 0
    }
    public static func display(_ text: String) -> String {
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { return "—" }
        let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "id_ID"); formatter.numberStyle = .currency; formatter.currencyCode = "IDR"; formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "IDR \(text)"
    }
}
